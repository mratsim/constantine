# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internal
  ../../platforms/abstractions,
  ./limbs, ./limbs_extmul

when UseASM_X86_32:
  import ./assembly/limbs_asm_redc_mont_x86
when UseASM_X86_64:
  import
    ./assembly/limbs_asm_mul_mont_x86,
    ./assembly/limbs_asm_mul_mont_x86_adx_bmi2,
    ./assembly/limbs_asm_redc_mont_x86_adx_bmi2

# ############################################################
#
#         Multiprecision Montgomery Arithmetic
#
# ############################################################
#
# Note: Montgomery multiplications and squarings are the biggest bottlenecks
#       of an elliptic curve library, asymptotically 100% of the costly algorithms:
#       - field exponentiation
#       - field inversion via Little Fermat
#       - extension towers multiplication, squarings, inversion
#       - elliptic curve point addition
#       - elliptic curve point doubling
#       - elliptic curve point multiplication
#       - pairing Miller Loop
#       - pairing final exponentiation
#       are bottlenecked by Montgomery multiplications or squarings
#
# Inlining note:
# - The public dispatch functions are inlined.
#   This allows the compiler to check CPU features only once
#   in the high-level proc and also removes an intermediate function call
#   to the wrapper function
# - The ASM procs or internal fallbacks are not inlined
#   to save on code size.

# No exceptions allowed
{.push raises: [], checks: off.}

# Montgomery Reduction
# ------------------------------------------------------------
func redc2xMont_CIOS[N: static int](
       r: var array[N, SecretWord],
       a: array[N*2, SecretWord],
       M: array[N, SecretWord],
       m0ninv: BaseType, skipFinalSub: static bool = false) =
  ## Montgomery reduce a double-precision bigint modulo M
  ##
  ## This maps
  ## - [0, 4p²) -> [0, 2p) with skipFinalSub
  ## - [0, 4p²) -> [0, p) without
  ##
  ## skipFinalSub skips the final substraction step.
  # - Analyzing and Comparing Montgomery Multiplication Algorithms
  #   Cetin Kaya Koc and Tolga Acar and Burton S. Kaliski Jr.
  #   http://pdfs.semanticscholar.org/5e39/41ff482ec3ee41dc53c3298f0be085c69483.pdf
  #
  # - Arithmetic of Finite Fields
  #   Chapter 5 of Guide to Pairing-Based Cryptography
  #   Jean Luc Beuchat, Luis J. Dominguez Perez, Sylvain Duquesne, Nadia El Mrabet, Laura Fuentes-Castañeda, Francisco Rodríguez-Henríquez, 2017
  #   https://www.researchgate.net/publication/319538235_Arithmetic_of_Finite_Fields
  #
  # Algorithm
  # Inputs:
  # - N number of limbs
  # - a[0 ..< 2N] (double-precision input to reduce)
  # - M[0 ..< N] The field modulus (must be odd for Montgomery reduction)
  # - m0ninv: Montgomery Reduction magic number = -1/M[0]
  # Output:
  # - r[0 ..< N], in the Montgomery domain
  # Parameters:
  # - w, the word width usually 64 on 64-bit platforms or 32 on 32-bit
  #
  # for i in 0 .. n-1:
  #   C <- 0
  #   m <- a[i] * m0ninv mod 2ʷ (i.e. simple multiplication)
  #   for j in 0 .. n-1:
  #     (C, S) <- a[i+j] + m * M[j] + C
  #     a[i+j] <- S
  #   a[i+n] += C
  # for i in 0 .. n-1:
  #   r[i] = a[i+n]
  # if r >= M:
  #   r -= M
  #
  # Important note: `a[i+n] += C` should propagate the carry
  # to the higher limb if any, thank you "implementation detail"
  # missing from paper.

  var a {.noInit.} = a # Copy "t" for mutation and ensure on stack
  var res {.noInit.}: typeof(r)   # Accumulator
  staticFor i, 0, N:
    var C = Zero
    let m = a[i] * SecretWord(m0ninv)
    staticFor j, 0, N:
      muladd2(C, a[i+j], m, M[j], a[i+j], C)
    res[i] = C

  # This does t[i+n] += C
  # but in a separate carry chain, fused with the
  # copy "r[i] = t[i+n]"
  var carry = Carry(0)
  staticFor i, 0, N:
    addC(carry, res[i], a[i+N], res[i], carry)

  # Final substraction
  when not skipFinalSub:
    discard res.csub(M, SecretWord(carry).isNonZero() or not(res < M))
  r = res

