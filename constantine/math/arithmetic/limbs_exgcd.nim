# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/abstractions,
  ./limbs, ./limbs_unsaturated

# No exceptions allowed
{.push raises: [].}
{.push checks: off.}

# ############################################################
#
#             Primitives based on Bézout's identity
#
# ############################################################
#
# Bézout's identity is the linear Diophantine equation
#   au + bv = c
#
# The solution c is gcd(a, b)
# if a and b are coprime, gcd(a, b) = 1
#   au + bv = 1
#
# Hence modulo b we have
#   au + bv ≡ 1 (mod b)
#   au      ≡ 1 (mod b)
# So u is the modular multiplicative inverse of a (mod b)
#
# As we can use the Extended Euclidean Algorithm to find
# the GCD and the Bézout coefficient, we can use it to find the
# modular multiplicaative inverse.

# ############################################################
#
#                  Modular inversion (mod 2ᵏ)
#
# ############################################################

func invModBitwidth*(a: BaseType): BaseType =
  # Modular inverse algorithm:
  # Explanation p11 "Dumas iterations" based on Newton-Raphson:
  # - Cetin Kaya Koc (2017), https://eprint.iacr.org/2017/411
  # - Jean-Guillaume Dumas (2012), https://arxiv.org/pdf/1209.6626v2.pdf
  # - Colin Plumb (1994), http://groups.google.com/groups?selm=1994Apr6.093116.27805%40mnemosyne.cs.du.edu
  # Other sources:
  # - https://crypto.stackexchange.com/questions/47493/how-to-determine-the-multiplicative-inverse-modulo-64-or-other-power-of-two
  # - https://mumble.net/~campbell/2015/01/21/inverse-mod-power-of-two
  # - http://marc-b-reynolds.github.io/math/2017/09/18/ModInverse.html

  # We are in a special case
  # where m = 2^WordBitWidth.
  # For a and m to be coprimes, a must be odd.
  #
  # We have the following relation
  # ax ≡ 1 (mod 2ᵏ) <=> ax(2 - ax) ≡ 1 (mod 2²ᵏ)
  # which grows in O(log(log(a)))
  debug: doAssert (a and 1) == 1, "a must be odd"

  const k = log2_vartime(a.sizeof().uint32 * 8)
  result = a                 # Start from an inverse of M0 modulo 2, M0 is odd and it's own inverse
  for _ in 0 ..< k:          # at each iteration we get the inverse mod(2^2k)
    result *= 2 - a * result # x' = x(2 - ax)

func invMod2k(M0: BaseType, k: static BaseType): BaseType =
  ## Compute 1/M mod 2ᵏ
  ## from M[0]
  # Algorithm: Cetin Kaya Koc (2017) p11, https://eprint.iacr.org/2017/411
  # Once you have a modular inverse (mod 2ˢ) you can reduce
  # (mod 2ᵏ) to have the modular inverse (mod 2ᵏ)
  static: doAssert k <= WordBitWidth
  const maskMod = (1 shl k)-1
  M0.invModBitwidth() and maskMod

# ###############################################################
#
#                   Modular inversion
#
# ###############################################################

# Algorithm by Bernstein-Yang
# ------------------------------------------------------------
#
# - Original Bernstein-Yang paper, https://eprint.iacr.org/2019/266
# - Executable spec and description by Dettman-Wuille, https://github.com/bitcoin-core/secp256k1/blob/85b00a1/doc/safegcd_implementation.md
# - Formal bound verification by Wuille, https://github.com/sipa/safegcd-bounds
# - Formal verification by Hvass-Aranha-Spitters, https://eprint.iacr.org/2021/549
#
# We implement the half-delta divstep variant

type TransitionMatrix = object
  ## Bernstein-Yang Jumpdivstep transition matrix
  ##     [u v]
  ## t = [q r]
  ## It it is scaled by 2ᵏ
  u, v, q, r: SignedSecretWord

debug:
  # Debugging helpers

  func checkDeterminant(t: TransitionMatrix, u, v, q, r: SignedSecretWord, k, numIters: int): bool =
    # The determinant of t must be a power of two. This guarantees that multiplication with t
    # does not change the gcd of f and g, apart from adding a power-of-2 factor to it (which
    # will be divided out again).
    # Each divstep's individual matrix has determinant 2⁻¹,
    # the aggregate of numIters of them will have determinant 2ⁿᵘᵐᴵᵗᵉʳˢ. Multiplying with the initial
    # 2ᵏ*identity (which has determinant 2²ᵏ) means the result has determinant 2²ᵏ⁻ⁿᵘᵐᴵᵗᵉʳˢ.
    let
      u = SecretWord u
      v = SecretWord v
      q = SecretWord q
      r = SecretWord r

    var a, b: array[2, SecretWord]
    smul(a[1], a[0], u, r)
    smul(b[1], b[0], v, q)

    var borrow: Borrow
    subB(borrow, a[0], a[0], b[0], Borrow(0))
    subB(borrow, a[1], a[1], b[1], borrow)

    let d = 2*k - numIters
    b[0] = Zero; b[1] = Zero
    b[d div WordBitWidth] = One shl (d mod WordBitWidth)

    return bool(a == b)

