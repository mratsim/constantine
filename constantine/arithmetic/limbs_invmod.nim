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
#                  Modular division by 2
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

# ############################################################
#
#                    Modular inversion
#
# ############################################################

# Generic (odd-only modulus)
# ------------------------------------------------------------
# Algorithm by Niels Möller,
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

func steinsGCD*(v: var Limbs, a: Limbs, F, M: Limbs, bits: int, mp1div2: Limbs) =
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