func redc2xMont_Comba[N: static int](
       r: var array[N, SecretWord],
       a: array[N*2, SecretWord],
       M: array[N, SecretWord],
       m0ninv: BaseType, skipFinalSub: static bool = false) {.used.} =
  ## Montgomery reduce a double-precision bigint modulo M
  ##
  ## This maps
  ## - [0, 4p²) -> [0, 2p) with skipFinalSub
  ## - [0, 4p²) -> [0, p) without
  ##
  ## skipFinalSub skips the final substraction step.
  # We use Product Scanning / Comba multiplication
  var t, u, v = Zero
  var carry: Carry
  var z: typeof(r) # zero-init, ensure on stack and removes in-place problems in tower fields
  staticFor i, 0, N:
    staticFor j, 0, i:
      mulAcc(t, u, v, z[j], M[i-j])

    addC(carry, v, v, a[i], Carry(0))
    addC(carry, u, u, Zero, carry)
    addC(carry, t, t, Zero, carry)

    z[i] = v * SecretWord(m0ninv)
    mulAcc(t, u, v, z[i], M[0])
    v = u
    u = t
    t = Zero

  staticFor i, N, 2*N-1:
    staticFor j, i-N+1, N:
      mulAcc(t, u, v, z[j], M[i-j])

    addC(carry, v, v, a[i], Carry(0))
    addC(carry, u, u, Zero, carry)
    addC(carry, t, t, Zero, carry)

    z[i-N] = v

    v = u
    u = t
    t = Zero

  addC(carry, z[N-1], v, a[2*N-1], Carry(0))

  # Final substraction
  when not skipFinalSub:
    discard z.csub(M, SecretBool(carry) or not(z < M))
  r = z

# Montgomery Multiplication
# ------------------------------------------------------------

func mulMont_CIOS_sparebit(r: var Limbs, a, b, M: Limbs, m0ninv: BaseType, skipFinalSub: static bool = false) =
  ## Montgomery Multiplication using Coarse Grained Operand Scanning (CIOS)
  ## and no-carry optimization.
  ## This requires the most significant word of the Modulus
  ##   M[^1] < high(SecretWord) shr 1 (i.e. less than 0b01111...1111)
  ## https://hackmd.io/@gnark/modular_multiplication
  ##
  ## This maps
  ## - [0, 2p) -> [0, 2p) with skipFinalSub
  ## - [0, 2p) -> [0, p) without
  ##
  ## skipFinalSub skips the final substraction step.

  # We want all the computation to be kept in registers
  # hence we use a temporary `t`, hoping that the compiler does it.
  var t: typeof(M) # zero-init
  const N = t.len
  staticFor i, 0, N:
    # (A, t[0]) <- a[0] * b[i] + t[0]
    #  m        <- (t[0] * m0ninv) mod 2ʷ
    # (C, _)    <- m * M[0] + t[0]
    var A: SecretWord
    muladd1(A, t[0], a[0], b[i], t[0])
    let m = t[0] * SecretWord(m0ninv)
    var C, lo: SecretWord
    muladd1(C, lo, m, M[0], t[0])

    staticFor j, 1, N:
      # (A, t[j])   <- a[j] * b[i] + A + t[j]
      # (C, t[j-1]) <- m * M[j] + C + t[j]
      muladd2(A, t[j], a[j], b[i], A, t[j])
      muladd2(C, t[j-1], m, M[j], C, t[j])

    t[N-1] = C + A

  when not skipFinalSub:
    discard t.csub(M, not(t < M))
  r = t

