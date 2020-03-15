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
  ./limbs,
  ./montgomery

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
    limbs*: array[bits.wordsRequired, Word]

# For unknown reason, `bits` doesn't semcheck if
#   `limbs: Limbs[bits.wordsRequired]`
# with
#   `Limbs[N: static int] = distinct array[N, Word]`
# so we don't set Limbs as a distinct type

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

func GT*(a, b: BigInt): CTBool[Word] =
  ## Returns true if a > b
  a.limbs.GT(b.limbs)

# ############################################################
#
#                   Modular BigInt
#
# ############################################################

func reduce*[aBits, mBits](r: var BigInt[mBits], a: BigInt[aBits], M: BigInt[mBits]) =
  ## Reduce `a` modulo `M` and store the result in `r`
  ##
  ## The modulus `M` **must** use `mBits` bits (bits at position mBits-1 must be set)
  ##
  ## CT: Depends only on the length of the modulus `M`

  # Note: for all cryptographic intents and purposes the modulus is known at compile-time
  # but we don't want to inline it as it would increase codesize, better have Nim
  # pass a pointer+length to a fixed session of the BSS.
  reduce(r.limbs, a.limbs, aBits, M.limbs, mBits)

# ############################################################
#
#                 Montgomery Arithmetic
#
# ############################################################

func montyResidue*(mres: var BigInt, a: BigInt, N, r2modM: static BigInt, m0ninv: static BaseType) =
  ## Convert a BigInt from its natural representation
  ## to the Montgomery n-residue form
  ##
  ## `mres` is overwritten. It's bitlength must be properly set before calling this procedure.
  ##
  ## Caller must take care of properly switching between
  ## the natural and montgomery domain.
  ## Nesting Montgomery form is possible by applying this function twice.
  ##
  ## The Montgomery Magic Constants:
  ## - `m0ninv` is µ = -1/N (mod M)
  ## - `r2modM` is R² (mod M)
  ## with W = M.len
  ## and R = (2^WordBitSize)^W
  montyResidue(mres.limbs, a.limbs, N.limbs, r2modM.limbs, Word(m0ninv))

func redc*[mBits](r: var BigInt[mBits], a: BigInt[mBits], N: static BigInt[mBits], m0ninv: static BaseType) =
  ## Convert a BigInt from its Montgomery n-residue form
  ## to the natural representation
  ##
  ## `mres` is modified in-place
  ##
  ## Caller must take care of properly switching between
  ## the natural and montgomery domain.
  const one = block:
    var one {.noInit.}: BigInt[mBits]
    one.setOne()
    one
  redc(r.limbs, a.limbs, one.limbs, N.limbs, Word(m0ninv))
