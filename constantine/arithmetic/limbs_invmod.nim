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
  ./limbs, ./limbs_extmul

# No exceptions allowed
{.push raises: [].}

# ############################################################
#
#                  Modular division by 2ᴺ
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

func invMod2powN(negInvModWord, n: static BaseType): BaseType =
  ## Compute 1/M mod 2ᴺ
  ## from -1/M[0] (mod 2^WordBitWidth)
  # Algorithm: Cetin Kaya Koc (2017) p11, https://eprint.iacr.org/2017/411
  # Once you have a modular inverse (mod 2ˢ) you can reduce
  # (mod 2ᵏ) to have the modular inverse (mod 2ᵏ)
  static: doAssert n <= WordBitWidth
  const maskMod = (1 shl n)-1
  (-negInvModWord) and maskMod

func div2powN_modular*(a: var Limbs, negInvModWord, n: static BaseType) =
  ## Fast division a / 2ⁿ (mod p)
  # see secp256k1 explanation
  #
  # Instead of precomputing 1 / 2ⁿ (mod p)
  # and multiplying (line 1445 `gf_mul_inline(d, &v, &GF_INVT508);`)
  # as in the original code we save a multiplication by a multiple of p
  # that will zero the `n` lower bits of a before shifting those bits out.

  # Find `m` such that m*M has the same bottom N bits as x
  #     (m * p) mod 2ᴺ = x mod 2ᴺ
  # <=> m mod 2ᴺ = (x / p) mod 2ᴺ
  # <=> m mod 2ᴺ = (x * invpmod2n) mod 2ᴺ
  const maskMod = (1 shl n)-1

  # let invpmod2n = negInvModWord.invMod2powN(n)
  # let m = (a[0] * invpmod2n) and maskMod
  # (carry, t) = m * M (can be precomputed)
  # (borrow, a) = a - (carry, t)
  # a = (borrow, a) >> n

  # Alternatively, instead of substracting and negating negInvModWord
  # let negm = (a[0] * negInvModWord) and maskMod
  # (carry, t) = negm * M (can be precomputed)
  # (carry, a) = a + (carry, negm)
  # a = (carry, a) >> n

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

func mollerGCD*(v: var Limbs, a: Limbs, F, M: Limbs, bits: int, mp1div2: Limbs) =
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

# DEBUG
import ../config/[common, type_bigint]

func shl2L_hi(w_hi, w_lo: SecretWord, k: SomeUnsignedInt): SecretWord =
  ## Returns the hi word after
  ## shifting left of a double-precision word by k
  ## Assumes k <= WordBitWidth
  debug:
    doAssert(0 < k and k < WordBitWidth, "k: " & $k)
  SecretWord((BaseType(w_hi) shl k) or (BaseType(w_lo) shr (WordBitWidth - k)))