func mulMont_CIOS(r: var Limbs, a, b, M: Limbs, m0ninv: BaseType) {.used.} =
  ## Montgomery Multiplication using Coarse Grained Operand Scanning (CIOS)
  # - Analyzing and Comparing Montgomery Multiplication Algorithms
  #   Cetin Kaya Koc and Tolga Acar and Burton S. Kaliski Jr.
  #   http://pdfs.semanticscholar.org/5e39/41ff482ec3ee41dc53c3298f0be085c69483.pdf
  #
  # - Montgomery Arithmetic from a Software Perspective\
  #   Joppe W. Bos and Peter L. Montgomery, 2017\
  #   https://eprint.iacr.org/2017/1057

  # We want all the computation to be kept in registers
  # hence we use a temporary `t`, hoping that the compiler does it.
  var t: typeof(M)   # zero-init
  const N = t.len
  # Extra words to handle up to 2 carries t[N] and t[N+1]
  var tN: SecretWord
  var tNp1: Carry

  staticFor i, 0, N:
    var A = Zero
    # Multiplication
    staticFor j, 0, N:
      # (A, t[j]) <- a[j] * b[i] + t[j] + A
      muladd2(A, t[j], a[j], b[i], t[j], A)
    addC(tNp1, tN, tN, A, Carry(0))

    # Reduction
    #  m        <- (t[0] * m0ninv) mod 2ʷ
    # (C, _)    <- m * M[0] + t[0]
    var C, lo = Zero
    let m = t[0] * SecretWord(m0ninv)
    muladd1(C, lo, m, M[0], t[0])
    staticFor j, 1, N:
      # (C, t[j-1]) <- m*M[j] + t[j] + C
      muladd2(C, t[j-1], m, M[j], t[j], C)

    #  (C,t[N-1]) <- t[N] + C
    #  (_, t[N])  <- t[N+1] + C
    var carry: Carry
    addC(carry, t[N-1], tN, C, Carry(0))
    addC(carry, tN, SecretWord(tNp1), Zero, carry)

  # t[N+1] can only be non-zero in the intermediate computation
  # since it is immediately reduce to t[N] at the end of each "i" iteration
  # However if t[N] is non-zero we have t > M
  discard t.csub(M, tN.isNonZero() or not(t < M)) # TODO: (t >= M) is unnecessary for prime in the form (2^64)ʷ
  r = t

func mulMont_FIPS(r: var Limbs, a, b, M: Limbs, m0ninv: BaseType, skipFinalSub: static bool = false) =
  ## Montgomery Multiplication using Finely Integrated Product Scanning (FIPS)
  ##
  ## This maps
  ## - [0, 2p) -> [0, 2p) with skipFinalSub
  ## - [0, 2p) -> [0, p) without
  ##
  ## skipFinalSub skips the final substraction step.
  # - Architectural Enhancements for Montgomery
  #   Multiplication on Embedded RISC Processors
  #   Johann Großschädl and Guy-Armand Kamendje, 2003
  #   https://pure.tugraz.at/ws/portalfiles/portal/2887154/ACNS2003_AEM.pdf
  #
  # - New Speed Records for Montgomery Modular
  #   Multiplication on 8-bit AVR Microcontrollers
  #   Zhe Liu and Johann Großschädl, 2013
  #   https://eprint.iacr.org/2013/882.pdf
  var z: typeof(r) # zero-init, ensure on stack and removes in-place problems in tower fields
  const L = r.len
  var t, u, v = Zero

  staticFor i, 0, L:
    staticFor j, 0, i:
      mulAcc(t, u, v, a[j], b[i-j])
      mulAcc(t, u, v, z[j], M[i-j])
    mulAcc(t, u, v, a[i], b[0])
    z[i] = v * SecretWord(m0ninv)
    mulAcc(t, u, v, z[i], M[0])
    v = u
    u = t
    t = Zero
  staticFor i, L, 2*L:
    staticFor j, i-L+1, L:
      mulAcc(t, u, v, a[j], b[i-j])
      mulAcc(t, u, v, z[j], M[i-j])
    z[i-L] = v
    v = u
    u = t
    t = Zero

  when not skipFinalSub:
    discard z.csub(M, v.isNonZero() or not(z < M))
  r = z

func sumprodMont_CIOS_spare2bits[K: static int](
       r: var Limbs, a, b: array[K, Limbs],
       M: Limbs, m0ninv: BaseType,
       skipFinalSub: static bool = false) =
  ## Compute r = ⅀aᵢ.bᵢ (mod M) (suim of products)
  ## This requires 2 unused bits in the field element representation
  ##
  ## This maps
  ## - [0, 2p) -> [0, 2p) with skipFinalSub
  ## - [0, 2p) -> [0, p) without
  ##
  ## skipFinalSub skips the final substraction step.

  # We want all the computation to be kept in registers
  # hence we use a temporary `t`, hoping that the compiler does the right thing™.
  var t: typeof(M)   # zero-init
  const N = t.len
  # Extra word to handle carries t[N] (not there are 2 unused spare bits)
  var tN {.noInit.}: SecretWord

  static: doAssert K <= 8, "we cannot sum more than 8 products"
  # Bounds:
  # 1. To ensure mapping in [0, 2p), we need ⅀aᵢ.bᵢ <=pR
  #    for all intent and purposes this is true since aᵢ.bᵢ is:
  #    if reduced inputs: (p-1).(p-1) = p²-2p+1 which would allow more than p sums
  #    if unreduced inputs: (2p-1).(2p-1) = 4p²-4p+1,
  #    with 4p < R due to the 2 unused bits constraint so more than p sums are allowed
  # 2. We have a high-word tN to accumulate overflows.
  #    with 2 unused bits in the last word,
  #    the multiplication of two last words will leave 4 unused bits
  #    enough for accumulating 8 additions and overflow.

  staticFor i, 0, N:
    tN = Zero
    staticFor k, 0, K:
      var A = Zero
      staticFor j, 0, N:
        # (A, t[j]) <- a[k][j] * b[k][i] + t[j] + A
        muladd2(A, t[j], a[k][j], b[k][i], t[j], A)
      tN += A

    # Reduction
    #  m        <- (t[0] * m0ninv) mod 2ʷ
    # (C, _)    <- m * M[0] + t[0]
    var C, lo = Zero
    let m = t[0] * SecretWord(m0ninv)
    muladd1(C, lo, m, M[0], t[0])
    staticFor j, 1, N:
      # (C, t[j-1]) <- m*M[j] + t[j] + C
      muladd2(C, t[j-1], m, M[j], t[j], C)
    #  (_,t[N-1]) <- t[N] + C
    t[N-1] = tN + C

  when not skipFinalSub:
    discard t.csub(M, not(t < M))
  r = t


