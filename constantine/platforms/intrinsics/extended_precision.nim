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

import
  ../config,
  ./addcarry_subborrow,
  ../constant_time/ct_types,
  ../constant_time/ct_routines

# ############################################################
#
#                     32-bit words
#
# ############################################################

func mul*(hi, lo: var Ct[uint32], a, b: Ct[uint32]) {.inline.} =
  ## Extended precision multiplication
  ## (hi, lo) <- a*b
  ##
  ## This is constant-time on most hardware
  ## See: https://www.bearssl.org/ctmul.html
  let dblPrec = uint64(a) * uint64(b)
  lo = (Ct[uint32])(dblPrec)
  hi = (Ct[uint32])(dblPrec shr 32)

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

func smul*(hi, lo: var Ct[uint32], a, b: Ct[uint32]) {.inline.} =
  ## Signed extended precision multiplication
  ## (hi, lo) <- a*b
  ##
  ## Inputs are intentionally unsigned
  ## as we use their unchecked raw representation for cryptography
  ##
  ## This is constant-time on most hardware
  ## See: https://www.bearssl.org/ctmul.html
  let dblPrec = int64(cast[int32](a)) * int64(cast[int32](b)) # Sign-extension via cast+conversion to wider int
  lo = cast[Ct[uint32]](dblPrec)
  hi = cast[Ct[uint32]](dblPrec shr 32)

# ############################################################
#
#                     64-bit words
#
# ############################################################

when sizeof(int) == 8:
  when defined(vcc):
    from ./extended_precision_x86_64_msvc import mul, muladd1, muladd2, smul
  elif GCCCompatible:
    when X86:
      from ./extended_precision_64bit_uint128 import mul, muladd1, muladd2, smul
    else:
      from ./extended_precision_64bit_uint128 import mul, muladd1, muladd2, smul
  export mul, muladd1, muladd2, smul

# ############################################################
#
#                  Composite primitives
#
# ############################################################

func mulAcc*[T: Ct[uint32]|Ct[uint64]](t, u, v: var T, a, b: T) {.inline.} =
  ## (t, u, v) <- (t, u, v) + a * b
  var UV: array[2, T]
  var carry: Carry
  mul(UV[1], UV[0], a, b)
  addC(carry, v, v, UV[0], Carry(0))
  addC(carry, u, u, UV[1], carry)
  t += T(carry)

func mulDoubleAcc*[T: Ct[uint32]|Ct[uint64]](t, u, v: var T, a, b: T) {.inline.} =
  ## (t, u, v) <- (t, u, v) + 2 * a * b
  var UV: array[2, T]
  var carry: Carry
  mul(UV[1], UV[0], a, b)

  addC(carry, UV[0], UV[0], UV[0], Carry(0))
  addC(carry, UV[1], UV[1], UV[1], carry)
  t += T(carry)

  addC(carry, v, v, UV[0], Carry(0))
  addC(carry, u, u, UV[1], carry)
  t += T(carry)