# {.push checks: off.}
func approx_a_b[N: static int](abar, bbar: var SecretWord, a, b: Limbs[N], k: static int) =
  ## Combine the hi and lo bits of a and b into an approximation 
  # This is Algorithm 2, line 2 to 5
  # n ← max(len(a),len(b),2k)
  # ā ← (a mod 2^(k−1)) + 2^(k−1) * floor(a/2^(n−k−1))
  # ƀ ← (b mod 2^(k−1)) + 2^(k−1) * floor(b/2^(n−k−1))
  #
  # With k = 32 we want to extract
  # the k-1 = 31 low bits
  # and k+1 = 33 top bits of a and b
  static: doAssert k.isPowerOf2()

  var
    a_hi = a[N-1]
    b_hi = b[N-1]
    a_nx = a[N-2]
    b_nx = b[N-2]

  for i in countdown(N-3, 0, 1):
    let mswNotFound = (a_hi or b_hi).isZero()
    mswNotFound.ccopy(a_hi, a_nx)
    mswNotFound.ccopy(b_hi, b_nx)
    mswNotFound.ccopy(a_nx, a[i])
    mswNotFound.ccopy(b_nx, b[i])

  # Shifts mod WordBitwidth
  let s = 2*k - log2(BaseType(a_hi or b_hi)) - 1
  const keep2km1 = SecretWord((1'u64 shl (k-1)) - 1)
  const clear2km1 = not(keep2km1)

  abar = (a[0] and keep2km1) or (shl2L_hi(a_hi, a_nx, s) and clear2km1)
  bbar = (b[0] and keep2km1) or (shl2L_hi(b_hi, b_nx, s) and clear2km1)
# {.pop.}

type
  UpdateFactors = object
    ## Transition matrix to apply
    f0, g0: SecretWord
    f1, g1: SecretWord

func extGCDstep(
       uf: var UpdateFactors,
       abar, bbar: SecretWord,
       k: static int
     ) =
  ## From the approximation ā, ƀ (with only k+1 top bits and k-1 low bits)
  ## to compute GCD(a, b),
  ## compute a transition matrix uf = [f0, g0, f1, g1]
  ## to apply to a, b, u, v
  ## 
  ## Assuming 64-bit and so k = 32, allowing extGCstep for k-1 = 31 iterations
  ## f₀g₀ = (f₀ + 2³¹-1) + (g₀+2³¹-1)*2³²
  ## f₁g₁ = (f₁ + 2³¹-1) + (g₁+2³¹-1)*2³²
  
  template setFactors(f, g: uint): SecretWord =
    # The addition of the constant 2³¹ −1 to each
    # update factor ensures that the stored values remain positive;
    # thus, there will be no unwanted
    # carry propagating from the low to high halves of the registers. 
    SecretWord(f + (1'u shl (k-1)) - 1 + ((g + (1'u shl (k-1)) - 1) shl k))

  template lo(uf: SecretWord): SecretWord =
    const mask = SecretWord((1 shl k) - 1)
    (uf and mask) - ((One shl (k-1)) - One)
  template hi(uf: SecretWord): SecretWord =
    const mask = SecretWord((1 shl k) - 1)
    ((uf shr k) and mask) - ((One shl (k-1)) - One)

  var f0g0 = setFactors(1, 0)
  var f1g1 = setFactors(0, 1)
  const bias = setFactors(0, 0)

  var a = abar
  var b = bbar

  for i in 0 ..< k:
    debug: doAssert bool(b.isOdd)
    
    # Save values before conditional processing
    let
      ta = a
      tb = b
      tf0g0 = f0g0
      tf1g1 = f1g1
    
    # Conditional swap if ā < ƀ
    let aLessThanB = a < b
    aLessThanB.ccopy(a, b)
    aLessThanB.ccopy(b, ta)
    aLessThanB.ccopy(f0g0, f1g1)
    aLessThanB.ccopy(f1g1, tf0g0)

    # ā <- ā-ƀ, (f₀, g₀) <- (f₀-f₁, g₀-g₁)
    a -= b
    f0g0 -= f1g1
    f0g0 += bias

    # If ā was even, rollback
    let isOddA = SecretBool(ta and One)
    isOddA.ccopy(a, ta)
    isOddA.ccopy(b, tb)
    isOddA.ccopy(f0g0, tf0g0)
    isOddA.ccopy(f1g1, tf1g1)

    # ā <- ā/2 if even, ā <- (ā-ƀ)/2 if odd
    a = a shr 1

    # (f₁, g₁) <- (2f₁, 2g₁)
    f1g1 += f1g1
    f1g1 -= bias
  
  block:
    uf.f0 = f0g0.lo()
    uf.g0 = f0g0.hi()
    uf.f1 = f1g1.lo()
    uf.g1 = f1g1.hi()

