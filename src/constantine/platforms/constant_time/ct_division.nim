# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./ct_types, ./ct_routines, ./multiplexers

func div2n1n*[T: Ct](q, r: var T, n_hi, n_lo, d: T) =
  ## Division uint128 by uint64 or uint64 by uint32
  ## Warning ⚠️ :
  ##   - if n_hi == d, quotient does not fit in an uint32
  ##   - if n_hi > d result is undefined
  ## 
  ## To avoid issues, n_hi, n_lo, d should be normalized.
  ## i.e. shifted (== multiplied by the same power of 2)
  ## so that the most significant bit in d is set.
  # See
  #   https://www.bearssl.org/bigint.html
  #   br_divrem
  const bits = sizeof(T)*8

  q = T(0)
  var hi = mux(n_hi == d, T(0), n_hi)
  var lo = n_lo

  for k in countdown(bits-1, 1):
    let j = bits-k
    let w = (hi shl j) or (lo shr k)
    let ctl = (w >= d) or CTBool[T](hi shr k)
    let hi2 = (w-d) shr j
    let lo2 = lo - (d shl k)
    hi = ctl.mux(hi2, hi)
    lo = ctl.mux(lo2, lo)
    q = q or (T(ctl) shl k)

  let carry = (lo >= d) or hi.isNonZero()
  q = q or T(carry)
  r = carry.mux(lo - d, lo)


# Performance:
# If division ever becomes a bottleneck, we can avoid binary-shift
# by first computing a single-word reciprocal (mod 2⁶⁴)
# Then using multiplication for each quotient/remainder
# See algorithm 2 (reciprocal) and 4 in https://gmplib.org/~tege/division-paper.pdf
#
# Algorithm 2
#   can be made constant-time via Newton-Raphson iterations
#   or use binary shift division with
#
#   v ← [2⁶⁴-1-d, 2⁶⁴-1]/d
#
# or (for assembly)
#
#   v ← not(d << 64)/d
#
# (d normalized)
#
# Algorithm 4
#   can be made constant-time via conditional moves.
#
#   (q, r) ← DIV2BY1(〈u1, u0〉, d, v)
#      In: β/2 ≤ d < β, u1 < d, v = ⌊(β2 − 1)/d⌋ − β
#  
#   1   〈q1, q0〉 ← vu1                    // umul
#   2   〈q1, q0〉 ← 〈q1, q0〉 + 〈u1, u0〉
#   3    q1 ← (q1 + 1) mod β
#   4    r ← (u0 − q1d) mod β              // umullo
#   5    if r > q0                         // Unpredictable condition
#   6        q1 ← (q1 − 1) mod β
#   7        r ← (r + d) mod β
#   8    if r ≥ d                          // Unlikely condition
#   9        q1 ← q1 + 1
#   10       r ← r − d
#   11   return q1, r