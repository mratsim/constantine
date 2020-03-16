# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#               Extended precision primitives
#
# ############################################################

import ./constant_time_types

# ############################################################
#
#                     32-bit words
#
# ############################################################

func unsafeDiv2n1n*(q, r: var Ct[uint32], n_hi, n_lo, d: Ct[uint32]) {.inline.}=
  ## Division uint64 by uint32
  ## Warning ⚠️ :
  ##   - if n_hi == d, quotient does not fit in an uint32
  ##   - if n_hi > d result is undefined
  ##
  ## To avoid issues, n_hi, n_lo, d should be normalized.
  ## i.e. shifted (== multiplied by the same power of 2)
  ## so that the most significant bit in d is set.
  # TODO !!! - Replace by constant-time, portable, non-assembly version
  #          -> use uint128? Compiler might add unwanted branches
  {.warning: "unsafeDiv2n1n is not constant-time at the moment on most hardware".}
  let dividend = (uint64(n_hi) shl 32) or uint64(n_lo)
  let divisor = uint64(d)
  q = (Ct[uint32])(dividend div divisor)
  r = (Ct[uint32])(dividend mod divisor)

func muladd1*(hi, lo: var Ct[uint32], a, b, c: Ct[uint32]) {.inline.} =
  ## Extended precision multiplication + addition
  ## (hi, lo) <- a*b + c
  ##
  ## Note: 0xFFFFFFFF² -> (hi: 0xFFFFFFFE, lo: 0x00000001)
  ##       so adding any c cannot overflow
  ##
  ## This is constant-time on most hardware
  ## See: https://www.bearssl.org/ctmul.html
  let dblPrec = uint64(a) * uint64(b) + uint64(c)
  lo = (Ct[uint32])(dblPrec)
  hi = (Ct[uint32])(dblPrec shr 32)

func muladd2*(hi, lo: var Ct[uint32], a, b, c1, c2: Ct[uint32]) {.inline.}=
  ## Extended precision multiplication + addition + addition
  ## This is constant-time on most hardware except some specific one like Cortex M0
  ## (hi, lo) <- a*b + c1 + c2
  ##
  ## Note: 0xFFFFFFFF² -> (hi: 0xFFFFFFFE, lo: 0x00000001)
  ##       so adding 0xFFFFFFFF leads to (hi: 0xFFFFFFFF, lo: 0x00000000)
  ##       and we have enough space to add again 0xFFFFFFFF without overflowing
  let dblPrec = uint64(a) * uint64(b) + uint64(c1) + uint64(c2)
  lo = (Ct[uint32])(dblPrec)
  hi = (Ct[uint32])(dblPrec shr 32)

# ############################################################
#
#                     64-bit words
#
# ############################################################

when sizeof(int) == 8:
  when defined(vcc):
    from ./extended_precision_x86_64_msvc import unsafeDiv2n1n, muladd1, muladd2
  elif GCCCompatible:
    # TODO: constant-time div2n1n
    when X86:
      from ./extended_precision_x86_64_gcc import unsafeDiv2n1n
      from ./extended_precision_64bit_uint128 import muladd1, muladd2
    else:
      from ./extended_precision_64bit_uint128 import unsafeDiv2n1n, muladd1, muladd2

  export unsafeDiv2n1n, muladd1, muladd2