func canonicalize(
       a: var LimbsUnsaturated,
       signMask: SignedSecretWord,
       M: LimbsUnsaturated
     ) =
  ## Compute a = sign*a (mod M)
  ##
  ## with a in range (-2*M, M)
  ## result in range [0, M)

  const
    UnsatBitWidth = WordBitWidth - a.Excess
    Max = SignedSecretWord(MaxWord shr a.Excess)

  # Operate in registers
  var z = a

  # Add M if `z` is negative
  # -> range (-M, M)
  z.cadd(M, z.isNegMask())
  # Negate if sign is negative
  # -> range (-M, M)
  z.cneg(signMask)
  # Normalize words to range (-2^UnsatBitwidth, 2^UnsatBitwidth)
  for i in 0 ..< z.words.len-1:
    z[i+1] = z[i+1] + z[i].ashr(UnsatBitWidth)
    z[i] = z[i] and Max

  # Add M if `z` is negative
  # -> range (0, M)
  z.cadd(M, z.isNegMask())
  # Normalize words to range (-2^UnsatBitwidth, 2^UnsatBitwidth)
  for i in 0 ..< z.words.len-1:
    z[i+1] = z[i+1] + z[i].ashr(UnsatBitWidth)
    z[i] = z[i] and Max

  a = z

proc partitionDivsteps(bits, wordBitWidth: int): tuple[totalIters, numChunks, chunkSize, cutoff: int] =
  # Given the field modulus number of bits
  # and the effective word size
  # Returns:
  # - the total number of iterations that guarantees GCD convergence
  # - the number of chunks of divsteps to compute
  # - the base number of divsteps per chunk
  # - a cutoff chunk,
  #     before this chunk ID, the number of divsteps is "base number + 1"
  #     afterward it's "base number"
  let totalIters =
    if bits == 256:
      # https://github.com/sipa/safegcd-bounds/tree/master/coq
      # For 256-bit inputs, 590 divsteps are sufficient with hddivstep variant (half-delta divstep)
      # for gcd(f, g) with 0 <= g <= f <= Modulus (inversion g == 1)
      # The generic formula reports 591
      590
    else:
      # https://github.com/sipa/safegcd-bounds/blob/master/genproofhd.md
      # For any input, for gcd(f, g) with 0 <= g <= f <= Modulus with hddivstep variant (half-delta divstep)
      # (inversion g == 1)
      (45907*bits + 26313) div 19929
  let numChunks = totalIters.ceilDiv_vartime(wordBitWidth)
  let chunkSize = totalIters div numChunks
  let cutoff = totalIters mod numChunks
  return (totalIters, numChunks, chunkSize, cutoff)

