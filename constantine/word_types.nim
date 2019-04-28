# Constantine
# Copyright (c) 2018 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

type
  BaseUint* = SomeUnsignedInt or byte

  Ct*[T: BaseUint] = distinct T

  CTBool*[T: Ct] = distinct range[T(0)..T(1)]
    ## To avoid the compiler replacing bitwise boolean operations
    ## by conditional branches, we don't use booleans.
    ## We use an int to prevent compiler "optimization" and introduction of branches

func ctrue*(T: typedesc[BaseUint]): auto {.inline.}=
  (CTBool[Ct[T]])(true)

func cfalse*(T: typedesc[BaseUint]): auto {.inline.}=
  (CTBool[Ct[T]])(false)

func ct*[T: BaseUint](x: T): Ct[T] {.inline.}=
  (Ct[T])(x)

func `$`*[T](x: Ct[T]): string {.inline.} =
  $T(x)

func `$`*(x: CTBool): string {.inline.} =
  $bool(x)

# ############################################################
#
#                 Constant-time primitives
#
# ############################################################

# The main challenge is to prevent conditional branch/jump
# in the generated assembly.
#
# Note:
#   let x = if true: 1 else: 2
#
# does not guarantee a constant-time conditional move
# The compiler might introduce branching.

# These primitives are distinct type and internal to Constantine.
# We don't want to pollute unsuspecting users
# with `not` and `-` on unsigned ints

# #################################################################
# Hard base borrows
# We should use {.borrow.} instead of {.magic.} but pending:
#    - https://github.com/nim-lang/Nim/pull/8531
#    - https://github.com/nim-lang/Nim/issues/4121 (can be workaround with #8531)

func high*(T: typedesc[Ct]): T {.inline.}=
  not T(0)

func `and`*[T: Ct](x, y: T): T {.magic: "BitandI".}
func `or`*[T: Ct](x, y: T): T {.magic: "BitorI".}
func `xor`*[T: Ct](x, y: T): T {.magic: "BitxorI".}
func `not`*[T: Ct](x: T): T {.magic: "BitnotI".}
func `+`*[T: Ct](x, y: T): T {.magic: "AddU".}
func `+=`*[T: Ct](x: var T, y: T): T {.magic: "Inc".}
func `-`*[T: Ct](x, y: T): T {.magic: "SubU".}
func `-=`*[T: Ct](x: var T, y: T): T {.magic: "Dec".}
func `shr`*[T: Ct](x: T, y: SomeInteger): T {.magic: "ShrI".}
func `shl`*[T: Ct](x: T, y: SomeInteger): T {.magic: "ShlI".}

func `*`*[T: Ct](x, y: T): T {.magic: "MulU".}
# Warning ⚠️ : We assume that mul hardware multiplication is constant time
# but this is not always true, especially on ARMv7 and ARMv9

# We don't implement div/mod as we can't assume the hardware implementation
# is constant-time

func `-`*(x: Ct): Ct {.inline.}=
  ## Unary minus returns the two-complement representation
  ## of an unsigned integer
  {.emit:"`result` = -`x`;".}

# ############################################################
#
#                           Bit hacks
#
# ############################################################

func isMsbSet*[T: Ct](x: T): CTBool[T] {.inline.} =
  ## Returns the most significant bit of an integer
  const msb_pos = T.sizeof * 8 - 1
  result = (CTBool[T])(x shr msb_pos)

# ############################################################
#
#             Hardened Boolean primitives
#
# ############################################################

template undistinct[T: Ct](x: CTBool[T]): T =
  T(x)

func `not`*(ctl: CTBool): CTBool {.inline.}=
  ## Negate a constant-time boolean
  (type result)(ctl.undistinct xor (type ctl.undistinct)(1))

func `and`*(x, y: CTBool): CTBool {.magic: "BitandI".}
func `or`*(x, y: CTBool): CTBool {.magic: "BitorI".}

template mux*[T: Ct](ctl: CTBool[T], x, y: T): T =
  ## Multiplexer / selector
  ## Returns x if ctl == 1
  ## else returns y
  ## So equivalent to ctl? x: y
  y xor (-T(ctl) and (x xor y))

  # TODO verify assembly generated
  # as mentionned in https://cryptocoding.net/index.php/Coding_rules
  # the alternative `(x and ctl) or (y and -ctl)`
  # is optimized into a branch by Clang :/

func noteq[T: Ct](x, y: T): CTBool[T] {.inline.}=
  const msb = T.sizeof * 8 - 1
  let z = x xor y
  result = (type result)((z or -z) shr msb)

func `==`*[T: Ct](x, y: T): CTBool[T] {.inline.}=
  not(noteq(x, y))

func `<`*[T: Ct](x, y: T): CTBool[T] {.inline.}=
  result = isMsbSet(
      x xor (
        (x xor y) or ((x - y) xor y)
      )
    )

func `<=`*[T: Ct](x, y: T): CTBool[T] {.inline.}=
  not(y < x)

# ############################################################
#
#         Workaround system.nim `!=` template
#
# ############################################################

# system.nim defines `!=` as a catchall template
# in terms of `==` while we define `==` in terms of `!=`
# So we would have not(not(noteq(x,y)))

template trmFixSystemNotEq*{x != y}[T: Ct](x, y: T): CTBool[T] =
  noteq(x, y)

# ############################################################
#
#             Optimized hardened zero comparison
#
# ############################################################

func isNonZero*[T: Ct](x: T): CTBool[T] {.inline.} =
  isMsbSet(x or -x)

func isZero*[T: Ct](x: T): CTBool[T] {.inline.} =
  not x.isNonZero

# ############################################################
#
#             Transform x == 0 and x != 0
#             into their optimized version
#
# ############################################################

template trmIsZero*{x == 0}[T: Ct](x: T): CTBool[T] = x.isZero
template trmIsZero*{0 == x}[T: Ct](x: T): CTBool[T] = x.isZero
template trmIsNonZero*{x != 0}[T: Ct](x: T): CTBool[T] = x.isNonZero
template trmIsNonZero*{0 != x}[T: Ct](x: T): CTBool[T] = x.isNonZero
