# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/macros,
  # Internal
  ../config/common,
  ../primitives,
  ./limbs

when UseASM_X86_32:
  import ./assembly/limbs_asm_montred_x86
when UseASM_X86_64:
  import
    ./assembly/limbs_asm_montmul_x86,
    ./assembly/limbs_asm_montmul_x86_adx_bmi2,
    ./assembly/limbs_asm_montred_x86_adx_bmi2

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
{.push raises: [].}

# Montgomery Multiplication
# ------------------------------------------------------------

func montyMul_CIOS_nocarry(r: var Limbs, a, b, M: Limbs, m0ninv: BaseType) =
  ## Montgomery Multiplication using Coarse Grained Operand Scanning (CIOS)
  ## and no-carry optimization.
  ## This requires the most significant word of the Modulus
  ##   M[^1] < high(SecretWord) shr 1 (i.e. less than 0b01111...1111)
  ## https://hackmd.io/@zkteam/modular_multiplication

  # We want all the computation to be kept in registers
  # hence we use a temporary `t`, hoping that the compiler does it.
  var t: typeof(M) # zero-init
  const N = t.len
  staticFor i, 0, N:
    # (A, t[0]) <- a[0] * b[i] + t[0]
    #  m        <- (t[0] * m0ninv) mod 2^w
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

  discard t.csub(M, not(t < M))
  r = t

func montyMul_CIOS(r: var Limbs, a, b, M: Limbs, m0ninv: BaseType) {.used.} =
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
    #  m        <- (t[0] * m0ninv) mod 2^w
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
  discard t.csub(M, tN.isNonZero() or not(t < M)) # TODO: (t >= M) is unnecessary for prime in the form (2^64)^w
  r = t

func montyMul_FIPS(r: var Limbs, a, b, M: Limbs, m0ninv: BaseType) =
  ## Montgomery Multiplication using Finely Integrated Product Scanning (FIPS)
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

  discard z.csub(M, v.isNonZero() or not(z < M))
  r = z

# Montgomery Squaring
# ------------------------------------------------------------

func montySquare_CIOS_nocarry(r: var Limbs, a, M: Limbs, m0ninv: BaseType) {.used.}=
  ## Montgomery Multiplication using Coarse Grained Operand Scanning (CIOS)
  ## and no-carry optimization.
  ## This requires the most significant word of the Modulus
  ##   M[^1] < high(SecretWord) shr 2 (i.e. less than 0b00111...1111)
  ## https://hackmd.io/@zkteam/modular_multiplication

  # TODO: Deactivated
  # Off-by one on 32-bit on the least significant bit
  # for Fp[BLS12-381] with inputs
  # - -0x091F02EFA1C9B99C004329E94CD3C6B308164CBE02037333D78B6C10415286F7C51B5CD7F917F77B25667AB083314B1B
  # - -0x0B7C8AFE5D43E9A973AF8649AD8C733B97D06A78CFACD214CBE9946663C3F682362E0605BC8318714305B249B505AFD9

  # We want all the computation to be kept in registers
  # hence we use a temporary `t`, hoping that the compiler does it.
  var t: typeof(M) # zero-init
  const N = t.len
  staticFor i, 0, N:
    # Squaring
    var
      A1: Carry
      A0: SecretWord
    # (A0, t[i]) <- a[i] * a[i] + t[i]
    muladd1(A0, t[i], a[i], a[i], t[i])
    staticFor j, i+1, N:
      # (A1, A0, t[j]) <- 2*a[j]*a[i] + t[j] + (A1, A0)
      # 2*a[j]*a[i] can spill 1-bit on a 3rd word
      mulDoubleAdd2(A1, A0, t[j], a[j], a[i], t[j], A1, A0)

    # Reduction
    #  m        <- (t[0] * m0ninv) mod 2^w
    # (C, _)    <- m * M[0] + t[0]
    let m = t[0] * SecretWord(m0ninv)
    var C, lo: SecretWord
    muladd1(C, lo, m, M[0], t[0])
    staticFor j, 1, N:
      # (C, t[j-1]) <- m*M[j] + t[j] + C
      muladd2(C, t[j-1], m, M[j], t[j], C)

    t[N-1] = C + A0

  discard t.csub(M, not(t < M))
  r = t