func batchedDivsteps(
       t: var TransitionMatrix,
       hdelta: SignedSecretWord,
       f0, g0: SignedSecretWord,
       numIters: int,
       k: static int
     ): SignedSecretWord =
  ## Bernstein-Yang half-delta (hdelta) batch of divsteps
  ##
  ## Output:
  ## - return hdelta for the next batch of divsteps
  ## - mutate t, the transition matrix to apply `numIters` divsteps at once
  ##   t is scaled by 2ᵏ
  ##
  ## Input:
  ## - f0, bottom limb of f
  ## - g0, bottom limb of g
  ## - numIters, number of iterations requested in this batch of divsteps
  ## - k, the maximum batch size, transition matrix is scaled by 2ᵏ
  var
    u = SignedSecretWord(1 shl k)
    v = SignedSecretWord(0)
    q = SignedSecretWord(0)
    r = SignedSecretWord(1 shl k)
    f = f0
    g = g0

    hdelta = hdelta

  for i in k-numIters ..< k:
    debug:
      func reportLoop() =
        debugEcho "  iterations: [", k-numIters, ", ", k, ")", " (", numIters, " iterations in total)"
        debugEcho "  i: ", i, ", hdelta: ", int(hdelta)
        # debugEcho "    f: 0b", BiggestInt(f).toBin(64), ", g: 0b", BiggestInt(g).toBin(64), " | f: ", int(f), ", g: ", int(g)
        # debugEcho "    u: 0b", BiggestInt(u).toBin(64), ", v: 0b", BiggestInt(v).toBin(64), " | u: ", int(u), ", v: ", int(v)
        # debugEcho "    q: 0b", BiggestInt(q).toBin(64), ", r: 0b", BiggestInt(r).toBin(64), " | q: ", int(q), ", r: ", int(r)

      doAssert (BaseType(f) and 1) == 1, (reportLoop(); "f must be odd)")
      doAssert bool(not(uint(u or v or q or r) and (if i == 0: high(uint) else: high(uint) shr (i - 1)))), (reportLoop(); "Min trailing zeros count decreases at each iteration")
      doAssert bool(u.ashr(k-i)*f0 + v.ashr(k-i)*g0 == f.lshl(i)), (reportLoop(); "Applying the transition matrix to (f₀, g₀) returns current (f, g)")
      doAssert bool(q.ashr(k-i)*f0 + r.ashr(k-i)*g0 == g.lshl(i)), (reportLoop(); "Applying the transition matrix to (f₀, g₀) returns current (f, g)")

    # Conditional masks for (hdelta < 0) and g odd
    let c1 = hdelta.isNegMask()
    let c2 = g.isOddMask()
    # x, y, z, conditional complement of f, u, v
    let x = f xor c1
    let y = u xor c1
    let z = v xor c1
    # conditional substraction from g, q, r
    g.csub(x, c2)
    q.csub(y, c2)
    r.csub(z, c2)
    # c3 = (hdelta >= 0) and g odd
    let c3 = c2 and not c1
    # hdelta = -hdelta or hdelta+1
    hdelta = (hdelta xor c3) + SignedSecretWord(1)
    # Conditional rollback substraction
    f.cadd(g, c3)
    u.cadd(q, c3)
    v.cadd(r, c3)
    # Shifts
    g = g.lshr(1)
    q = q.ashr(1)
    r = r.ashr(1)

  t.u = u
  t.v = v
  t.q = q
  t.r = r
  debug:
    doAssert bool(u*f0 + v*g0 == f.lshl(k)), "Applying the final matrix to (f₀, g₀) gives the final (f, g)"
    doAssert bool(q*f0 + r*g0 == g.lshl(k)), "Applying the final matrix to (f₀, g₀) gives the final (f, g)"
    doAssert checkDeterminant(t, u, v, q, r, k, numIters)

  return hdelta

func matVecMul_shr_k_mod_M[N, E: static int](
       t: TransitionMatrix,
       d, e: var LimbsUnsaturated[N, E],
       k: static int,
       M: LimbsUnsaturated[N, E],
       invMod2k: SecretWord
  ) =
  ## Compute
  ##
  ## [u v]    [d]
  ## [q r]/2ᵏ.[e] mod M
  ##
  ## d, e will be in range (-2*modulus,modulus)
  ## and output limbs in (-2ᵏ, 2ᵏ)

  static: doAssert k == WordBitWidth - E
  const Max = SignedSecretWord(MaxWord shr E)

  let
    u = t.u
    v = t.v
    q = t.q
    r = t.r

  let sign_d = d.isNegMask()
  let sign_e = e.isNegMask()

  # Double-signed-word carries
  var cd, ce: DSWord

  # First iteration of [u v] [d]
  #                    [q r].[e]
  cd.ssumprodAccNoCarry(u, d[0], v, e[0])
  ce.ssumprodAccNoCarry(q, d[0], r, e[0])

  # Compute me and md, multiples of M
  # such as the bottom k bits if d and e are 0
  # This allows fusing division by 2ᵏ
  # i.e. (mx * M) mod 2ᵏ = x mod 2ᵏ
  var md, me = SignedSecretWord(0)
  md.cadd(u, sign_d)
  md.cadd(v, sign_e)
  me.cadd(q, sign_d)
  me.cadd(r, sign_e)

  md = md - (SignedSecretWord(invMod2k * SecretWord(cd.lo) + SecretWord(md)) and Max)
  me = me - (SignedSecretWord(invMod2k * SecretWord(ce.lo) + SecretWord(me)) and Max)

  # First iteration of [u v] [d]   [md]
  #                    [q r].[e] + [me].M[0]
  # k bottom bits are 0
  cd.smulAccNoCarry(md, M[0])
  ce.smulAccNoCarry(me, M[0])
  cd.ashr(k)
  ce.ashr(k)

  for i in 1 ..< N:
    cd.ssumprodAccNoCarry(u, d[i], v, e[i])
    ce.ssumprodAccNoCarry(q, d[i], r, e[i])
    cd.smulAccNoCarry(md, M[i])
    ce.smulAccNoCarry(me, M[i])
    d[i-1] = cd.lo and Max
    e[i-1] = ce.lo and Max
    cd.ashr(k)
    ce.ashr(k)

  d[N-1] = cd.lo
  e[N-1] = ce.lo

