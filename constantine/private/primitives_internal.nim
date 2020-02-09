# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#  Unsafe constant-time primitives with specific restrictions
#
# ############################################################

import ../primitives

func asm_x86_64_extMul(hi, lo: var uint64, a, b: uint64) {.inline.}=
  ## Extended precision multiplication uint64 * uint64 --> uint128

  # TODO !!! - Replace by constant-time, portable, non-assembly version
  #          -> use uint128? Compiler might add unwanted branches

  # MUL r/m64
  # Multiply RAX by r/m64
  #
  # Inputs:
  #   - RAX
  #   - r/m
  # Outputs:
  #   - High word in RDX
  #   - Low word in RAX

  # Don't forget to dereference the var hidden pointer in hi/lo
  asm """
    mulq %[operand]
    : "=d" (`*hi`), "=a" (`*lo`)
    : "a" (`a`), [operand] "rm" (`b`)
    :
  """

func unsafeExtendedPrecMul*(hi, lo: var Ct[uint64], a, b: Ct[uint64]) {.inline.}=
  ## Extended precision multiplication uint64 * uint64 --> uint128
  ##
  ## TODO, at the moment only x86_64 architecture are supported
  ##       as we use assembly.
  ##       Also we assume that the native integer division
  ##       provided by the PU is constant-time

  # Note, using C/Nim default `*` is inefficient
  # and complicated to make constant-time
  # See at the bottom.

  type T = uint64

  when not defined(amd64):
    {.error: "At the moment only x86_64 architecture is supported".}
  else:
    asm_x86_64_extMul(T(hi), T(lo), T(a), T(b))

func unsafeExtendedPrecMul*(hi, lo: var Ct[uint32], a, b: Ct[uint32]) {.inline.}=
  ## Extended precision multiplication uint32 * uint32 --> uint32
  let extMul = uint64(a) * uint64(b)
  hi = (Ct[uint32])(extMul shr 32)
  lo = (Ct[uint32])(extMul and 31)

func asm_x86_64_div2n1n(q, r: var uint64, n_hi, n_lo, d: uint64) {.inline.}=
  ## Division uint128 by uint64
  ## Warning ⚠️ :
  ##   - if n_hi == d, quotient does not fit in an uint64
  ##   - if n_hi > d result is undefined

  # TODO !!! - Replace by constant-time, portable, non-assembly version
  #          -> use uint128? Compiler might add unwanted branches

  # DIV r/m64
  # Divide RDX:RAX (n_hi:n_lo) by r/m64
  #
  # Inputs
  #   - numerator high word in RDX,
  #   - numerator low word in RAX,
  #   - divisor as r/m parameter (register or memory at the compiler discretion)
  # Result
  #   - Quotient in RAX
  #   - Remainder in RDX

  # 1. name the register/memory "divisor"
  # 2. don't forget to dereference the var hidden pointer
  # 3. -
  # 4. no clobbered registers beside explectly used RAX and RDX
  asm """
    divq %[divisor]
    : "=a" (`*q`), "=d" (`*r`)
    : "d" (`n_hi`), "a" (`n_lo`), [divisor] "rm" (`d`)
    :
  """

func unsafeDiv2n1n*(q, r: var Ct[uint64], n_hi, n_lo, d: Ct[uint64]) {.inline.}=
  ## Division uint128 by uint64
  ## Warning ⚠️ :
  ##   - if n_hi == d, quotient does not fit in an uint64
  ##   - if n_hi > d result is undefined
  ##
  ## To avoid issues, n_hi, n_lo, d should be normalized.
  ## i.e. shifted (== multiplied by the same power of 2)
  ## so that the most significant bit in d is set.
  ##
  ## TODO, at the moment only x86_64 architecture are supported
  ##       as we use assembly.
  ##       Also we assume that the native integer division
  ##       provided by the PU is constant-time

  # Note, using C/Nim default `div` is inefficient
  # and complicated to make constant-time
  # See at the bottom.
  #
  # Furthermore compilers may try to substitute division
  # with a fast path that may have branches. It might also
  # be the same at the hardware level.

  type T = uint64

  when not defined(amd64):
    {.error: "At the moment only x86_64 architecture is supported".}
  else:
    asm_x86_64_div2n1n(T(q), T(r), T(n_hi), T(n_lo), T(d))

