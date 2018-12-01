# Hardy
# Copyright (c) 2018 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./datatypes

# #########################
#
# Constant-time primitives
#
# #########################

# The main challenge is to prevent conditional branch/jump
# in the generated assembly.
#
# Note:
#   let x = if true: 1 else: 2
#
# does not guarantee a constant-time conditional move
# The compiler might introduce branching.

# These primitives are distinct type and internal to Hardy.
# We don't want to pollute unsuspecting users
# with `not` and `-` on unsigned ints

# #################################################################
# Hard base borrows
# We should use {.borrow.} instead of {.magic.} but pending:
#    - https://github.com/nim-lang/Nim/pull/8531
#    - https://github.com/nim-lang/Nim/issues/4121 (can be workaround with #8531)

func high*(T: typedesc[HardBase]): T {.inline.}=
  not T(0)

func `and`*[T: HardBase](x, y: T): T {.magic: "BitandI".}
func `or`*[T: HardBase](x, y: T): T {.magic: "BitorI".}
func `xor`*[T: HardBase](x, y: T): T {.magic: "BitxorI".}
func `not`*[T: HardBase](x: T): T {.magic: "BitnotI".}
func `+`*[T: HardBase](x, y: T): T {.magic: "AddU".}
func `-`*[T: HardBase](x, y: T): T {.magic: "SubU".}
func `shr`*[T: HardBase](x: T, y: SomeInteger): T {.magic: "ShrI".}
func `shl`*[T: HardBase](x: T, y: SomeInteger): T {.magic: "ShlI".}

func `*`*[T: HardBase](x, y: T): T {.magic: "MulU".}
# Warning ⚠️ : We assume that mul hardware multiplication is constant time
# but this is not always true, especially on ARMv7 and ARMv9

# We don't implement div/mod as we can't assume the hardware implementation
# is constant-time

func `-`*(x: HardBase): HardBase {.inline.}=
  ## Unary minus returns the two-complement representation
  ## of an unsigned integer
  {.emit:"`result` = -`x`;".}

# ############################################################
#
#                           Bit hacks
#
# ############################################################

func isMsbSet*[T: HardBase](x: T): HardBool[T] {.inline.} =
  ## Returns the most significant bit of an integer
  const msb_pos = T.sizeof * 8 - 1
  result = (HardBool[T])(x shr msb_pos)

# ############################################################
#
#             Hardened Boolean primitives
#
# ############################################################

func `not`*(ctl: HardBool): HardBool {.inline.}=
  ## Negate a constant-time boolean
  ctl xor 1

func select*[T: HardBase](ctl: HardBool[T], x, y: T): T {.inline.}=
  ## Multiplexer / selector
  ## Returns x if ctl == 1
  ## else returns y
  ## So equivalent to ctl? x: y
  # TODO verify assembly generated
  # as mentionned in https://cryptocoding.net/index.php/Coding_rules
  # the alternative `(x and ctl) or (y and -m)`
  # is optimized into a branch by Clang :/
  y xor (-ctl.T and (x xor y))

func noteq[T: HardBase](x, y: T): HardBool[T] {.inline.}=
  const msb = T.sizeof * 8 - 1
  let z = x xor y
  result = (type result)((z or -z) shr msb)

func `==`*[T: HardBase](x, y: T): HardBool[T] {.inline.}=
  not(noteq(x, y))

func `<`*[T: HardBase](x, y: T): HardBool[T] {.inline.}=
  result = isMsbSet(
      x xor (
        (x xor y) or ((x - y) xor y)
      )
    )

func `<=`*[T: HardBase](x, y: T): HardBool[T] {.inline.}=
  (y < x) xor 1

# ############################################################
#
#         Workaround system.nim `!=` template
#
# ############################################################

# system.nim defines `!=` as a catchall template
# in terms of `==` while we define `==` in terms of `!=`
# So we would have not(not(noteq(x,y)))

template trmFixSystemNotEq*{x != y}[T: HardBase](x, y: T): HardBool[T] =
  noteq(x, y)

# ############################################################
#
#             Optimized hardened zero comparison
#
# ############################################################

func isNonZero*[T: HardBase](x: T): HardBool[T] {.inline.} =
  isMsbSet(x or -x)

func isZero*[T: HardBase](x: T): HardBool[T] {.inline.} =
  not x.isNonZero

# ############################################################
#
#             Transform x == 0 and x != 0
#             into their optimized version
#
# ############################################################

template trmIsZero*{x == 0}[T: HardBase](x: T): HardBool[T] = x.isZero
template trmIsZero*{0 == x}[T: HardBase](x: T): HardBool[T] = x.isZero
template trmIsNonZero*{x != 0}[T: HardBase](x: T): HardBool[T] = x.isNonZero
template trmIsNonZero*{0 != x}[T: HardBase](x: T): HardBool[T] = x.isNonZero