func montySquare_CIOS(r: var Limbs, a, M: Limbs, m0ninv: BaseType) {.used.}=
  ## Montgomery Multiplication using Coarse Grained Operand Scanning (CIOS)
  ##
  ## Architectural Support for Long Integer Modulo Arithmetic on Risc-Based Smart Cards
  ## Johann Großschädl, 2003
  ## https://citeseerx.ist.psu.edu/viewdoc/download;jsessionid=95950BAC26A728114431C0C7B425E022?doi=10.1.1.115.3276&rep=rep1&type=pdf
  ##
  ## Analyzing and Comparing Montgomery Multiplication Algorithms
  ## Koc, Acar, Kaliski, 1996
  ## https://www.semanticscholar.org/paper/Analyzing-and-comparing-Montgomery-multiplication-Ko%C3%A7-Acar/5e3941ff482ec3ee41dc53c3298f0be085c69483

  # TODO: Deactivated
  # Off-by one on 32-bit on the least significant bit
  # for Fp[2^127 - 1] with inputs
  # - -0x75bfffefbfffffff7fd9dfd800000000
  # - -0x7ff7ffffffffffff1dfb7fafc0000000
  # Squaring the number and its opposite
  # should give the same result, but those are off-by-one

  # We want all the computation to be kept in registers
  # hence we use a temporary `t`, hoping that the compiler does it.
  var t: typeof(M) # zero-init
  const N = t.len
  # Extra words to handle up to 2 carries t[N] and t[N+1]
  var tNp1: SecretWord
  var tN: SecretWord

  staticFor i, 0, N:
    # Squaring
    var A1 = Carry(0)
    var A0: SecretWord
    # (A0, t[i]) <- a[i] * a[i] + t[i]
    muladd1(A0, t[i], a[i], a[i], t[i])
    staticFor j, i+1, N:
      # (A1, A0, t[j]) <- 2*a[j]*a[i] + t[j] + (A1, A0)
      # 2*a[j]*a[i] can spill 1-bit on a 3rd word
      mulDoubleAdd2(A1, A0, t[j], a[j], a[i], t[j], A1, A0)

    var carryS: Carry
    addC(carryS, tN, tN, A0, Carry(0))
    addC(carryS, tNp1, SecretWord(A1), Zero, carryS)

    # Reduction
    #  m        <- (t[0] * m0ninv) mod 2^w
    # (C, _)    <- m * M[0] + t[0]
    var C, lo: SecretWord
    let m = t[0] * SecretWord(m0ninv)
    muladd1(C, lo, m, M[0], t[0])
    staticFor j, 1, N:
      # (C, t[j-1]) <- m*M[j] + t[j] + C
      muladd2(C, t[j-1], m, M[j], t[j], C)

    #  (C,t[N-1]) <- t[N] + C
    #  (_, t[N])  <- t[N+1] + C
    var carryR: Carry
    addC(carryR, t[N-1], tN, C, Carry(0))
    addC(carryR, tN, tNp1, Zero, carryR)

  discard t.csub(M, tN.isNonZero() or not(t < M)) # TODO: (t >= M) is unnecessary for prime in the form (2^64)^w
  r = t

# Montgomery Reduction
# ------------------------------------------------------------
func montyRedc2x_CIOS[N: static int](
       r: var array[N, SecretWord],
       a: array[N*2, SecretWord],
       M: array[N, SecretWord],
       m0ninv: BaseType) =
  ## Montgomery reduce a double-width bigint modulo M
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
  # - a[0 ..< 2N] (double-width input to reduce)
  # - M[0 ..< N] The field modulus (must be odd for Montgomery reduction)
  # - m0ninv: Montgomery Reduction magic number = -1/M[0]
  # Output:
  # - r[0 ..< N], in the Montgomery domain
  # Parameters:
  # - w, the word width usually 64 on 64-bit platforms or 32 on 32-bit
  #
  # for i in 0 .. n-1:
  #   C <- 0
  #   m <- a[i] * m0ninv mod 2^w (i.e. simple multiplication)
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

  var a = a          # Copy "t" for mutation and ensure on stack
  var res: typeof(r) # Accumulator
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
  discard res.csub(M, SecretWord(carry).isNonZero() or not(res < M))
  r = res

func montyRedc2x_Comba[N: static int](
       r: var array[N, SecretWord],
       a: array[N*2, SecretWord],
       M: array[N, SecretWord],
       m0ninv: BaseType) =
  ## Montgomery reduce a double-width bigint modulo M
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
  discard z.csub(M, SecretBool(carry) or not(z < M))
  r = z

# Exported API
# ------------------------------------------------------------

