# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                Constant-time primitives
#
# ############################################################

type
  BaseUint* = SomeUnsignedInt or byte

  Ct*[T: BaseUint] = distinct T

  CTBool*[T: Ct] = distinct range[T(0)..T(1)]
    ## To avoid the compiler replacing bitwise boolean operations
    ## by conditional branches, we don't use booleans.
    ## We use an int to prevent compiler "optimization" and introduction of branches

# No exceptions allowed
{.push raises: [].}
# Word primitives are inlined
{.push inline.}

func ctrue*(T: typedesc[Ct or BaseUint]): auto =
  when T is Ct:
    (CTBool[T])(true)
  else:
    (CTBool[Ct[T]])(true)

func cfalse*(T: typedesc[Ct or BaseUint]): auto =
  when T is Ct:
    (CTBool[T])(false)
  else:
    (CTBool[Ct[T]])(false)

func ct*[T: BaseUint](x: T): Ct[T] =
  (Ct[T])(x)

func `$`*[T](x: Ct[T]): string =
  $T(x)

func `$`*(x: CTBool): string =
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

func high*(T: typedesc[Ct]): T =
  not T(0)

func `and`*[T: Ct](x, y: T): T {.magic: "BitandI".}
func `or`*[T: Ct](x, y: T): T {.magic: "BitorI".}
func `xor`*[T: Ct](x, y: T): T {.magic: "BitxorI".}
# func `not`*[T: Ct](x: T): T {.magic: "BitnotI".} # int128 changes broke the magic
template `not`*[T: Ct](x: T): T =
  # Note: T.T is Ct.T is the conversion to the base type
  T(not T.T(x))

func `+`*[T: Ct](x, y: T): T {.magic: "AddU".}
func `+=`*[T: Ct](x: var T, y: T) {.magic: "Inc".}
func `-`*[T: Ct](x, y: T): T {.magic: "SubU".}
func `-=`*[T: Ct](x: var T, y: T) {.magic: "Dec".}
func `shr`*[T: Ct](x: T, y: SomeInteger): T {.magic: "ShrI".}
func `shl`*[T: Ct](x: T, y: SomeInteger): T {.magic: "ShlI".}

func `*`*[T: Ct](x, y: T): T {.magic: "MulU".}
# Warning ⚠️ : We assume that mul hardware multiplication is constant time
# but this is not always true, especially on ARMv7 and ARMv9

# We don't implement div/mod as we can't assume the hardware implementation
# is constant-time

func `-`*(x: Ct): Ct =
  ## Unary minus returns the two-complement representation
  ## of an unsigned integer
  {.emit:"`result` = -`x`;".}

# ############################################################
#
#                           Bit hacks
#
# ############################################################

func isMsbSet*[T: Ct](x: T): CTBool[T] =
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

func `not`*(ctl: CTBool): CTBool =
  ## Negate a constant-time boolean
  (type result)(ctl.undistinct xor (type ctl.undistinct)(1))

func `and`*(x, y: CTBool): CTBool {.magic: "BitandI".}
func `or`*(x, y: CTBool): CTBool {.magic: "BitorI".}

func noteq[T: Ct](x, y: T): CTBool[T] =
  const msb = T.sizeof * 8 - 1
  let z = x xor y
  result = (type result)((z or -z) shr msb)

func `==`*[T: Ct](x, y: T): CTBool[T] =
  not(noteq(x, y))

func `<`*[T: Ct](x, y: T): CTBool[T] =
  result = isMsbSet(
      x xor (
        (x xor y) or ((x - y) xor y)
      )
    )

func `<=`*[T: Ct](x, y: T): CTBool[T] =
  not(y < x)

func `==`*(x, y: CTBool): CTBool =
  (type result)(x.undistinct == y.undistinct)

func `xor`*(x, y: CTBool): CTBool =
  (type result)(x.undistinct.noteq(y.undistinct))

template mux*[T: Ct](ctl: CTBool[T], x, y: T): T =
  ## Multiplexer / selector
  ## Returns x if ctl is true
  ## else returns y
  ## So equivalent to ctl? x: y
  y xor (-T(ctl) and (x xor y))

  # TODO verify assembly generated
  # as mentioned in https://cryptocoding.net/index.php/Coding_rules
  # the alternative `(x and ctl) or (y and -ctl)`
  # is optimized into a branch by Clang :/

  # TODO: assembly fastpath for conditional mov

template mux*[T: CTBool](ctl: CTBool, x, y: T): T =
  ## Multiplexer / selector
  ## Returns x if ctl is true
  ## else returns y
  ## So equivalent to ctl? x: y
  T(T.T(y) xor (-T.T(ctl) and T.T(x xor y)))

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

func isNonZero*[T: Ct](x: T): CTBool[T] =
  isMsbSet(x or -x)

func isZero*[T: Ct](x: T): CTBool[T] =
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