func slincomb[M, N: static int](
      r: var Limbs[M],
      a, b: Limbs[N],
      f, g: SecretWord) =
  ## Compute the signed dot product / linear combination
  ##      [f]
  ## [a b][g] = r
  ## 
  ## r <- (af + bg)
  
  # TODO: Nim bug, can't use "r: var Limbs[N+1]"
  static: doAssert M == N+1

  # TODO: this assumes that the sign bit fits in Limbs[N]
  # for example secp256k1 uses the full 256-bit and cannot use this.

  var ta{.noInit.}, tb{.noinit.}: Limbs[N]

  # Make f and g non-negative for multiplication
  let negF = f.isMsbSet()
  var f = f.cneg(negF)         # set f to |f| with conditional negation
  ta.cneg(a, SecretBool negF)

  let negG = g.isMsbSet()
  var g = g.cneg(negG)         # set g to |g| with conditional negation
  tb.cneg(b, SecretBool negG)

  # Compute a*f+b*g, f and g are 2ᵏ⁻¹ with k = WordBitsize / 2
  # Assuming 64-bit words, k = 32, f, g <= 2³¹
  # hence aᵢ*f is at most 64+31 = 95 bits
  # and aᵢ*f + bᵢ*g + carry is at most 97 bits
  #
  # We could take advantage of that in multi-precision multiplication
  # but in practice there is no performance improvement (on x86-64)
  # so we stay generic.
  var af{.noInit.}, bg{.noInit.}: Limbs[M]
  af.prod(ta, [f])
  bg.prod(tb, [g])
  discard r.sum(af, bg)

func abs_lincomb_shr[N: static int](
      r: var Limbs[N],
      a, b: Limbs[N],
      f, g: SecretWord,
      s : static int): SecretBool =
  ## Compute the absolute value of the signed dot product / linear combination
  ##      [f]
  ## [a b][g] / 2ˢ = r
  ## 
  ## r <- (af + bg) / 2ˢ
  ## and r is then set to the absolute value |r|
  ## 
  ## The function
  ##   returns true if r was negative
  ##   false otherwise
  ## 
  ## f, g <= 2ˢ
  
  # TODO: this assumes that the sign bit fits in Limbs[N]
  # for example secp256k1 uses the full 256-bit and cannot use this.
  
  static: doAssert s < WordBitWidth

  var z {.noInit.}: Limbs[N+1]
  z.slincomb(a, b, f, g)

  # Divide by 2ˢ, except the last limb
  for i in 0 ..< N:
    z[i] = (z[i] shr s) or (z[i+1] shl (WordBitWidth - s))

  # Return |z| and if z was negative.
  # r: Limbs[N] and z: Limbs[N+1], after shift
  result = z[N].isMsbSet()
  let mask = -SecretWord(result)     # Obtain a 0xFF... or 0x00... mask
  var carry = SecretWord(result)
  for i in 0 ..< r.len:
    let t = (z[i] xor mask) + carry  # XOR with mask and add 0x01 or 0x00 respectively
    carry = SecretWord(t < carry)    # Carry on
    r[i] = t

func porninGCD*[N: static int](v: var Limbs[N], a: Limbs[N], F, M: Limbs[N], bits: int) =
  ## Compute F multiplied the modular inverse of ``a`` modulo M
  ## r ≡ F . a^-1 (mod M)
  ##
  ## M MUST be odd, M does not need to be prime.
  ## ``a`` MUST be less than M.
  ##
  ## No information about ``a`` in particular its actual length in bits is leaked.
  ##
  ## The inverse of 0 is 0.

  var a = a
  var b = M
  var u = F
  v.setZero()

  const k = WordBitwidth div 2
  for i in 0 ..< (2 * bits + (k-1)) div k:
    var abar{.noInit.}, bbar{.noInit.}: SecretWord
    var t{.noInit.}: typeof(a)
    approx_a_b(abar, bbar, a, b, k)
    var uf{.noInit.}: UpdateFactors
    uf.extGCDstep(abar, bbar, k)
    
    # L17-21 - Compute (a, b) and fix approximation
    let negA = t.abs_lincomb_shr(a, b, uf.f0, uf.g0, k-1)
    let negB = b.abs_lincomb_shr(a, b, uf.f1, uf.g1, k-1)
    a.cneg(t, negA)
    uf.f0 = uf.f0.cneg(negA)
    uf.g0 = uf.g0.cneg(negA)
    b.cneg(negB)
    uf.f1 = uf.f1.cneg(negB)
    uf.g1 = uf.g1.cneg(negB)

    # L22 - (u, v) ← (uf₀ + vg₀ mod m, uf₁ + vg₁ mod m)
    # Note: u was initialized with R² (mod m) and v with 0
    # Do we need (mod m)?
    var un1{.noInit.}, vn1{.noInit.}: Limbs[N+1]
    un1.slincomb(u, v, uf.f0, uf.g0)
    vn1.slincomb(u, v, uf.f1, uf.g1)