func montyMul*(
        r: var Limbs, a, b, M: Limbs,
        m0ninv: static BaseType, canUseNoCarryMontyMul: static bool) {.inline.} =
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

  # Many curve moduli are "Montgomery-friendly" which means that m0ninv is 1
  # This saves N basic type multiplication and potentially many register mov
  # as well as unless using "mulx" instruction, x86 "mul" requires very specific registers.
  #
  # The implementation is visible from here, the compiler can make decision whether to:
  # - specialize/duplicate code for m0ninv == 1 (especially if only 1 curve is needed)
  # - keep it generic and optimize code size
  when canUseNoCarryMontyMul:
    when UseASM_X86_64 and a.len in {2 .. 6}: # TODO: handle spilling
      if ({.noSideEffect.}: hasBmi2()) and ({.noSideEffect.}: hasAdx()):
        montMul_CIOS_nocarry_asm_adx_bmi2(r, a, b, M, m0ninv)
      else:
        montMul_CIOS_nocarry_asm(r, a, b, M, m0ninv)
    else:
      montyMul_CIOS_nocarry(r, a, b, M, m0ninv)
  else:
    montyMul_FIPS(r, a, b, M, m0ninv)

func montySquare*(r: var Limbs, a, M: Limbs,
                  m0ninv: static BaseType, canUseNoCarryMontySquare: static bool) {.inline.} =
  ## Compute r <- a^2 (mod M) in the Montgomery domain
  ## `m0ninv` = -1/M (mod SecretWord). Our words are 2^31 or 2^63

  # TODO: needs optimization similar to multiplication
  montyMul(r, a, a, M, m0ninv, canUseNoCarryMontySquare)

  # when canUseNoCarryMontySquare:
  #   # TODO: Deactivated
  #   # Off-by one on 32-bit on the least significant bit
  #   # for Fp[BLS12-381] with inputs
  #   # - -0x091F02EFA1C9B99C004329E94CD3C6B308164CBE02037333D78B6C10415286F7C51B5CD7F917F77B25667AB083314B1B
  #   # - -0x0B7C8AFE5D43E9A973AF8649AD8C733B97D06A78CFACD214CBE9946663C3F682362E0605BC8318714305B249B505AFD9
  #
  #   # montySquare_CIOS_nocarry(r, a, M, m0ninv)
  #   montyMul_CIOS_nocarry(r, a, a, M, m0ninv)
  # else:
  #   # TODO: Deactivated
  #   # Off-by one on 32-bit for Fp[2^127 - 1] with inputs
  #   # - -0x75bfffefbfffffff7fd9dfd800000000
  #   # - -0x7ff7ffffffffffff1dfb7fafc0000000
  #   # Squaring the number and its opposite
  #   # should give the same result, but those are off-by-one
  #
  #   # montySquare_CIOS(r, a, M, m0ninv) # TODO <--- Fix this
  #   montyMul_FIPS(r, a, a, M, m0ninv)

# TODO upstream, using Limbs[N] breaks semcheck
func montyRedc2x*[N: static int](
       r: var array[N, SecretWord],
       a: array[N*2, SecretWord],
       M: array[N, SecretWord],
       m0ninv: BaseType, canUseNoCarryMontyMul: static bool) {.inline.} =
  ## Montgomery reduce a double-width bigint modulo M
  when UseASM_X86_64 and r.len <= 6:
    if ({.noSideEffect.}: hasBmi2()) and ({.noSideEffect.}: hasAdx()):
      montRed_asm_adx_bmi2(r, a, M, m0ninv, canUseNoCarryMontyMul)
    else:
      montRed_asm(r, a, M, m0ninv, canUseNoCarryMontyMul)
  elif UseASM_X86_32 and r.len <= 6:
    # TODO: Assembly faster than GCC but slower than Clang
    montRed_asm(r, a, M, m0ninv, canUseNoCarryMontyMul)
  else:
    montyRedc2x_CIOS(r, a, M, m0ninv)
    # montyRedc2x_Comba(r, a, M, m0ninv)

func redc*(r: var Limbs, a, one, M: Limbs,
           m0ninv: static BaseType, canUseNoCarryMontyMul: static bool) =
  ## Transform a bigint ``a`` from it's Montgomery N-residue representation (mod N)
  ## to the regular natural representation (mod N)
  ##
  ## with W = M.len
  ## and R = (2^WordBitWidth)^W
  ##
  ## Does "a * R^-1 (mod M)"
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
  #
  montyMul(r, a, one, M, m0ninv, canUseNoCarryMontyMul)

func montyResidue*(r: var Limbs, a, M, r2modM: Limbs,
                   m0ninv: static BaseType, canUseNoCarryMontyMul: static bool) =
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
  montyMul(r, a, r2ModM, M, m0ninv, canUseNoCarryMontyMul)

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
#   - the base^k is stored at each index of a temp table of size k
#   - the base^k to use is indexed by the hamming weight
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

