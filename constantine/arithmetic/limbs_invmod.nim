# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/common,
  ../primitives,
  ./limbs, ./limbs_unsaturated

# No exceptions allowed
{.push raises: [].}

# ############################################################
#
#                  Modular arithmetic (mod 2ᵏ)
#
# ############################################################

func div2_modular*(a: var Limbs, mp1div2: Limbs) {.inline.} =
  ## Modular Division by 2
  ## `a` will be divided in-place
  ## `mp1div2` is the modulus (M+1)/2
  ##
  ## Normally if `a` is odd we add the modulus before dividing by 2
  ## but this may overflow and we might lose a bit before shifting.
  ## Instead we shift first and then add half the modulus rounded up
  ##
  ## Assuming M is odd, `mp1div2` can be precomputed without
  ## overflowing the "Limbs" by dividing by 2 first
  ## and add 1
  ## Otherwise `mp1div2` should be M/2

  # if a.isOdd:
  #   a += M
  # a = a shr 1
  let wasOdd = a.isOdd()
  a.shiftRight(1)
  let carry {.used.} = a.cadd(mp1div2, wasOdd)
  debug: doAssert not carry.bool

func invModBitwidth(a: BaseType): BaseType =
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

  const k = log2_vartime(a.sizeof() * 8)
  result = a                 # Start from an inverse of M0 modulo 2, M0 is odd and it's own inverse
  for _ in 0 ..< k:          # at each iteration we get the inverse mod(2^2k)
    result *= 2 - a * result # x' = x(2 - ax)

func invMod2powK(M0: BaseType, k: static BaseType): BaseType =
  ## Compute 1/M mod 2ᵏ
  ## from M[0]
  # Algorithm: Cetin Kaya Koc (2017) p11, https://eprint.iacr.org/2017/411
  # Once you have a modular inverse (mod 2ˢ) you can reduce
  # (mod 2ᵏ) to have the modular inverse (mod 2ᵏ)
  static: doAssert k <= WordBitWidth
  const maskMod = (1 shl k)-1
  M0.invModBitwidth() and maskMod

# ############################################################
#
#            Modular inversion (Niels Möller)
#
# ############################################################

# Algorithm by Niels Möller
# ------------------------------------------------------------
# a modified version of Stein's Algorithm (binary Extended Euclid GCD)
#
# Algorithm 5 in
# Fast Software Polynomial Multiplication on ARM Processors Using the NEON Engine
# Danilo Camara, Conrado P. L. Gouvea, Julio Lopez, and Ricardo Dahab
# https://link.springer.com/content/pdf/10.1007%2F978-3-642-40588-4_10.pdf
#
# Input: integer x, odd integer n, x < n
# Output: x−1 (mod n)
# 1:   function ModInv(x, n)
# 2:   (a, b, u, v) ← (x, n, 1, 1)
# 3:   ℓ ← ⌊log2 n⌋ + 1            ⮚ number of bits in n
# 4:   for i ← 0 to 2ℓ − 1 do
# 5:     odd ← a & 1
# 6:     if odd and a ≥ b then
# 7:       a ← a − b
# 8:     else if odd and a < b then
# 9:       (a, b, u, v) ← (b − a, a, v, u)
# 10:    a ← a >> 1
# 11:    if odd then u ← u − v
# 12:    if u < 0 then u ← u + n
# 13:    if u & 1 then u ← u + n
# 14:    u ← u >> 1
# 15:  return v
#
# Warning ⚠️: v should be 0 at initialization
#
# We modify it to return F . a^-1
# So that we can pass an adjustment factor F
# And directly compute modular division or Montgomery inversion