{.pop.} # raises no exceptions

# Sanity Checks
# ------------------------------------------------------------

when isMainModule:
  import 
    ../config/type_bigint, ../io/io_bigints,
    ./limbs_extmul,
    std/[strutils, times, monotimes]

  proc checkApprox() =
    let test = [
        (
          "0xFFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF",
          "0x0FFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF"
        ),
        (
          "0x0FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFF",
          "0x00FFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFF"
        ),
        (
          "0x000000000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFF",
          "0x0000000000FFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFF"
        ),
        (
          "0x00000000000000000000000000000000000000000FFFF0000FFF",
          "0x000000000000000000000000000000000000000000FFF0000FFF"
        ),
        (
          "0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaaa",
          "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F"
        )
    ]

    # Python impl
    #
    # def approx_ab(a, b, k):
    #     ## n ← max(len(a),len(b),2k)
    #     ## ā ← (a mod 2^(k−1)) + 2^(k−1) * floor(a/2^(n−k−1))
    #     ## ƀ ← (b mod 2^(k−1)) + 2^(k−1) * floor(b/2^(n−k−1))
    #     n = max(a.bit_length(), b.bit_length(), 2*k)
    #
    #     abar = (a % 2**(k-1)) + 2**(k-1) * (a // (2**(n-k-1)))
    #     bbar = (b % 2**(k-1)) + 2**(k-1) * (b // (2**(n-k-1)))
    #     return abar, bbar
    #
    # for a, b in test:
    #     a = int(a, 16)
    #     b = int(b, 16)
    #     print(f'a: {a:#0{98}x}')
    #     print(f'b: {b:#0{98}x}')
    #     abar, bbar =  approx_ab(a, b, 32)
    #     print(f'ā: {abar:#0{18}x}')
    #     print(f'ƀ: {bbar:#0{18}x}')

    for (a, b) in test:
      let a = BigInt[381].fromHex(a)
      let b = BigInt[381].fromHex(b)
      echo "a: ", a.toHex()
      echo "b: ", b.toHex()
      var abar, bbar: SecretWord
      approx_a_b(abar, bbar, a.limbs, b.limbs, k=32)
      echo "abar: ", abar.BaseType.toHex()
      echo "bbar: ", bbar.BaseType.toHex()

  proc checkLinComb() =
    let a = BigInt[383].fromHex"0x7FFFFFFFFFFFFFFF_FFFFFFFFFFFFFFFF_FFFFFFFFFFFFFFFF_FFFFFFFFFFFFFFFF_FFFFFFFFFFFFFFFF_FFFFFFFFFFFFFFFF"
    let b = BigInt[383].fromHex"0x7FFFFFFFFFFFFFFF_FFFFFFFFFFFFFFFF_FFFFFFFFFFFFFFFF_FFFFFFFFFFFFFFFF_FFFFFFFFFFFFFFFF_FFFFFFFFFFFFFFFF"
    let f = BigInt[31].fromHex"0x7FFFFFFF"
    let g = BigInt[31].fromHex"0x7FFFFFFF"
    const iters = 1000000

    var af, bg: BigInt[415]
    var start = getMonoTime()
    for i in 0 ..< iters:
      af.limbs.prod(a.limbs, f.limbs)
      bg.limbs.prod(b.limbs, g.limbs)
      discard af.limbs.add(bg.limbs)
    var stop = getMonoTime()

    echo "Expected: ", af.toHex()
    echo "Evaluated in ", float64(inMicroseconds(stop-start)) / float64 iters, " µs"

    var r: BigInt[415]
    start = getMonoTime()
    for i in 0 ..< iters:
      r.limbs.slincomb(a.limbs, b.limbs, f.limbs[0], g.limbs[0])
    stop = getMonoTime()

    echo "Computed: ", r.toHex()
    echo "Evaluated in ", float64(inMicroseconds(stop-start)) / float64 iters, " µs"

  checkApprox()
  checkLinComb()