# Montgomery Squaring
# --------------------------------------------------------------------------------------------------------------------
#
# There are Montgomery squaring multiplications mentioned in the litterature
# - https://hackmd.io/@gnark/modular_multiplication if M[^1] < high(SecretWord) shr 2 (i.e. less than 0b00111...1111)
# - Architectural Support for Long Integer Modulo Arithmetic on Risc-Based Smart Cards
#   Johann Großschädl, 2003
#   https://citeseerx.ist.psu.edu/viewdoc/download;jsessionid=95950BAC26A728114431C0C7B425E022?doi=10.1.1.115.3276&rep=rep1&type=pdf
# - Analyzing and Comparing Montgomery Multiplication Algorithms
#   Koc, Acar, Kaliski, 1996
#   https://www.semanticscholar.org/paper/Analyzing-and-comparing-Montgomery-multiplication-Ko%C3%A7-Acar/5e3941ff482ec3ee41dc53c3298f0be085c69483
#
# However fuzzing the implementation showed off-by-one on certain inputs especially in 32-bit mode
#
# for Fp[BLS12-381] on 32 bit with inputs
# - 0x091F02EFA1C9B99C004329E94CD3C6B308164CBE02037333D78B6C10415286F7C51B5CD7F917F77B25667AB083314B1B
# - 0x0B7C8AFE5D43E9A973AF8649AD8C733B97D06A78CFACD214CBE9946663C3F682362E0605BC8318714305B249B505AFD9
# for Consensys/zkteam algorithm (off by one in least significant bit)
#
# for Fp[2^127 - 1] with inputs
# - -0x75bfffefbfffffff7fd9dfd800000000
# - -0x7ff7ffffffffffff1dfb7fafc0000000
# Squaring the number and its opposite
# should give the same result, but those are off-by-one
# with Großschädl algorithm
#
# I suspect either I did a twice the same mistake when translating 2 different algorithms
# or there is a carry propagation constraint that prevents interleaving squaring
# and Montgomery reduction in the following loops
# for i in 0 ..< N:
#   for j in i+1 ..< N:     # <-- squaring, notice that we start at i+1 but carries from below may still impact us.
#     ...
#   for j in 1 ..< N:       # <- Montgomery reduce.

# Montgomery Conversion
# ------------------------------------------------------------
#
# In Montgomery form, inputs are scaled by a constant R
# so a' = aR (mod p) and b' = bR (mod p)
#
# A classic multiplication would do a'*b' = abR² (mod p)
# we then need to remove the extra R, hence:
# - Montgomery reduction (redc) does 1/R (mod p) to map abR² (mod p) -> abR (mod p)
# - Montgomery multiplication directly compute mulMont(aR, bR) = abR (mod p)
#
# So to convert a to a' = aR (mod p), we can do mulMont(a, R²) = aR (mod p)
# and to convert a' to a = aR / R (mod p) we can do:
# - redc(aR) = a
# - or mulMont(aR, 1) = a

