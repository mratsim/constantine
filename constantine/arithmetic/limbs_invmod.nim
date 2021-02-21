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
  ./limbs

# No exceptions allowed
{.push raises: [].}

# ############################################################
#
#                  Modular division by 2^N
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
  ## Compute 1/M mod 2^N
  ## from -1/M[0] (mod 2^WordBitWidth)
  # Algorithm: Cetin Kaya Koc (2017) p11, https://eprint.iacr.org/2017/411
  # Once you have a modular inverse (mod 2^s) you can reduce
  # (mod 2^k) to have the modular inverse (mod 2^k)
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
  #     (m * p) mod 2^N = x mod 2^N
  # <=> m mod 2^N = (x / p) mod 2^N
  # <=> m mod 2^N = (x * invpmod2n) mod 2^N
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

# DEBUG
import ../config/type_bigint

type
  TransitionMatrix = object
    f0, g0: uint64
    f1, g1: uint64

func shl2L_hi(w_hi, w_lo, k: SecretWord): SecretWord =
  ## Returns the hi word after
  ## shifting left of a double-precision word by k
  ## Assumes k <= WordBitWidth
  debug:
    doAssert(k.int <= WordBitWidth)
  SecretWord((w_hi.BaseType shl k.BaseType) or (w_lo.BaseType shr (WordBitWidth - k.BaseType)))

# {.push checks: off.}
func extractMSW[N: static int](uh, vh: var SecretWord, u, v: Limbs[N], w: int) =
  ## Extract the joint Most Significant Word from v & v
  ## The MSW will be looked for starting from `w` word
  # This is Algorithm 2, line 2 to 5
  # n ← max(len(a),len(b),2k)
  # ā ← (a mod 2^(k−1)) + 2^(k−1) * floor(a/2^(n−k−1))
  # ƀ ← (b mod 2^(k−1)) + 2^(k−1) * floor(b/2^(n−k−1))
  #
  # We extract the second part a/2^(n−k−1) and b/2^(n−k−1)

  debug:
    doAssert w >= 1

  var mswFound = CtFalse
  var clz: SecretWord

  for i in countdown(w-1, 1, 1):
    let uvi = u[i] or v[i]
    let isMsw = not(mswFound) and uvi.isNonZero()
    let clzi = SecretWord countLeadingZeros(uvi.BaseType)
    isMsw.ccopy(clz, clzi)
    isMsw.ccopy(uh, shl2L_hi(u[i], u[i-1], clzi))
    isMsw.ccopy(vh, shl2L_hi(v[i], v[i-1], clzi))
    mswFound = mswFound or isMsw

  # If all words were zeros so far
  mswFound = not(mswFound)
  ccopy(mswFound, uh, u[0])
  ccopy(mswFound, vh, v[0])
# {.pop.}

func divSteps62[N: static int](
       u, v: Limbs[N],
       t: var TransitionMatrix
     ) =
  discard

  # Planned implementation outline
  #
  # constant-time:
  # - Pornin's paper groups f0 g0 in rax and f1 g1 in rcx.
  #   for the inner fast loop.
  #   This forces the loop to use i31 values.
  #   Instead we can use SSE2 SIMD (supported on all x86-64 CPUs and since 2000)
  #   to store f0 g0 and f1 g1 in the SIMD registers.
  #   On ARM, we can use NEON and this can be done in a portable way
  #   using GCC vector instructions.
  #   - This allows to keep using 62 inner iterations and avoid the bitshift manipulation.
  #   - This would significantly reduce register pressure
  #
  # vartime:
  # - We can process by batch of zeros with "countTrailingZeros"
  #   a zero just requires a doubling so we CTZ and shift by as many zeros found.

# Sanity Checks
# ------------------------------------------------------------

when isMainModule:
  import ../config/type_bigint

  type SW = SecretWord

  proc checkMSW_1() =
    var a = [SW 0x00000000_00000001'u64, SW 0x00000000_00010000'u64, SW 0x00001000_00000000'u64, SW 0x10000000_00000000'u64]
    var b = [SW 0x00000000_00000001'u64, SW 0x00000000_00001000'u64, SW 0x00000100_00000000'u64, SW 0x01000000_00000000'u64]

    var u, v: array[1, SW]
    extractMSW(u[0], v[0], a, b, 4)

    echo "u: ", u.toString()
    echo "v: ", v.toString()

  checkMSW_1()
