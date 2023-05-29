# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./ct_types

# ############################################################
#
#                           Pragmas
#
# ############################################################

# No exceptions allowed
{.push raises: [].}
# SecretWord primitives are inlined
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

template ct*(x: auto, T: typedesc[BaseUint]): Ct[T] =
  (Ct[T])(x)

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
  # but this is not always true. See https://www.bearssl.org/ctmul.html
  fmap(x, `*`, y)

template `*=`*[T: Ct](x, y: T) =
  # Warning ⚠️ : We assume that mul hardware multiplication is constant time
  # but this is not always true. See https://www.bearssl.org/ctmul.html
  fmapAsgn(x, `*=`, y)

template `-`*[T: Ct](x: T): T =
  ## Unary minus returns the two-complement representation
  ## of an unsigned integer
  T(0) - x

# ############################################################
#
#             Hardened Boolean primitives
#
# ############################################################

template isMsbSet*[T: Ct](x: T): CTBool[T] =
  ## Returns the most significant bit of an integer
  const msb_pos = T.sizeof * 8 - 1
  (CTBool[T])(x shr msb_pos)

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
  {.push hint[ConvFromXtoItselfNotNeeded]: off.}
  let r = CTBool[T](noteq(T(x), T(y)))
  {.pop.}
  r

# ############################################################
#
#                       Conditionals
#
# ############################################################

template cneg*[T: Ct](x: T, ctl: CTBool[T]): T =
  # Conditional negate if ctl is true
  (x xor -T(ctl)) + T(ctl)

# ############################################################
#
#                       Table lookups
#
# ############################################################

func secretLookup*[T; S: Ct](table: openArray[T], index: S): T =
  ## Return table[index]
  ## This is constant-time, whatever the `index`, its value is not leaked
  ## This is also protected against cache-timing attack by always scanning the whole table
  var val: S
  for i in 0 ..< table.len:
    let selector = S(i) == index
    selector.ccopy(val, S table[i])
  return T(val)

# ############################################################
#
#             Optimized hardened zero comparison
#
# ############################################################

template isNonZero*[T: Ct](x: T): CTBool[T] =
  let x_NZ = x
  isMsbSet(x_NZ or -x_NZ)

template isZero*[T: Ct](x: T): CTBool[T] =
  # In x86 assembly, we can use "neg" + "adc"
  not isNonZero(x)