func fromMont_CIOS(r: var Limbs, a, M: Limbs, m0ninv: BaseType) =
  ## Convert from Montgomery form to canonical BigInt form
  # for i in 0 .. n-1:
  #   m <- t[0] * m0ninv mod 2ʷ (i.e. simple multiplication)
  #   C, _ = t[0] + m * M[0]
  #   for j in 1 ..n-1:
  #     (C, t[j-1]) <- r[j] + m*M[j] + C
  #   t[n-1] = C

  const N = a.len
  var t {.noInit.} = a # Ensure working in registers

  staticFor i, 0, N:
    let m = t[0] * SecretWord(m0ninv)
    var C, lo: SecretWord
    muladd1(C, lo, m, M[0], t[0])
    staticFor j, 1, N:
      muladd2(C, t[j-1], m, M[j], C, t[j])
    t[N-1] = C

  discard t.csub(M, not(t < M))
  r = t

# Exported API
# ------------------------------------------------------------

# Skipping reduction requires the modulus M <= R/4
# On 64-bit R is the multiple of 2⁶⁴ immediately larger than M
#
# Montgomery Arithmetic from a Software Perspective
# Bos and Montgomery, 2017
# https://eprint.iacr.org/2017/1057.pdf

# TODO upstream, using Limbs[N] breaks semcheck
func redc2xMont*[N: static int](
       r: var array[N, SecretWord],
       a: array[N*2, SecretWord],
       M: array[N, SecretWord],
       m0ninv: BaseType,
       spareBits: static int, skipFinalSub: static bool = false) {.inline.} =
  ## Montgomery reduce a double-precision bigint modulo M

  const skipFinalSub = skipFinalSub and spareBits >= 2

  when UseASM_X86_64 and r.len <= 6:
    # ADX implies BMI2
    if ({.noSideEffect.}: hasAdx()):
      redcMont_asm_adx(r, a, M, m0ninv, spareBits, skipFinalSub)
    else:
      when r.len in {3..6}:
        redcMont_asm(r, a, M, m0ninv, spareBits, skipFinalSub)
      else:
        redc2xMont_CIOS(r, a, M, m0ninv, skipFinalSub)
        # redc2xMont_Comba(r, a, M, m0ninv)
  elif UseASM_X86_64 and r.len in {3..6}:
    # TODO: Assembly faster than GCC but slower than Clang
    redcMont_asm(r, a, M, m0ninv, spareBits, skipFinalSub)
  else:
    redc2xMont_CIOS(r, a, M, m0ninv, skipFinalSub)
    # redc2xMont_Comba(r, a, M, m0ninv, skipFinalSub)

func mulMont*(
        r: var Limbs, a, b, M: Limbs,
        m0ninv: BaseType,
        spareBits: static int,
        skipFinalSub: static bool = false) {.inline.} =
  ## Compute r <- a*b (mod M) in the Montgomery domain
  ## `m0ninv` = -1/M (mod SecretWord). Our words are 2^32 or 2^64
  ##
  ## This resets r to zero before processing. Use {.noInit.}
  ## to avoid duplicating with Nim zero-init policy
  ## The result `r` buffer size MUST be at least the size of `M` buffer
  ##
  ##
  ## Assuming 64-bit words, the magic constant should be:
  ##
  ## - µ ≡ -1/M[0] (mod 2^64) for a general multiplication
  ##   This can be precomputed with `m0ninv`
  ## - 1 for conversion from Montgomery to canonical representation
  ##   The library implements a faster `redc` primitive for that use-case
  ## - R^2 (mod M) for conversion from canonical to Montgomery representation
  ##
  # i.e. c'R <- a'R b'R * R^-1 (mod M) in the natural domain
  # as in the Montgomery domain all numbers are scaled by R

  const skipFinalSub = skipFinalSub and spareBits >= 2

  when spareBits >= 1:
    when UseASM_X86_64 and a.len in {2 .. 6}: # TODO: handle spilling
      # ADX implies BMI2
      if ({.noSideEffect.}: hasAdx()):
        mulMont_CIOS_sparebit_asm_adx(r, a, b, M, m0ninv, skipFinalSub)
      else:
        mulMont_CIOS_sparebit_asm(r, a, b, M, m0ninv, skipFinalSub)
    else:
      mulMont_CIOS_sparebit(r, a, b, M, m0ninv, skipFinalSub)
  else:
    mulMont_FIPS(r, a, b, M, m0ninv, skipFinalSub)