template matVecMul_shr_k_impl(
       t: TransitionMatrix,
       f, g: var LimbsUnsaturated,
       Excess: static int,
       numLimbsLeft: int or static int,
       k: static int
  ) =
  ## Compute
  ##
  ## [u v] [f]
  ## [q r].[g] / 2ᵏ
  ##
  ## Template so that it can be specialized
  ## when iteration number is fixed and compiler can unroll, in constant-time case
  ## or variable and the full buffer might not be used (vartime)

  static: doAssert k == WordBitWidth - Excess
  const Max = SignedSecretWord(MaxWord shr Excess)

  let
    u = t.u
    v = t.v
    q = t.q
    r = t.r

  # Double-signed-word carries
  var cf, cg: DSWord

  # First iteration of [u v] [f]
  #                    [q r].[g]
  ssumprodAccNoCarry(cf, u, f[0], v, g[0])
  ssumprodAccNoCarry(cg, q, f[0], r, g[0])
  # bottom k bits are zero by construction
  debug:
    doAssert BaseType(cf.lo and Max) == 0, "bottom k bits should be 0, cf.lo: " & $BaseType(cf.lo)
    doAssert BaseType(cg.lo and Max) == 0, "bottom k bits should be 0, cg.lo: " & $BaseType(cg.lo)

  cf.ashr(k)
  cg.ashr(k)

  for i in 1 ..< numLimbsLeft:
    ssumprodAccNoCarry(cf, u, f[i], v, g[i])
    ssumprodAccNoCarry(cg, q, f[i], r, g[i])
    f[i-1] = cf.lo and Max
    g[i-1] = cg.lo and Max
    cf.ashr(k)
    cg.ashr(k)

  f[numLimbsLeft-1] = cf.lo
  g[numLimbsLeft-1] = cg.lo

func matVecMul_shr_k[N, E: static int](t: TransitionMatrix, f, g: var LimbsUnsaturated[N, E], k: static int) =
  matVecMul_shr_k_impl(t, f, g, E, N, k)

func invmodImpl[N, E](
       a: var LimbsUnsaturated[N, E],
       F, M: LimbsUnsaturated[N, E],
       invMod2k: SecretWord,
       k, bits: static int) =
  ## Modular inversion using Bernstein-Yang algorithm
  ## r ≡ F.a⁻¹ (mod M)

  # hdelta = delta-1/2, delta starts at 1/2 for the half-delta variant
  var hdelta = SignedSecretWord(0)
  var d{.noInit.}, e{.noInit.}: LimbsUnsaturated[N, E]
  var f{.noInit.}, g{.noInit.}: LimbsUnsaturated[N, E]

  d.setZero()
  e = F

  # g < f for partitioning / iteration count formula
  f = M
  g = a
  const partition = partitionDivsteps(bits, k)

  for i in 0 ..< partition.numChunks:
    var t{.noInit.}: TransitionMatrix
    let numIters = partition.chunkSize + int(i < partition.cutoff)
    # Compute transition matrix and next hdelta
    hdelta = t.batchedDivsteps(hdelta, f[0], g[0], numIters, k)
    # Apply the transition matrix
    # [u v]    [d]
    # [q r]/2ᵏ.[e]  mod M
    t.matVecMul_shr_k_mod_M(d, e, k, M, invMod2k)
    # [u v]    [f]
    # [q r]/2ᵏ.[g]
    t.matVecMul_shr_k(f, g, k)

  d.canonicalize(signMask = f.isNegMask(), M)
  a = d

func invmod*(
       r: var Limbs, a: Limbs,
       F, M: Limbs, bits: static int) =
  ## Compute the scaled modular inverse of ``a`` modulo M
  ## r ≡ F.a⁻¹ (mod M)
  ##
  ## M MUST be odd, M does not need to be prime.
  ## ``a`` MUST be less than M.
  const Excess = 2
  const k = WordBitWidth - Excess
  const NumUnsatWords = bits.ceilDiv_vartime(k)

  # Convert values to unsaturated repr
  var m2 {.noInit.}: LimbsUnsaturated[NumUnsatWords, Excess]
  var factor {.noInit.}: LimbsUnsaturated[NumUnsatWords, Excess]
  m2.fromPackedRepr(M)
  factor.fromPackedRepr(F)
  let m0invK = SecretWord invMod2k(BaseType M[0], k)

  var a2 {.noInit.}: LimbsUnsaturated[NumUnsatWords, Excess]
  a2.fromPackedRepr(a)
  a2.invmodImpl(factor, m2, m0invK, k, bits)
  r.fromUnsatRepr(a2)