func mollerInvMod*(v: var Limbs, a: Limbs, F, M: Limbs, bits: int, mp1div2: Limbs) =
  ## Compute F multiplied the modular inverse of ``a`` modulo M
  ## r ≡ F . a^-1 (mod M)
  ##
  ## M MUST be odd, M does not need to be prime.
  ## ``a`` MUST be less than M.
  ##
  ## No information about ``a`` in particular its actual length in bits is leaked.
  ##
  ## This takes (M+1)/2 (mp1div2) as a precomputed parameter as a slight optimization
  ## in stack size and speed.
  ##
  ## The inverse of 0 is 0.

  # Ideally we need registers for a, b, u, v
  # but:
  #   - Even with ~256-bit primes, that's 4 limbs = 4*4 => 16 registers
  #   - x86_64 only has 16 general purposes registers
  #   - Registers are needed for the loop counter and comparison results
  #   - CMOV is reg <- RM so can move registers/memory into registers
  #     but cannot move into memory.
  # so we choose to keep "v" from the algorithm in memory as `r`

  # TODO: the inlining of primitives like `csub` is bad for codesize
  #       but there is a 80% slowdown without it.

  var a = a
  var b = M
  var u = F
  v.setZero()

  for i in 0 ..< 2 * bits:
    debug: doAssert bool(b.isOdd)
    let isOddA = a.isOdd()

    # if isOddA: a -= b
    let aLessThanB = isOddA and (SecretBool) a.csub(b, isOddA)
    # if a < b and the sub was processed
    # in that case, b <- a = a - b + b
    discard b.cadd(a, aLessThanB)
    # and a <- -new_a = (b-a)
    a.cneg(aLessThanB)
    debug: doAssert not bool(a.isOdd)
    a.shiftRight(1)

    # Swap u and v is a < b
    u.cswap(v, aLessThanB)
    # if isOddA: u -= v (mod M)
    let neg = isOddA and (SecretBool) u.csub(v, isOddA)
    discard u.cadd(M, neg)

    # u = u/2 (mod M)
    u.div2_modular(mp1div2)

  debug:
    doAssert bool a.isZero()
    # GCD exist (always true if a and M are relatively prime)
    doAssert bool b.isOne() or
      # or not (on prime fields iff input was zero) and no GCD fallback output is zero
      v.isZero()

# ############################################################
#
#            Modular inversion (Thomas Pornin)
#
# ############################################################

# Algorithm by Thomas Pornin
# ------------------------------------------------------------
# a modified version of Stein's Algorithm (binary Extended Euclid GCD)
#
# - https://github.com/pornin/bingcd
# - https://eprint.iacr.org/2020/972.pdf
# - Discussion on SIMD optimization https://github.com/supranational/blst/issues/62
#
# Correctly and efficiently implementing it for generic primes is actually tricky:
# - L22: (u, v) ← (uf₀ + vg₀ mod m, uf₁ + vg₁ mod m)
#   This requires efficient modular reduction. This is true for Generalized Mersenne Primes
#   like secp256k1 or ED25519 but not BLS12-381
# - Supranational / BLST's authors delayed the modular reduction but this triggered
#   an edge case in fuzzing: https://github.com/supranational/blst/commit/fd45352#commitcomment-66068518
#   In the past there was another edge case raised:
#   - https://github.com/supranational/blst/commit/3533291
# - The efficient implementation requires:
#   - Assembly for cmov in inner loop, leading zero count
#     - Note: it requires lzcount as clz(0) is undefined.
#       https://github.com/bitcoin-core/secp256k1/pull/767#issuecomment-679116483
#   - fast modular reduction
#   - an extra bit in the high word for negative integers, making it unsuitable for secp256k1 or P256
#     when using a saturated representation.
#
# Sketch of Nim implementation at:
# - https://github.com/mratsim/constantine/blob/874efa8/constantine/arithmetic/limbs_invmod.nim
# - or https://gist.github.com/mratsim/a48f2ae26d1a939cc5bbeda8c4e84f7a

# ###############################################################
#
#   Modular inversion (Bernstein-Yang Modified by Dettman-Wuille)
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
    var e: array[2, SecretWord]
    smul(a[1], a[0], u, r)
    smul(b[1], b[0], v, q)

    var borrow: Borrow
    subB(borrow, a[0], a[0], b[0], Borrow(0))
    subB(borrow, a[1], a[1], b[1], borrow)

    let d = 2*k - numIters
    b[0] = Zero; b[1] = Zero
    b[d div WordBitwidth] = One shl (d mod WordBitwidth)

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
  if bits == 256:
    # https://github.com/sipa/safegcd-bounds/tree/master/coq
    # For 256-bit inputs, 590 divsteps are sufficient with hddivstep variant (half-delta divstep)
    # for gcd(f, g) with 0 <= g <= f <= Modulus (inversion g == 1)
    # The generic formula reports 591
    return (590, 10, 59, 0)
  else:
    # https://github.com/sipa/safegcd-bounds/blob/master/genproofhd.md
    # For any input, for gcd(f, g) with 0 <= g <= f <= Modulus with hddivstep variant (half-delta divstep)
    # (inversion g == 1)
    let totalIters = (45907*bits + 26313) div 19929
    let numChunks = (totalIters + wordBitWidth-1) div wordBitWidth
    let chunkSize = totalIters div numChunks
    let cutoff = totalIters mod numChunks
    return (totalIters, numChunks, chunkSize, cutoff)

