# Hardy
# Copyright (c) 2018 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./datatypes

# ################################
#
# Constant-time boolean primitives
#
# ################################

# The main challenge is to prevent conditional branch/jump
# in the generated assembly.
#
# Note:
#   let x = if true: 1 else: 2
#
# does not guarantee a constant-time conditional move
# The compiler might introduce branching.

# These primitives are internal to Hardy.
# We don't want to pollute unsuspecting users
# with `not` and `-` on unsigned ints

func high*(T: typedesc[HardBase]): T {.inline.}=
  result = not T(0)

func `not`*[T: HardBase](ctl: HardBool[T]): HardBool[T] {.inline.}=
  ## Negate a constant-time boolean
  result = ctl xor 1.T

func `-`*(x: HardBase): HardBase {.inline.}=
  ## Unary minus returns the two-complement representation
  ## of an unsigned integer
  const max = high(type x)
  result = (max xor x) + 1

func mux*[T: HardBase](ctl: HardBool[T], x, y: T): T {.inline.}=
  ## Returns x if ctl == 1
  ## else returns y
  result = y xor (-ctl.HardBase and (x xor y))