func squareMont*[N](r: var Limbs[N], a, M: Limbs[N],
                  m0ninv: BaseType,
                  spareBits: static int,
                  skipFinalSub: static bool = false) {.inline.} =
  ## Compute r <- a^2 (mod M) in the Montgomery domain
  ## `m0ninv` = -1/M (mod SecretWord). Our words are 2^31 or 2^63

  const skipFinalSub = skipFinalSub and spareBits >= 2

  when UseASM_X86_64 and a.len in {4, 6}:
    # ADX implies BMI2
    if ({.noSideEffect.}: hasAdx()):
      # With ADX and spare bit, squareMont_CIOS_asm_adx
      # which uses unfused squaring then Montgomery reduction
      # is slightly slower than fused Montgomery multiplication
      when spareBits >= 1:
        mulMont_CIOS_sparebit_asm_adx(r, a, a, M, m0ninv, skipFinalSub)
      else:
        squareMont_CIOS_asm_adx(r, a, M, m0ninv, spareBits, skipFinalSub)
    else:
      squareMont_CIOS_asm(r, a, M, m0ninv, spareBits, skipFinalSub)
  elif UseASM_X86_64:
    var r2x {.noInit.}: Limbs[2*N]
    r2x.square(a)
    r.redc2xMont(r2x, M, m0ninv, spareBits, skipFinalSub)
  else:
    mulMont(r, a, a, M, m0ninv, spareBits, skipFinalSub)

func sumprodMont*[N: static int](
        r: var Limbs, a, b: array[N, Limbs],
        M: Limbs, m0ninv: BaseType,
        spareBits: static int,
        skipFinalSub: static bool = false) =
  ## Compute r <- ⅀aᵢ.bᵢ (mod M) (sum of products)
  when spareBits >= 2:
    when UseASM_X86_64 and r.len in {2 .. 6}:
      if ({.noSideEffect.}: hasAdx()):
        r.sumprodMont_CIOS_spare2bits_asm_adx(a, b, M, m0ninv, skipFinalSub)
      else:
        r.sumprodMont_CIOS_spare2bits_asm(a, b, M, m0ninv, skipFinalSub)
    else:
      r.sumprodMont_CIOS_spare2bits(a, b, M, m0ninv, skipFinalSub)
  else:
    r.mulMont(a[0], b[0], M, m0ninv, spareBits, skipFinalSub = false)
    var ri {.noInit.}: Limbs
    for i in 1 ..< N:
      ri.mulMont(a[i], b[i], M, m0ninv, spareBits, skipFinalSub = false)
      var overflowed = SecretBool r.add(ri)
      overflowed = overflowed or not(r < M)
      discard r.csub(M, overflowed)

func fromMont*(r: var Limbs, a, M: Limbs,
           m0ninv: BaseType, spareBits: static int) {.inline.} =
  ## Transform a bigint ``a`` from it's Montgomery N-residue representation (mod N)
  ## to the regular natural representation (mod N)
  ##
  ## with W = M.len
  ## and R = (2^WordBitWidth)^W
  ##
  ## Does "a * R^-1 (mod M)" = montMul(a, 1)
  ##
  ## This is called a Montgomery Reduction
  ## The Montgomery Magic Constant is µ = -1/N mod M
  ## is used internally and can be precomputed with m0ninv(Curve)
  # References:
  #   - https://eprint.iacr.org/2017/1057.pdf (Montgomery)
  #     page: Radix-r interleaved multiplication algorithm
  #   - https://en.wikipedia.org/wiki/Montgomery_modular_multiplication#Montgomery_arithmetic_on_multiprecision_(variable-radix)_integers
  #   - http://langevin.univ-tln.fr/cours/MLC/extra/montgomery.pdf
  #     Montgomery original paper
  when UseASM_X86_64 and a.len in {2 .. 6}:
    # ADX implies BMI2
    if ({.noSideEffect.}: hasAdx()):
      fromMont_asm_adx(r, a, M, m0ninv)
    else:
      fromMont_asm(r, a, M, m0ninv)
  else:
    fromMont_CIOS(r, a, M, m0ninv)

func getMont*(r: var Limbs, a, M, r2modM: Limbs,
                   m0ninv: BaseType, spareBits: static int) {.inline.} =
  ## Transform a bigint ``a`` from it's natural representation (mod N)
  ## to a the Montgomery n-residue representation
  ##
  ## Montgomery-Multiplication - based
  ##
  ## with W = M.len
  ## and R = (2^WordBitWidth)^W
  ##
  ## Does "a * R (mod M)"
  ##
  ## `a`: The source BigInt in the natural representation. `a` in [0, N) range
  ## `M`: The field modulus. M must be odd.
  ## `r2modM`: 2^WordBitWidth mod `M`. Can be precomputed with `r2mod` function
  ##
  ## Important: `r` is overwritten
  ## The result `r` buffer size MUST be at least the size of `M` buffer
  # Reference: https://eprint.iacr.org/2017/1057.pdf

  # For conversion to a field element (in the Montgomery domain), we do not use the "no-carry" optimization:
  #    While Montgomery Reduction can map inputs [0, 4p²) -> [0, p)
  #    that range is not valid with the no-carry optimization,
  #    hence an unreduced input that uses 256-bit while prime is 254-bit
  #    can have an incorrect representation.
  mulMont_FIPS(r, a, r2ModM, M, m0ninv, skipFinalSub = false)

