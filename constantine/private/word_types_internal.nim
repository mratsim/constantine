# Constantine
# Copyright (c) 2018 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#  Unsafe constant-time primitives with specific restrictions
#
# ############################################################

import ../word_types

func asm_x86_64_div2n1n(q, r: var uint64, n_hi, n_lo, d: uint64) {.inline.}=
  ## Division uint128 by uint64
  ## Warning ⚠️ :
  ##   - if n_hi == d, quotient does not fit in an uint64
  ##   - if n_hi > d result is undefined

  # TODO !!! - Replace by constant-time, portable, non-assembly version

  # DIV r/m64
  # Divide RDX:RAX (n_hi:n_lo) by r/m64
  #
  # Inputs
  #   - numerator high word in RDX,
  #   - numerator low word in RAX,
  #   - divisor as rm parameter (register or memory at the compiler discretion)
  # Result
  #   - Quotient in RAX
  #   - Remainder in RDX
  asm """
    divq %[divisor]             // We name the register/memory divisor
    : "=a" (`*q`), "=d" (`*r`)  // Don't forget to dereference the var hidden pointer
    : "d" (`n_hi`), "a" (`n_lo`), [divisor] "rm" (`d`)
    :  // no register clobbered besides explicitly used RAX and RDX
  """

func unsafe_div2n1n*(q, r: var Ct[uint64], n_hi, n_lo, d: Ct[uint64]) {.inline.}=
  ## Division uint128 by uint64
  ## Warning ⚠️ :
  ##   - if n_hi == d, quotient does not fit in an uint64
  ##   - if n_hi > d result is undefined
  ##
  ## TODO, at the moment only x86_64 architecture are supported
  ##       as we use assembly.
  ##       Also we assume that the native integer division
  ##       provided by the PU is constant-time

  # Note, using C/Nim default `div` is inefficient
  # and complicated to make constant-time
  # See at the bottom.
  #
  # Furthermore compilers try to substitute division
  # with a fast path that may have branches. It might also
  # be the same at the hardware level.

  type T = uint64

  when not defined(amd64):
    {.error: "At the moment only x86_64 architecture is supported".}
  else:
    asm_x86_64_div2n1n(T(q), T(r), T(n_hi), T(n_lo), T(d))

when isMainModule:

  var q, r: uint64

  # (1 shl 64) div 3
  let n_hi = 1'u64
  let n_lo = 0'u64
  let d = 3'u64

  asm_x86_64_div2n1n(q, r, n_hi, n_lo, d)

  doAssert q == 6148914691236517205'u64
  doAssert r == 1

# ############################################################
#
#             Non-constant-time portable div2n1n
#
# ############################################################

# implementation from Stint: https://github.com/status-im/nim-stint/blob/edb1ade37309390cc641cee07ab62e5459d9ca44/stint/private/uint_div.nim#L131

# func div2n1n[T: SomeunsignedInt](q, r: var T, n_hi, n_lo, d: T) =
#
#   # assert countLeadingZeroBits(d) == 0, "Divisor was not normalized"
#
#   const
#     size = bitsof(q)
#     halfSize = size div 2
#     halfMask = (1.T shl halfSize) - 1.T
#
#   template halfQR(n_hi, n_lo, d, d_hi, d_lo: T): tuple[q,r: T] =
#
#     var (q, r) = divmod(n_hi, d_hi)
#     let m = q * d_lo
#     var r = (r shl halfSize) or n_lo
#
#     # Fix the reminder, we're at most 2 iterations off
#     if r < m:
#       dec q
#       r += d
#       if r >= d and r < m:
#         dec q
#         r += d
#     r -= m
#     (q, r)
#
#   let
#     d_hi = d shr halfSize
#     d_lo = d and halfMask
#     n_lohi = nlo shr halfSize
#     n_lolo = nlo and halfMask
#
#   # First half of the quotient
#   let (q1, r1) = halfQR(n_hi, n_lohi, d, d_hi, d_lo)
#
#   # Second half
#   let (q2, r2) = halfQR(r1, n_lolo, d, d_hi, d_lo)
#
#   q = (q1 shl halfSize) or q2
#   r = r2
