# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./constant_time_types

# ############################################################
#
#                           Pragmas
#
# ############################################################

# No exceptions allowed
{.push raises: [].}
# Word primitives are inlined
{.push inline.}

# ############################################################
#
#                        Constructors
#
# ############################################################

template ctrue*(T: typedesc[Ct or BaseUint]): auto =
  when T is Ct:
    (CTBool[T])(true)
  else:
    (CTBool[Ct[T]])(true)

template cfalse*(T: typedesc[Ct or BaseUint]): auto =
  when T is Ct:
    (CTBool[T])(false)
  else:
    (CTBool[Ct[T]])(false)

template ct*[T: BaseUint](x: T): Ct[T] =
  (Ct[T])(x)

template `$`*[T](x: Ct[T]): string =
  $T(x)

template `$`*(x: CTBool): string =
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
# We should use {.borrow.} instead:
#    - https://github.com/nim-lang/Nim/pull/8531
#    - https://github.com/nim-lang/Nim/issues/4121 (can be workaround with #8531)
#
# We use templates to enforce inlining in generated C code.
# inline proc pollutes the C code with may small proc and
# compilers might hit inlining limits, especially given
# that we can have hundreds of calls to those primitives in a single algorithm
#
# Note that templates duplicate their input parameters.
# If a param is used multiple times, it **must** be `let` assigned first
# to avoid duplicate computation or duplicate side-effect.
# We append a mnemonic like `mux` or `LT` to help inspecting the C code

template fmap[T: Ct](x: T, op: untyped, y: T): T =
  ## Unwrap x and y from their distinct type
  ## Apply op, and rewrap them
  T(op(T.T(x), T.T(y)))

template fmapAsgn[T: Ct](x: T, op: untyped, y: T) =
  ## Unwrap x and y from their distinct type
  ## Apply assignment op, and rewrap them
  op(T.T(x), T.T(y))

template `and`*[T: Ct](x, y: T): T    = fmap(x, `and`, y)
template `or`*[T: Ct](x, y: T): T     = fmap(x, `or`, y)
template `xor`*[T: Ct](x, y: T): T    = fmap(x, `xor`, y)
template `not`*[T: Ct](x: T): T       = T(not T.T(x))
template `+`*[T: Ct](x, y: T): T      = fmap(x, `+`, y)
template `+=`*[T: Ct](x: var T, y: T) = fmapAsgn(x, `+=`, y)
template `-`*[T: Ct](x, y: T): T      = fmap(x, `-`, y)
template `-=`*[T: Ct](x: var T, y: T) = fmapAsgn(x, `-=`, y)
template `shr`*[T: Ct](x: T, y: SomeInteger): T = T(T.T(x) shr y)
template `shl`*[T: Ct](x: T, y: SomeInteger): T = T(T.T(x) shl y)

template `*`*[T: Ct](x, y: T): T =
  # Warning ⚠️ : We assume that mul hardware multiplication is constant time
  # but this is not always true, especially on ARMv7 and ARMv9
  fmap(x, `*`, y)

# We don't implement div/mod as we can't assume the hardware implementation
# is constant-time

template `-`*[T: Ct](x: T): T =
  ## Unary minus returns the two-complement representation
  ## of an unsigned integer
  # We could use "not(x) + 1" but the codegen is not optimal
  block:
    var neg: T
    {.emit:[neg, " = -", x, ";"].}
    neg

# ############################################################
#
#                           Bit hacks
#
# ############################################################

template isMsbSet*[T: Ct](x: T): CTBool[T] =
  ## Returns the most significant bit of an integer
  const msb_pos = T.sizeof * 8 - 1
  (CTBool[T])(x shr msb_pos)

func log2*(x: uint32): uint32 =
  ## Find the log base 2 of a 32-bit or less integer.
  ## using De Bruijn multiplication
  ## Works at compile-time, guaranteed constant-time.
  ## Note: at runtime BitScanReverse or CountLeadingZero are more efficient
  ##       but log2 is never needed at runtime.
  # https://graphics.stanford.edu/%7Eseander/bithacks.html#IntegerLogDeBruijn
  const lookup: array[32, uint8] = [0'u8, 9, 1, 10, 13, 21, 2, 29, 11, 14, 16, 18,
    22, 25, 3, 30, 8, 12, 20, 28, 15, 17, 24, 7, 19, 27, 23, 6, 26, 5, 4, 31]
  var v = x
  v = v or v shr 1 # first round down to one less than a power of 2
  v = v or v shr 2
  v = v or v shr 4
  v = v or v shr 8
  v = v or v shr 16
  lookup[(v * 0x07C4ACDD'u32) shr 27]

func log2*(x: uint64): uint64 {.inline, noSideEffect.} =
  ## Find the log base 2 of a 32-bit or less integer.
  ## using De Bruijn multiplication
  ## Works at compile-time, guaranteed constant-time.
  ## Note: at runtime BitScanReverse or CountLeadingZero are more efficient
  ##       but log2 is never needed at runtime.
  # https://graphics.stanford.edu/%7Eseander/bithacks.html#IntegerLogDeBruijn
  const lookup: array[64, uint8] = [0'u8, 58, 1, 59, 47, 53, 2, 60, 39, 48, 27, 54,
    33, 42, 3, 61, 51, 37, 40, 49, 18, 28, 20, 55, 30, 34, 11, 43, 14, 22, 4, 62,
    57, 46, 52, 38, 26, 32, 41, 50, 36, 17, 19, 29, 10, 13, 21, 56, 45, 25, 31,
    35, 16, 9, 12, 44, 24, 15, 8, 23, 7, 6, 5, 63]
  var v = x
  v = v or v shr 1 # first round down to one less than a power of 2
  v = v or v shr 2
  v = v or v shr 4
  v = v or v shr 8
  v = v or v shr 16
  v = v or v shr 32
  lookup[(v * 0x03F6EAF2CD271461'u64) shr 58]

# ############################################################
#
#             Hardened Boolean primitives
#
# ############################################################

template fmap[T: Ct](x: CTBool[T], op: untyped, y: CTBool[T]): CTBool[T] =
  CTBool[T](op(T(x), T(y)))

template `not`*[T: Ct](ctl: CTBool[T]): CTBool[T] =
  ## Negate a constant-time boolean
  CTBool[T](T(ctl) xor T(1))

template `and`*(x, y: CTBool): CTBool = fmap(x, `and`, y)
template `or`*(x, y: CTBool): CTBool = fmap(x, `or`, y)

template noteq[T: Ct](x, y: T): CTBool[T] =
  const msb = T.sizeof * 8 - 1
  let z_NEQ = x xor y
  CTBool[T]((z_NEQ or -z_NEQ) shr msb)

template `==`*[T: Ct](x, y: T): CTBool[T] =
  not(noteq(x, y))

template `<`*[T: Ct](x, y: T): CTBool[T] =
  let # Templates duplicate input params code
    x_LT = x
    y_LT = y
  isMsbSet(
      x_LT xor (
        (x_LT xor y_LT) or ((x_LT - y_LT) xor y_LT)
      )
    )

template `<=`*[T: Ct](x, y: T): CTBool[T] =
  not(y < x)

template `xor`*[T: Ct](x, y: CTBool[T]): CTBool[T] =
  CTBool[T](noteq(T(x), T(y)))

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

template isNonZero*[T: Ct](x: T): CTBool[T] =
  let x_NZ = x
  isMsbSet(x_NZ or -x_NZ)

template isZero*[T: Ct](x: T): CTBool[T] =
  not isNonZero(x)

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