func invmod*(
       r: var Limbs, a: Limbs,
       F, M: static Limbs, bits: static int) =
  ## Compute the scaled modular inverse of ``a`` modulo M
  ## r ≡ F.a⁻¹ (mod M) (compile-time factor and modulus overload)
  ##
  ## with F and M known at compile-time
  ##
  ## M MUST be odd, M does not need to be prime.
  ## ``a`` MUST be less than M.

  const Excess = 2
  const k = WordBitWidth - Excess
  const NumUnsatWords = bits.ceilDiv_vartime(k)

  # Convert values to unsaturated repr
  const m2 = LimbsUnsaturated[NumUnsatWords, Excess].fromPackedRepr(M)
  const factor = LimbsUnsaturated[NumUnsatWords, Excess].fromPackedRepr(F)
  const m0invK = SecretWord invMod2k(BaseType M[0], k)

  var a2 {.noInit.}: LimbsUnsaturated[NumUnsatWords, Excess]
  a2.fromPackedRepr(a)
  a2.invmodImpl(factor, m2, m0invK, k, bits)
  r.fromUnsatRepr(a2)

# ############################################################
#
#      Euler criterion, Legendre/Jacobi/Krönecker symbol
#
# ############################################################
#
# The Euler criterion, i.e. the quadratic residuosity test, for p an odd prime, is:
#  a^((p-1)/2) ≡  1 (mod p), iff a is a square
#              ≡ -1 (mod p), iff a is quadratic non-residue
#              ≡  0 (mod p), iff a is 0
# derived from Fermat's Little Theorem
#
# The Legendre symbol is a function with p odd prime
# (a/p)ₗ ≡  1 (mod p), iff a is a square
#        ≡ -1 (mod p), iff a is quadratic non-residue
#        ≡  0 (mod p), iff a is 0
#
# The Jacobi symbol generalizes the Legendre symbol for any odd n:
#   (a/n)ⱼ = ∏ᵢ (a/pᵢ)ₗ
# is the product of legendre symbol (a/pᵢ)ₗ with pᵢ the prime factors of n
#
# Those symbols can be computed either via exponentiation (Fermat's Little Theorem)
# or using slight modifications to the Extended Euclidean Algorithm for GCD.

func batchedDivstepsSymbol(
       t: var TransitionMatrix,
       hdelta: SignedSecretWord,
       f0, g0: SignedSecretWord,
       numIters: int,
       k: static int
     ): tuple[hdelta, L: SignedSecretWord] =
  ## Bernstein-Yang half-delta (hdelta) batch of divsteps
  ## with Legendre symbol tracking
  ##
  ## Output:
  ## - return hdelta for the next batch of divsteps
  ## - Returns the intermediate Legendre symbol
  ## - mutate t, the transition matrix to apply `numIters` divsteps at once
  ##   t is scaled by 2ᵏ
  ##
  ## Input:
  ## - f0, bottom limb of f
  ## - g0, bottom limb of g
  ## - numIters, number of iterations requested in this batch of divsteps
  ## - k, the maximum batch size, transition matrix is scaled by 2ᵏ

  var
    u = SignedSecretWord(1 shl (k-numIters))
    v = SignedSecretWord(0)
    q = SignedSecretWord(0)
    r = SignedSecretWord(1 shl (k-numIters))
    f = f0
    g = g0

    hdelta = hdelta
    L = SignedSecretWord(0)

  for i in k-numIters ..< k:
    debug:
      func reportLoop() =
        debugEcho "  iterations: [", k-numIters, ", ", k, ")", " (", numIters, " iterations in total)"
        debugEcho "  i: ", i, ", hdelta: ", int(hdelta)
        # debugEcho "    f: 0b", BiggestInt(f).toBin(64), ", g: 0b", BiggestInt(g).toBin(64), " | f: ", int(f), ", g: ", int(g)
        # debugEcho "    u: 0b", BiggestInt(u).toBin(64), ", v: 0b", BiggestInt(v).toBin(64), " | u: ", int(u), ", v: ", int(v)
        # debugEcho "    q: 0b", BiggestInt(q).toBin(64), ", r: 0b", BiggestInt(r).toBin(64), " | q: ", int(q), ", r: ", int(r)

      doAssert (BaseType(f) and 1) == 1, (reportLoop(); "f must be odd)")
      doAssert bool(u*f0 + v*g0 == f.lshl(i)), (reportLoop(); "Applying the transition matrix to (f₀, g₀) returns current (f, g)")
      doAssert bool(q*f0 + r*g0 == g.lshl(i)), (reportLoop(); "Applying the transition matrix to (f₀, g₀) returns current (f, g)")

    let fi = f

    # Conditional masks for (hdelta < 0) and g odd
    let c1 = hdelta.isNegMask()
    let c2 = g.isOddMask()
    # x, y, z, conditional negated complement of f, u, v
    let x = (f xor c1) - c1
    let y = (u xor c1) - c1
    let z = (v xor c1) - c1
    # conditional addition g, q, r
    g.cadd(x, c2)
    q.cadd(y, c2)
    r.cadd(z, c2)
    # c3 = (hdelta < 0) and g odd
    let c3 = c2 and c1
    # hdelta = -hdelta-2 or hdelta-1
    hdelta = (hdelta xor c3) - SignedSecretWord(1)
    # Conditionally rollback
    f.cadd(g, c3)
    u.cadd(q, c3)
    v.cadd(r, c3)
    # Shifts
    g = g.lshr(1)
    u = u.lshl(1)
    v = v.lshl(1)

    L = L + (((fi and f) xor f.lshr(1)) and SignedSecretWord(2))
    L = L + (L.isOdd() xor v.isNeg())
    L = L and SignedSecretWord(3)

  t.u = u
  t.v = v
  t.q = q
  t.r = r
  debug:
    doAssert bool(u*f0 + v*g0 == f.lshl(k)), "Applying the final matrix to (f₀, g₀) gives the final (f, g)"
    doAssert bool(q*f0 + r*g0 == g.lshl(k)), "Applying the final matrix to (f₀, g₀) gives the final (f, g)"
    doAssert checkDeterminant(t, u, v, q, r, k, numIters)

  return (hdelta, L)