func batchedDivsteps(
       t: var TransitionMatrix,
       theta: SignedSecretWord,
       f0, g0: SignedSecretWord,
       numIters: int,
       k: static int
     ): SignedSecretWord =
  ## Bernstein-Yang half-delta (theta) batch of divsteps
  ## 
  ## Output:
  ## - return theta for the next batch of divsteps
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

    theta = theta

  for i in k-numIters ..< k:
    debug:
      func reportLoop() =
        debugEcho "  iterations: [", k-numIters, ", ", k, ")"
        debugEcho "  i: ", i, ", theta: ", int(theta)
        # debugEcho "    f: 0b", BiggestInt(f).toBin(64), ", g: 0b", BiggestInt(g).toBin(64), " | f: ", int(f), ", g: ", int(g)
        # debugEcho "    u: 0b", BiggestInt(u).toBin(64), ", v: 0b", BiggestInt(v).toBin(64), " | u: ", int(u), ", v: ", int(v)
        # debugEcho "    q: 0b", BiggestInt(q).toBin(64), ", r: 0b", BiggestInt(r).toBin(64), " | q: ", int(q), ", r: ", int(r)

      doAssert (f.BaseType and 1) == 1, (reportLoop(); "f must be odd)")
      doAssert bool(not(uint(u or v or q or r) and (if i == 0: high(uint) else: high(uint) shr (i - 1)))), (reportLoop(); "Min trailing zeros count decreases at each iteration")
      doAssert bool(u.ashr(k-i)*f0 + v.ashr(k-i)*g0 == f.lshl(i)), (reportLoop(); "Applying the transition matrix to (f₀, g₀) returns current (f, g)")
      doAssert bool(q.ashr(k-i)*f0 + r.ashr(k-i)*g0 == g.lshl(i)), (reportLoop(); "Applying the transition matrix to (f₀, g₀) returns current (f, g)")

    # Conditional masks for (theta < 0) and g odd
    let c1 = theta.isNegMask()
    let c2 = g.isOddMask()
    # x, y, z, conditional complement of f, u, v
    let x = f xor c1
    let y = u xor c1
    let z = v xor c1
    # conditional substraction from g, q, r
    g.csub(x, c2)
    q.csub(y, c2)
    r.csub(z, c2)
    # c3 = (theta >= 0) and g odd
    let c3 = c2 and not c1
    # theta = -theta or theta+1
    theta = (theta xor c3) + SignedSecretWord(1)
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

  return theta

