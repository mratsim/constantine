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

# #################################################################

func `not`*(ctl: HardBool): HardBool {.inline.}=
  ## Negate a constant-time boolean
  result = ctl xor 1

func `-`*(x: HardBase): HardBase {.inline.}=
  ## Unary minus returns the two-complement representation
  ## of an unsigned integer
  {.emit:"`result` = -`x`;".}

func mux*[T: HardBase](ctl: HardBool[T], x, y: T): T {.inline.}=
  ## Multiplexer / selector
  ## Returns x if ctl == 1
  ## else returns y
  result = y xor (-ctl.T and (x xor y))

func `!=`*[T: HardBase](x, y: T): HardBool[T] {.inline.}=
  const msb = T.sizeof * 8 - 1
  let z = x xor y
  result = (type result)((z or -z) shr msb)

func `==`*[T: HardBase](x, y: T): HardBool[T] {.inline.}=
  result = not(x != y)

func `<`*[T: HardBase](x, y: T): HardBool[T] {.inline.}=
  const msb = T.sizeof * 8 - 1
  result = (type result)(
    (
      x xor (
        (x xor y) or ((x - y) xor y)
      )
    ) shr msb
  )

func `<=`*[T: HardBase](x, y: T): HardBool[T] {.inline.}=
  (y < x) xor 1