# Montgomery Modular Exponentiation
# ------------------------------------------
# We use fixed-window based exponentiation
# that is constant-time: i.e. the number of multiplications
# does not depend on the number of set bits in the exponents
# those are always done and conditionally copied.
#
# The exponent MUST NOT be private data (until audited otherwise)
# - Power attack on RSA, https://www.di.ens.fr/~fouque/pub/ches06.pdf
# - Flush-and-reload on Sliding window exponentiation: https://tutcris.tut.fi/portal/files/8966761/p1639_pereida_garcia.pdf
# - Sliding right into disaster, https://eprint.iacr.org/2017/627.pdf
# - Fixed window leak: https://www.scirp.org/pdf/JCC_2019102810331929.pdf
# - Constructing sliding-windows leak, https://easychair.org/publications/open/fBNC
#
# For pairing curves, this is the case since exponentiation is only
# used for inversion via the Little Fermat theorem.
# For RSA, some exponentiations uses private exponents.
#
# Note:
# - Implementation closely follows Thomas Pornin's BearSSL
# - Apache Milagro Crypto has an alternative implementation
#   that is more straightforward however:
#   - the exponent hamming weight is used as loop bounds
#   - the baseᵏ is stored at each index of a temp table of size k
#   - the baseᵏ to use is indexed by the hamming weight
#     of the exponent, leaking this to cache attacks
#   - in contrast BearSSL touches the whole table to
#     hide the actual selection

template checkPowScratchSpaceLen(len: int) =
  ## Checks that there is a minimum of scratchspace to hold the temporaries
  debug:
    assert len >= 2, "Internal Error: the scratchspace for powmod should be equal or greater than 2"

func getWindowLen(bufLen: int): uint =
  ## Compute the maximum window size that fits in the scratchspace buffer
  checkPowScratchSpaceLen(bufLen)
  result = 5
  while (1 shl result) + 1 > bufLen:
    dec result

func powMontPrologue(
       a: var Limbs, M, one: Limbs,
       m0ninv: BaseType,
       scratchspace: var openarray[Limbs],
       spareBits: static int
     ): uint =
  ## Setup the scratchspace
  ## Returns the fixed-window size for exponentiation with window optimization.
  result = scratchspace.len.getWindowLen()
  # Precompute window content, special case for window = 1
  # (i.e scratchspace has only space for 2 temporaries)
  # The content scratchspace[2+k] is set at aᵏ
  # with scratchspace[0] untouched
  if result == 1:
    scratchspace[1] = a
  else:
    scratchspace[2] = a
    for k in 2 ..< 1 shl result:
      scratchspace[k+1].mulMont(scratchspace[k], a, M, m0ninv, spareBits)

  # Set a to one
  a = one