func legendreImpl[N, E](
       a: var LimbsUnsaturated[N, E],
       M: LimbsUnsaturated[N, E],
       k, bits: static int): SecretWord =
  ## Legendre symbol / Quadratic Residuosity Test
  ## using Bernstein-Yang algorithm

  # hdelta = delta-1/2, delta starts at 1/2 for the half-delta variant
  var hdelta = SignedSecretWord(0)
  var f{.noInit.}, g{.noInit.}: LimbsUnsaturated[N, E]

  # g < f for partitioning / iteration count formula
  f = M
  g = a
  const partition = partitionDivsteps(bits, k)
  const UnsatBitWidth = WordBitWidth - a.Excess

  var # Track and accumulate Legendre symbol transitions
    accL = SignedSecretWord(0)
    L = SignedSecretWord(0)

  for i in 0 ..< partition.numChunks:
    var t{.noInit.}: TransitionMatrix
    let numIters = partition.chunkSize + int(i < partition.cutoff)
    # Compute transition matrix and next hdelta
    when f.words.len > 1:
      (hdelta, L) = t.batchedDivstepsSymbol(
                      hdelta,
                      # the symbol computation needs to see the extra 2 next bits.
                      f[0] or f[1].lshl(UnsatBitWidth),
                      g[0] or g[1].lshl(UnsatBitWidth),
                      numIters, k)
    else:
      (hdelta, L) = t.batchedDivstepsSymbol(hdelta, f[0], g[0], numIters, k)
    # [u v]    [f]
    # [q r]/2ᵏ.[g]
    t.matVecMul_shr_k(f, g, k)
    accL = (accL + L) and SignedSecretWord(3)
    accL = (accL + ((accL.isOdd() xor f.isNeg()))) and SignedSecretWord(3)

  accL = (accL + accL.isOdd()) and SignedSecretWord(3)
  accL = SignedSecretWord(1)-accL
  accL.csetZero(not f.isZeroMask())
  return SecretWord(accL)

func legendre*(a, M: Limbs, bits: static int): SecretWord =
  ## Compute the Legendre symbol
  ##
  ## (a/p)ₗ ≡ a^((p-1)/2) ≡  1 (mod p), iff a is a square
  ##                      ≡ -1 (mod p), iff a is quadratic non-residue
  ##                      ≡  0 (mod p), iff a is 0
  const Excess = 2
  const k = WordBitWidth - Excess
  const NumUnsatWords = bits.ceilDiv_vartime(k)

  # Convert values to unsaturated repr
  var m2 {.noInit.}: LimbsUnsaturated[NumUnsatWords, Excess]
  m2.fromPackedRepr(M)

  var a2 {.noInit.}: LimbsUnsaturated[NumUnsatWords, Excess]
  a2.fromPackedRepr(a)

  legendreImpl(a2, m2, k, bits)

func legendre*(a: Limbs, M: static Limbs, bits: static int): SecretWord =
  ## Compute the Legendre symbol (compile-time modulus overload)
  ##
  ## (a/p)ₗ ≡ a^((p-1)/2) ≡  1 (mod p), iff a is a square
  ##                      ≡ -1 (mod p), iff a is quadratic non-residue
  ##                      ≡  0 (mod p), iff a is 0

  const Excess = 2
  const k = WordBitWidth - Excess
  const NumUnsatWords = bits.ceilDiv_vartime(k)

  # Convert values to unsaturated repr
  const m2 = LimbsUnsaturated[NumUnsatWords, Excess].fromPackedRepr(M)

  var a2 {.noInit.}: LimbsUnsaturated[NumUnsatWords, Excess]
  a2.fromPackedRepr(a)

  legendreImpl(a2, m2, k, bits)