func montyPowPrologue(
       a: var Limbs, M, one: Limbs,
       m0ninv: static BaseType,
       scratchspace: var openarray[Limbs],
       canUseNoCarryMontyMul: static bool
     ): uint =
  ## Setup the scratchspace
  ## Returns the fixed-window size for exponentiation with window optimization.
  result = scratchspace.len.getWindowLen()
  # Precompute window content, special case for window = 1
  # (i.e scratchspace has only space for 2 temporaries)
  # The content scratchspace[2+k] is set at a^k
  # with scratchspace[0] untouched
  if result == 1:
    scratchspace[1] = a
  else:
    scratchspace[2] = a
    for k in 2 ..< 1 shl result:
      scratchspace[k+1].montyMul(scratchspace[k], a, M, m0ninv, canUseNoCarryMontyMul)

  # Set a to one
  a = one

func montyPowSquarings(
        a: var Limbs,
        exponent: openarray[byte],
        M: Limbs,
        m0ninv: static BaseType,
        tmp: var Limbs,
        window: uint,
        acc, acc_len: var uint,
        e: var int,
        canUseNoCarryMontySquare: static bool
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
    tmp.montySquare(a, M, m0ninv, canUseNoCarryMontySquare)
    a = tmp

  return (k, bits)

func montyPow*(
       a: var Limbs,
       exponent: openarray[byte],
       M, one: Limbs,
       m0ninv: static BaseType,
       scratchspace: var openarray[Limbs],
       canUseNoCarryMontyMul: static bool,
       canUseNoCarryMontySquare: static bool
      ) =
  ## Modular exponentiation r = a^exponent mod M
  ## in the Montgomery domain
  ##
  ## This uses fixed-window optimization if possible
  ##
  ## - On input ``a`` is the base, on ``output`` a = a^exponent (mod M)
  ##   ``a`` is in the Montgomery domain
  ## - ``exponent`` is the exponent in big-endian canonical format (octet-string)
  ##   Use ``exportRawUint`` for conversion
  ## - ``M`` is the modulus
  ## - ``one`` is 1 (mod M) in montgomery representation
  ## - ``m0ninv`` is the montgomery magic constant "-1/M[0] mod 2^WordBitWidth"
  ## - ``scratchspace`` with k the window bitsize of size up to 5
  ##   This is a buffer that can hold between 2^k + 1 big-ints
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

  let window = montyPowPrologue(a, M, one, m0ninv, scratchspace, canUseNoCarryMontyMul)

  # We process bits with from most to least significant.
  # At each loop iteration with have acc_len bits in acc.
  # To maintain constant-time the number of iterations
  # or the number of operations or memory accesses should be the same
  # regardless of acc & acc_len
  var
    acc, acc_len: uint
    e = 0
  while acc_len > 0 or e < exponent.len:
    let (k, bits) = montyPowSquarings(
      a, exponent, M, m0ninv,
      scratchspace[0], window,
      acc, acc_len, e,
      canUseNoCarryMontySquare
    )

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
    scratchspace[0].montyMul(a, scratchspace[1], M, m0ninv, canUseNoCarryMontyMul)
    a.ccopy(scratchspace[0], SecretWord(bits).isNonZero())

func montyPowUnsafeExponent*(
       a: var Limbs,
       exponent: openarray[byte],
       M, one: Limbs,
       m0ninv: static BaseType,
       scratchspace: var openarray[Limbs],
       canUseNoCarryMontyMul: static bool,
       canUseNoCarryMontySquare: static bool
      ) =
  ## Modular exponentiation r = a^exponent mod M
  ## in the Montgomery domain
  ##
  ## Warning ⚠️ :
  ## This is an optimization for public exponent
  ## Otherwise bits of the exponent can be retrieved with:
  ## - memory access analysis
  ## - power analysis
  ## - timing analysis

  # TODO: scratchspace[1] is unused when window > 1

  let window = montyPowPrologue(a, M, one, m0ninv, scratchspace, canUseNoCarryMontyMul)

  var
    acc, acc_len: uint
    e = 0
  while acc_len > 0 or e < exponent.len:
    let (_, bits) = montyPowSquarings(
      a, exponent, M, m0ninv,
      scratchspace[0], window,
      acc, acc_len, e,
      canUseNoCarryMontySquare
    )

    ## Warning ⚠️: Exposes the exponent bits
    if bits != 0:
      if window > 1:
        scratchspace[0].montyMul(a, scratchspace[1+bits], M, m0ninv, canUseNoCarryMontyMul)
      else:
        # scratchspace[1] holds the original `a`
        scratchspace[0].montyMul(a, scratchspace[1], M, m0ninv, canUseNoCarryMontyMul)
      a = scratchspace[0]

{.pop.} # raises no exceptions