func powMontSquarings(
        a: var Limbs,
        exponent: openarray[byte],
        M: Limbs,
        m0ninv: BaseType,
        tmp: var Limbs,
        window: uint,
        acc, acc_len: var uint,
        e: var int,
        spareBits: static int
      ): tuple[k, bits: uint] {.inline.}=
  ## Squaring step of exponentiation by squaring
  ## Get the next k bits in range [1, window)
  ## Square k times
  ## Returns the number of squarings done and the corresponding bits
  ##
  ## Updates iteration variables and accumulators
  # Due to the high number of parameters,
  # forcing this inline actually reduces the code size
  #
  # ⚠️: Extreme care should be used to not leak
  #    the exponent bits nor its real bitlength
  #    i.e. if the exponent is zero but encoded in a
  #    256-bit integer, only "256" should leak
  #    as for some application like RSA
  #    the exponent might be the user secret key.

  # Get the next bits
  # acc/acc_len must be uint to avoid Nim runtime checks leaking bits
  # acc/acc_len must be uint to avoid Nim runtime checks leaking bits
  # e is public
  var k = window
  if acc_len < window:
    if e < exponent.len:
      acc = (acc shl 8) or exponent[e].uint
      inc e
      acc_len += 8
    else: # Drained all exponent bits
      k = acc_len

  let bits = (acc shr (acc_len - k)) and ((1'u32 shl k) - 1)
  acc_len -= k

  # We have k bits and can do k squaring
  for i in 0 ..< k:
    a.squareMont(a, M, m0ninv, spareBits)

  return (k, bits)

func powMont*(
       a: var Limbs,
       exponent: openarray[byte],
       M, one: Limbs,
       m0ninv: BaseType,
       scratchspace: var openarray[Limbs],
       spareBits: static int) =
  ## Modular exponentiation a <- a^exponent (mod M)
  ## in the Montgomery domain
  ##
  ## This uses fixed-window optimization if possible
  ##
  ## - On input ``a`` is the base, on ``output`` a = a^exponent (mod M)
  ##   ``a`` is in the Montgomery domain
  ## - ``exponent`` is the exponent in big-endian canonical format (octet-string)
  ##   Use ``marshal`` for conversion
  ## - ``M`` is the modulus
  ## - ``one`` is 1 (mod M) in montgomery representation
  ## - ``m0ninv`` is the montgomery magic constant "-1/M[0] mod 2^WordBitWidth"
  ## - ``scratchspace`` with k the window bitsize of size up to 5
  ##   This is a buffer that can hold between 2ᵏ + 1 big-ints
  ##   A window of of 1-bit (no window optimization) requires only 2 big-ints
  ##
  ## Note that the best window size require benchmarking and is a tradeoff between
  ## - performance
  ## - stack usage
  ## - precomputation
  ##
  ## For example BLS12-381 window size of 5 is 30% faster than no window,
  ## but windows of size 2, 3, 4 bring no performance benefit, only increased stack space.
  ## A window of size 5 requires (2^5 + 1)*(381 + 7)/8 = 33 * 48 bytes = 1584 bytes
  ## of scratchspace (on the stack).

  let window = powMontPrologue(a, M, one, m0ninv, scratchspace, spareBits)

  # We process bits with from most to least significant.
  # At each loop iteration with have acc_len bits in acc.
  # To maintain constant-time the number of iterations
  # or the number of operations or memory accesses should be the same
  # regardless of acc & acc_len
  var
    acc, acc_len: uint
    e = 0
  while acc_len > 0 or e < exponent.len:
    let (k, bits) = powMontSquarings(
      a, exponent, M, m0ninv,
      scratchspace[0], window,
      acc, acc_len, e,
      spareBits)

    # Window lookup: we set scratchspace[1] to the lookup value.
    # If the window length is 1, then it's already set.
    if window > 1:
      # otherwise we need a constant-time lookup
      # in particular we need the same memory accesses, we can't
      # just index the openarray with the bits to avoid cache attacks.
      for i in 1 ..< 1 shl k:
        let ctl = SecretWord(i) == SecretWord(bits)
        scratchspace[1].ccopy(scratchspace[1+i], ctl)

    # Multiply with the looked-up value
    # we keep the product only if the exponent bits are not all zeroes
    scratchspace[0].mulMont(a, scratchspace[1], M, m0ninv, spareBits)
    a.ccopy(scratchspace[0], SecretWord(bits).isNonZero())

func powMont_vartime*(
       a: var Limbs,
       exponent: openarray[byte],
       M, one: Limbs,
       m0ninv: BaseType,
       scratchspace: var openarray[Limbs],
       spareBits: static int
      ) =
  ## Modular exponentiation a <- a^exponent (mod M)
  ## in the Montgomery domain
  ##
  ## Warning ⚠️ :
  ## This is an optimization for public exponent
  ## Otherwise bits of the exponent can be retrieved with:
  ## - memory access analysis
  ## - power analysis
  ## - timing analysis

  # TODO: scratchspace[1] is unused when window > 1

  let window = powMontPrologue(a, M, one, m0ninv, scratchspace, spareBits)

  var
    acc, acc_len: uint
    e = 0
  while acc_len > 0 or e < exponent.len:
    let (_, bits) = powMontSquarings(
      a, exponent, M, m0ninv,
      scratchspace[0], window,
      acc, acc_len, e,
      spareBits)

    ## Warning ⚠️: Exposes the exponent bits
    if bits != 0:
      if window > 1:
        scratchspace[0].mulMont(a, scratchspace[1+bits], M, m0ninv, spareBits)
      else:
        # scratchspace[1] holds the original `a`
        scratchspace[0].mulMont(a, scratchspace[1], M, m0ninv, spareBits)
      a = scratchspace[0]

{.pop.} # raises no exceptions