func unsafeDiv2n1n*(q, r: var Ct[uint32], n_hi, n_lo, d: Ct[uint32]) {.inline.}=
  ## Division uint64 by uint32
  ## Warning ⚠️ :
  ##   - if n_hi == d, quotient does not fit in an uint32
  ##   - if n_hi > d result is undefined
  ##
  ## To avoid issues, n_hi, n_lo, d should be normalized.
  ## i.e. shifted (== multiplied by the same power of 2)
  ## so that the most significant bit in d is set.
  let dividend = (uint64(n_hi) shl 32) or uint64(n_lo)
  let divisor = uint64(d)
  q = (Ct[uint32])(dividend div divisor)
  r = (Ct[uint32])(dividend mod divisor)

when isMainModule:
  block: # Multiplication
    var hi, lo: uint64

    asm_x86_64_extMul(hi, lo, 1 shl 32, 1 shl 33) # 2^65
    doAssert hi == 2
    doAssert lo == 0

  block: # Division
    var q, r: uint64

    # (1 shl 64) div 3
    let n_hi = 1'u64
    let n_lo = 0'u64
    let d = 3'u64

    asm_x86_64_div2n1n(q, r, n_hi, n_lo, d)

    doAssert q == 6148914691236517205'u64
    doAssert r == 1

  block: # TODO - support Quotient that doesn't fit in the result
         # The usual way with normalization by the bitSize difference
         # is fundamentally non constant-time
         # it is probable that division is not constant-time at the hardware level as well
         # as it throws sigfpe when the quotient doesn't fit in the result size

    var q, r: uint64

    let n_hi = 1'u64
    let n_lo = 0'u64
    let d = 1'u64

    asm_x86_64_div2n1n(q, r, n_hi, n_lo, d)

    echo "quotient: ", q
    echo "remainder: ", r

  block:
    var q, r: uint64

    let n_hi = 4186590388502004879'u64
    let n_lo = 17852795547484522084'u64
    let d = 327340459940166448'u64

    asm_x86_64_div2n1n(q, r, n_hi, n_lo, d)

    echo "quotient: ", q
    echo "remainder: ", r

# ##############################################################
#
#  Non-constant-time portable extended precision multiplication
#
# ##############################################################

# implementation from Stint: https://github.com/status-im/nim-stint/blob/edb1ade37309390cc641cee07ab62e5459d9ca44/stint/private/uint_mul.nim#L91-L135

# template extPrecMulImpl(result: var UintImpl[uint64], op: untyped, u, v: uint64) =
#   const
#     p = 64 div 2
#     base: uint64 = 1 shl p
#
#   var
#     x0, x1, x2, x3: uint64
#
#   let
#     ul = lo(u)
#     uh = hi(u)
#     vl = lo(v)
#     vh = hi(v)
#
#   x0 = ul * vl
#   x1 = ul * vh
#   x2 = uh * vl
#   x3 = uh * vh
#
#   x1 += hi(x0)          # This can't carry
#   x1 += x2              # but this can
#   if x1 < x2:           # if carry, add it to x3
#     x3 += base
#
#   op(result.hi, x3 + hi(x1))
#   op(result.lo, (x1 shl p) or lo(x0))
#
# func extPrecMul*(result: var UintImpl[uint64], u, v: uint64) =
#   ## Extended precision multiplication
#   extPrecMulImpl(result, `=`, u, v)
#
# func extPrecAddMul(result: var UintImpl[uint64], u, v: uint64) =
#   ## Extended precision fused in-place addition & multiplication
#   extPrecMulImpl(result, `+=`, u, v)

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
