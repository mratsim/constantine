# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/common,
  ../primitives,
  ./limbs

# ############################################################
#
#                        BigInts
#
# ############################################################

# The API is exported as a building block
# with enforced compile-time checking of BigInt bitwidth
# and memory ownership.

# ############################################################
# Design
#
# Control flow should only depends on the static maximum number of bits
# This number is defined per Finite Field/Prime/Elliptic Curve
#
# Data Layout
#
# The previous implementation of Constantine used type-erased views
# to optimized code-size (1)
# Also instead of using the full 64-bit of an uint64 it used
# 63-bit with the last bit to handle carries (2)
#
# (1) brought an advantage in terms of code-size if multiple curves
# were supported.
# However it prevented unrolling for some performance critical routines
# like addition and Montgomery multiplication. Furthermore, addition
# is only 1 or 2 instructions per limbs meaning unrolling+inlining
# is probably smaller in code-size than a function call.
#
# (2) Not using the full 64-bit eased carry and borrow handling.
# Also on older x86 Arch, the add-with-carry "ADC" instruction
# may be up to 6x slower than plain "ADD" with memory operand in a carry-chain.
#
# However, recent CPUs (less than 5 years) have reasonable or lower ADC latencies
# compared to the shifting and masking required when using 63 bits.
# Also we save on words to iterate on (1 word for BN254, secp256k1, BLS12-381)
#
# Furthermore, pairing curves are not fast-reduction friendly
# meaning that lazy reductions and lazy carries are impractical
# and so it's simpler to always carry additions instead of
# having redundant representations that forces costly reductions before multiplications.
# https://github.com/mratsim/constantine/issues/15

func wordsRequired(bits: int): int {.compileTime.} =
  ## Compute the number of limbs required
  # from the **announced** bit length
  (bits + WordBitWidth - 1) div WordBitWidth

type
  BigInt*[bits: static int] = object
    ## Fixed-precision big integer
    ##
    ## - "bits" is the announced bit-length of the BigInt
    ##   This is public data, usually equal to the curve prime bitlength.
    ##
    ## - "limbs" is an internal field that holds the internal representation
    ##   of the big integer. Least-significant limb first. Within limbs words are native-endian.
    ##
    ## This internal representation can be changed
    ## without notice and should not be used by external applications or libraries.
    limbs: array[bits.wordsRequired, Word]

debug:
  import strutils

  func `$`*(a: BigInt): string =
    result = "BigInt["
    result.add $BigInt.bits
    result.add "](limbs: ["
    result.add $BaseType(a.limbs[0]) & " (0x" & toHex(BaseType(a.limbs[0])) & ')'
    for i in 1 ..< a.limbs.len:
      result.add ", "
      result.add $BaseType(a.limbs[i]) & " (0x" & toHex(BaseType(a.limbs[i])) & ')'
    result.add "])"

# No exceptions allowed
{.push raises: [].}
{.push inline.}

func `==`*(a, b: BigInt): CTBool[Word] =
  ## Returns true if 2 big ints are equal
  ## Comparison is constant-time
  a.limbs == b.limbs

func isZero*(a: BigInt): CTBool[Word] =
  ## Returns true if a big int is equal to zero
  a.limbs.isZero

func setZero*(a: var BigInt) =
  ## Set a BigInt to 0
  a.limbs.setZero()

func setOne*(a: var BigInt) =
  ## Set a BigInt to 1
  a.limbs.setOne()

func cadd*(a: var BigInt, b: BigInt, ctl: CTBool[Word]): CTBool[Word] =
  ## Constant-time in-place conditional addition
  ## The addition is only performed if ctl is "true"
  ## The result carry is always computed.
  (CTBool[Word]) cadd(a.limbs, b.limbs, ctl)

func csub*(a: var BigInt, b: BigInt, ctl: CTBool[Word]): CTBool[Word] =
  ## Constant-time in-place conditional addition
  ## The addition is only performed if ctl is "true"
  ## The result carry is always computed.
  (CTBool[Word]) csub(a.limbs, b.limbs, ctl)

func cdouble*(a: var BigInt, ctl: CTBool[Word]): CTBool[Word] =
  ## Constant-time in-place conditional doubling
  ## The doubling is only performed if ctl is "true"
  ## The result carry is always computed.
  (CTBool[Word]) cadd(a.limbs, a.limbs, ctl)

# ############################################################
#
#          BigInt Primitives Optimized for speed
#
# ############################################################
#
# TODO: fallback to cadd / csub with a "size" compile-option

func add*(a: var BigInt, b: BigInt): CTBool[Word] =
  ## Constant-time in-place addition
  ## Returns the carry
  (CTBool[Word]) add(a.limbs, b.limbs)

func sub*(a: var BigInt, b: BigInt): CTBool[Word] =
  ## Constant-time in-place substraction
  ## Returns the borrow
  (CTBool[Word]) sub(a.limbs, b.limbs)

func double*(a: var BigInt): CTBool[Word] =
  ## Constant-time in-place doubling
  ## Returns the carry
  (CTBool[Word]) add(a.limbs, a.limbs)

func sum*(r: var BigInt, a, b: BigInt): CTBool[Word] =
  ## Sum `a` and `b` into `r`.
  ## `r` is initialized/overwritten
  ##
  ## Returns the carry
  (CTBool[Word]) sum(r.limbs, a.limbs, b.limbs)

func diff*(r: var BigInt, a, b: BigInt): CTBool[Word] =
  ## Substract `b` from `a` and store the result into `r`.
  ## `r` is initialized/overwritten
  ##
  ## Returns the borrow
  (CTBool[Word]) diff(r.limbs, a.limbs, b.limbs)

func double*(r: var BigInt, a: BigInt): CTBool[Word] =
  ## Double `a` into `r`.
  ## `r` is initialized/overwritten
  ##
  ## Returns the carry
  (CTBool[Word]) sum(r.limbs, a.limbs, a.limbs)

# ############################################################
#
#                    Comparisons
#
# ############################################################

# Use "csub", which unfortunately requires the first operand to be mutable.
# for example for a <= b, we now that if a-b borrows then b > a and so a<=b is false
# This can be tested with "not csub(a, b, CtFalse)"