# ############################################################
#
#              Variable-time optimizations
#
# ############################################################

const NegInvMod256 = [
    # Stores tab[i div 2] = -i⁻¹ (mod 256), with i odd
    # See "invModBitwidth" on "Dumas iterations"
    # ax ≡ 1 (mod 2ᵏ) <=> ax(2 - ax) ≡ 1 (mod 2^(2k))
    # a⁻¹ (mod 256) = a(2-a²)
      -1, -235, -141, -183,  -57, -227, -133, -239,
    -241,  -91, -253, -167,  -41,  -83, -245, -223,
    -225, -203, -109, -151,  -25, -195, -101, -207,
    -209,  -59, -221, -135,   -9,  -51, -213, -191,
    -193, -171,  -77, -119, -249, -163,  -69, -175,
    -177,  -27, -189, -103, -233,  -19, -181, -159,
    -161, -139,  -45,  -87, -217, -131,  -37, -143,
    -145, -251, -157,  -71, -201, -243, -149, -127,
    -129, -107,  -13,  -55, -185,  -99,   -5, -111,
    -113, -219, -125,  -39, -169, -211, -117,  -95,
     -97,  -75, -237,  -23, -153,  -67, -229,  -79,
     -81, -187,  -93,   -7, -137, -179,  -85,  -63,
     -65,  -43, -205, -247, -121,  -35, -197,  -47,
     -49, -155,  -61, -231, -105, -147,  -53,  -31,
     -33,  -11, -173, -215,  -89,   -3, -165,  -15,
     -17, -123,  -29, -199,  -73, -115,  -21, -255]

func batchedDivsteps_vartime(
       t: var TransitionMatrix,
       eta: SignedSecretWord,
       f0, g0: SecretWord,
       k: static int
     ): SignedSecretWord {.tags:[Vartime].} =
  ## Bernstein-Yang eta (-delta) batch of divsteps
  ## **Variable-Time**
  ##
  ## Output:
  ## - return eta for the next batch of divsteps
  ## - mutate t, the transition matrix to apply `numIters` divsteps at once
  ##   t is scaled by 2ᵏ
  ##
  ## Input:
  ## - f0, bottom limb of f
  ## - g0, bottom limb of g
  ## - k, the maximum batch size, transition matrix is scaled by 2ᵏ

  template swapNeg(a, b) =
    var tmp = -a
    a = b
    b = tmp

  var
    u = One
    v = Zero
    q = Zero
    r = One
    f = f0
    g = g0

    eta = cast[SignedBaseType](eta)
    bitsLeft = cast[SignedBaseType](k)

  while true:
    # Count zeros up to bitsLeft and process a batch of divsteps up to that number
    let zeros = (BaseType(g) or (BaseType(1) shl bitsLeft)).countTrailingZeroBits_vartime()
    g = g shr zeros
    u = u shl zeros
    v = v shl zeros
    eta -= cast[SignedBaseType](zeros)
    bitsLeft -= cast[SignedBaseType](zeros)

    if bitsLeft == 0:
      break

    # Now process, the 1's.
    if eta < 0:
      eta = -eta
      swapNeg(f, g)
      swapNeg(u, q)
      swapNeg(v, r)

    # We process up to 6 1's at once
    const mask6 = SecretWord((1 shl 6) - 1)
    let limit = min(eta+1, bitsLeft)
    let maskLimit = (MaxWord shr (WordBitWidth - limit)) and mask6
    # Find the multiple of f to add to cancel the bottom min(limit, 6) bits of g
    let w = (g * SecretWord NegInvMod256[int((f and mask6) shr 1)]) and maskLimit

    # Next iteration will have at least 6 0's to process at once
    g += f*w
    q += u*w
    r += v*w

  t.u = SignedSecretWord u
  t.v = SignedSecretWord v
  t.q = SignedSecretWord q
  t.r = SignedSecretWord r
  return SignedSecretWord(eta)

func matVecMul_shr_k_partial(t: TransitionMatrix, f, g: var LimbsUnsaturated, len: int, k: static int) =
  ## Matrix-Vector multiplication with top part of f and g being zeros
  matVecMul_shr_k_impl(t, f, g, LimbsUnsaturated.Excess, len, k)

func isZero_vartime(a: LimbsUnsaturated, limbsLeft: int): bool {.tags:[VarTime].} =
  for i in 0 ..< limbsLeft:
    if a[i].int != 0:
      return false
  return true