func matVecMul_shr_k_mod_M[N, E: static int](
       t: TransitionMatrix,
       d, e: var LimbsUnsaturated[N, E],
       k: static int,
       M: LimbsUnsaturated[N, E],
       invMod2powK: SecretWord
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
  cd.slincombAccNoCarry(u, d[0], v, e[0])
  ce.slincombAccNoCarry(q, d[0], r, e[0])

  # Compute me and md, multiples of M
  # such as the bottom k bits if d and e are 0
  # This allows fusing division by 2ᵏ
  # i.e. (mx * M) mod 2ᵏ = x mod 2ᵏ
  var md, me = SignedSecretWord(0)
  md.cadd(u, sign_d)
  md.cadd(v, sign_e)
  me.cadd(q, sign_d)
  me.cadd(r, sign_e)
  
  md = md - (SignedSecretWord(invMod2powK * SecretWord(cd.lo) + SecretWord(md)) and Max)
  me = me - (SignedSecretWord(invMod2powK * SecretWord(ce.lo) + SecretWord(me)) and Max)

  # First iteration of [u v] [d]   [md]
  #                    [q r].[e] + [me].M[0]
  # k bottom bits are 0
  cd.smulAccNoCarry(md, M[0])
  ce.smulAccNoCarry(me, M[0])
  cd.ashr(k)
  ce.ashr(k)

  for i in 1 ..< N:
    cd.slincombAccNoCarry(u, d[i], v, e[i])
    ce.slincombAccNoCarry(q, d[i], r, e[i])
    cd.smulAccNoCarry(md, M[i])
    ce.smulAccNoCarry(me, M[i])
    d[i-1] = cd.lo and Max
    e[i-1] = ce.lo and Max
    cd.ashr(k)
    ce.ashr(k)
  
  d[N-1] = cd.lo
  e[N-1] = ce.lo

func matVecMul_shr_k[N, E: static int](
       t: TransitionMatrix,
       f, g: var LimbsUnsaturated[N, E],
       k: static int     
  ) =
  ## Compute
  ##      
  ## [u v] [f] 
  ## [q r].[g] / 2ᵏ

  static: doAssert k == WordBitWidth - E
  const Max = SignedSecretWord(MaxWord shr E)

  let
    u = t.u
    v = t.v
    q = t.q
    r = t.r

  # Double-signed-word carries
  var cf, cg: DSWord
  
  # First iteration of [u v] [f] 
  #                    [q r].[g]
  cf.slincombAccNoCarry(u, f[0], v, g[0])
  cg.slincombAccNoCarry(q, f[0], r, g[0])
  # bottom k bits are zero by construction
  debug:
    doAssert BaseType(cf.lo and Max) == 0, "bottom k bits should be 0, cf.lo: " & $BaseType(cf.lo)
    doAssert BaseType(cg.lo and Max) == 0, "bottom k bits should be 0, cg.lo: " & $BaseType(cg.lo)

  cf.ashr(k)
  cg.ashr(k)

  for i in 1 ..< N:
    cf.slincombAccNoCarry(u, f[i], v, g[i])
    cg.slincombAccNoCarry(q, f[i], r, g[i])
    f[i-1] = cf.lo and Max
    g[i-1] = cg.lo and Max
    cf.ashr(k)
    cg.ashr(k)
  
  f[N-1] = cf.lo
  g[N-1] = cg.lo

func bernsteinYangInvMod_impl[N, E](
       a: var LimbsUnsaturated[N, E],
       F, M: LimbsUnsaturated[N, E],
       invMod2powK: SecretWord,
       k, bits: static int) =
  ## Modular inversion using Bernstein-Yang algorithm
  ## r ≡ F.a⁻¹ (mod M)

  # theta = delta-1/2, delta starts at 1/2 for the half-delta variant
  var theta = SignedSecretWord(0)
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
    # Compute transition matrix and next theta
    theta = t.batchedDivsteps(theta, f[0], g[0], numIters, k)
    # Apply the transition matrix
    # [u v]    [d] 
    # [q r]/2ᵏ.[e]  mod M
    t.matVecMul_shr_k_mod_M(d, e, k, M, invMod2powK)
    # [u v]     [f] 
    # [q r]/ 2ᵏ.[g] 
    t.matVecMul_shr_k(f, g, k)

  d.canonicalize(signMask = f.isNegMask(), M)
  a = d

func bernsteinYangInvMod*(
       r: var Limbs, a: Limbs,
       F, M: Limbs, bits: static int) =
  ## Compute the modular inverse of ``a`` modulo M
  ## r ≡ F.a⁻¹ (mod M)
  ##
  ## M MUST be odd, M does not need to be prime.
  ## ``a`` MUST be less than M.
  ## 
  # TODO: compile-time overload to cache F and M for field arithmetic
  
  const Excess = 2
  const k = WordBitwidth - Excess
  const NumUnsatWords = (bits + k - 1) div k

  # Convert values to unsaturated repr
  var m2 {.noInit.}: LimbsUnsaturated[NumUnsatWords, Excess]
  var factor {.noInit.}: LimbsUnsaturated[NumUnsatWords, Excess]
  m2.fromPackedRepr(M)
  factor.fromPackedRepr(F)
  let invMod2PowK = SecretWord invMod2powK(BaseType M[0], k)

  var a2 {.noInit.}: LimbsUnsaturated[NumUnsatWords, Excess]
  a2.fromPackedRepr(a)
  a2.bernsteinYangInvMod_impl(factor, m2, invMod2PowK, k, bits)
  r.fromUnsatRepr(a2)