func discardUnusedLimb_vartime[N, E: static int](limbsLeft: var int, f, g: var LimbsUnsaturated[N, E]) {.tags:[VarTime].} =
  ## If f and g both don't use their last limb, it will propagate the sign down to the previous one
  if limbsLeft == 1:
    return

  let fn = f[limbsLeft-1]
  let gn = g[limbsLeft-1]
  var mask = SignedSecretWord(0)
  mask = mask or (fn xor fn.isNegMask()) # 0 if last limb has nothing left but its sign
  mask = mask or (gn xor gn.isNegMask()) # 0 if last limb has nothing left but its sign
  if cast[SignedBaseType](mask) == 0:
    f[limbsLeft-2] = f[limbsLeft-2] or fn.lshl(WordBitWidth-E) # if only sign is left, the last limb is 11..11 if negative
    g[limbsLeft-2] = g[limbsLeft-2] or gn.lshl(WordBitWidth-E) # or 00..00 if positive
    limbsLeft -= 1

func invmodImpl_vartime[N, E: static int](
       a: var LimbsUnsaturated[N, E],
       F, M: LimbsUnsaturated[N, E],
       invMod2k: SecretWord,
       k, bits: static int) {.tags:[VarTime].} =
  ## **Variable-time** Modular inversion using Bernstein-Yang algorithm
  ## r ≡ F.a⁻¹ (mod M)

  # eta = -delta
  var eta = cast[SignedSecretWord](-1)
  var d{.noInit.}, e{.noInit.}: LimbsUnsaturated[N, E]
  var f{.noInit.}, g{.noInit.}: LimbsUnsaturated[N, E]

  d.setZero()
  e = F

  f = M
  g = a

  var limbsLeft = N

  while true:
    var t{.noInit.}: TransitionMatrix
    # Compute transition matrix and next eta
    eta = t.batchedDivsteps_vartime(eta, SecretWord f[0], SecretWord g[0], k)
    # Apply the transition matrix
    # [u v]    [d]
    # [q r]/2ᵏ.[e]  mod M
    t.matVecMul_shr_k_mod_M(d, e, k, M, invMod2k)
    # [u v]    [f]
    # [q r]/2ᵏ.[g]
    t.matVecMul_shr_k_partial(f, g, limbsLeft, k)
    if g.isZero_vartime(limbsLeft):
      break
    limbsLeft.discardUnusedLimb_vartime(f, g)

  d.canonicalize(signMask = f[limbsLeft-1].isNegMask(), M)
  a = d

func invmod_vartime*(
       r: var Limbs, a: Limbs,
       F, M: Limbs, bits: static int) {.tags:[VarTime].} =
  ## Compute the scaled modular inverse of ``a`` modulo M
  ## r ≡ F.a⁻¹ (mod M)
  ##
  ## M MUST be odd, M does not need to be prime.
  ## ``a`` MUST be less than M.
  const Excess = 2
  const k = WordBitWidth - Excess
  const NumUnsatWords = bits.ceilDiv_vartime(k)

  # Convert values to unsaturated repr
  var m2 {.noInit.}: LimbsUnsaturated[NumUnsatWords, Excess]
  var factor {.noInit.}: LimbsUnsaturated[NumUnsatWords, Excess]
  m2.fromPackedRepr(M)
  factor.fromPackedRepr(F)
  let m0invK = SecretWord invMod2k(BaseType M[0], k)

  var a2 {.noInit.}: LimbsUnsaturated[NumUnsatWords, Excess]
  a2.fromPackedRepr(a)
  a2.invmodImpl_vartime(factor, m2, m0invK, k, bits)
  r.fromUnsatRepr(a2)

func invmod_vartime*(
       r: var Limbs, a: Limbs,
       F, M: static Limbs, bits: static int) {.tags:[VarTime].} =
  ## Compute the scaled modular inverse of ``a`` modulo M
  ## r ≡ F.a⁻¹ (mod M) (compile-time factor and modulus overload)
  ##
  ## with F and M known at compile-time
  ##
  ## M MUST be odd, M does not need to be prime.
  ## ``a`` MUST be less than M.

  const Excess = 2
  const k = WordBitWidth - Excess
  const NumUnsatWords = bits.ceilDiv_vartime(k)

  # Convert values to unsaturated repr
  const m2 = LimbsUnsaturated[NumUnsatWords, Excess].fromPackedRepr(M)
  const factor = LimbsUnsaturated[NumUnsatWords, Excess].fromPackedRepr(F)
  const m0invK = SecretWord invMod2k(BaseType M[0], k)

  var a2 {.noInit.}: LimbsUnsaturated[NumUnsatWords, Excess]
  a2.fromPackedRepr(a)
  a2.invmodImpl_vartime(factor, m2, m0invK, k, bits)
  r.fromUnsatRepr(a2)