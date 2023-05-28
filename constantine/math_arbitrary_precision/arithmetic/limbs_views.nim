# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ../../platforms/abstractions

# No exceptions allowed
{.push raises: [].}

# Datatype
# ------------------------------------------------------------

type
  LimbsView* = ptr UncheckedArray[SecretWord]
    ## Type-erased fixed-precision limbs
    ##
    ## This type mirrors the Limb type and is used
    ## for some low-level computation API
    ## This design
    ## - avoids code bloat due to generic monomorphization
    ##   otherwise limbs routines would have an instantiation for
    ##   each number of words.
    ##
    ## Accesses should be done via BigIntViewConst / BigIntViewConst
    ## to have the compiler check for mutability

  # "Indirection" to enforce pointer types deep immutability
  LimbsViewConst* = distinct LimbsView
    ## Immutable view into the limbs of a BigInt
  LimbsViewMut* = distinct LimbsView
    ## Mutable view into a BigInt
  LimbsViewAny* = LimbsViewConst or LimbsViewMut

# Deep Mutability safety
# ------------------------------------------------------------

template view*(a: Limbs): LimbsViewConst =
  ## Returns a borrowed type-erased immutable view to a bigint
  LimbsViewConst(cast[LimbsView](a.unsafeAddr))

template view*(a: var Limbs): LimbsViewMut =
  ## Returns a borrowed type-erased mutable view to a mutable bigint
  LimbsViewMut(cast[LimbsView](a.addr))

template view*(a: openArray[SecretWord]): LimbsViewConst =
  ## Returns a borrowed type-erased immutable view to a bigint
  LimbsViewConst(cast[LimbsView](a[0].unsafeAddr))

template view*(a: var openArray[SecretWord]): LimbsViewMut =
  ## Returns a borrowed type-erased mutable view to a mutable bigint
  LimbsViewMut(cast[LimbsView](a[0].addr))

template `[]`*(v: LimbsViewConst, limbIdx: int): SecretWord =
  LimbsView(v)[limbIdx]

template `[]`*(v: LimbsViewMut, limbIdx: int): var SecretWord =
  LimbsView(v)[limbIdx]

template `[]=`*(v: LimbsViewMut, limbIdx: int, val: SecretWord) =
  LimbsView(v)[limbIdx] = val

# Init
# ------------------------------------------------------------

func setZero*(p: LimbsViewMut, len: int) {.inline.} =
  for i in 0 ..< len:
    p[i] = Zero

# Copy
# ------------------------------------------------------------

func copyWords*(
       a: LimbsViewMut, startA: int,
       b: LimbsViewAny, startB: int,
       numWords: int) {.inline.} =
  ## Copy a slice of B into A. This properly deals
  ## with overlaps when A and B are slices of the same buffer
  if startA > startB:
    for i in countdown(numWords-1, 0):
      a[startA+i] = b[startB+i]
  else:
    for i in 0 ..< numWords:
      a[startA+i] = b[startB+i]

func ccopyWords*(
       a: LimbsViewMut, startA: int,
       b: LimbsViewAny, startB: int,
       ctl: SecretBool,
       numWords: int) {.inline.} =
  ## Copy a slice of B into A. This properly deals
  ## with overlaps when A and B are slices of the same buffer
  if startA > startB:
    for i in countdown(numWords-1, 0):
      ctl.ccopy(a[startA+i], b[startB+i])
  else:
    for i in 0 ..< numWords:
      ctl.ccopy(a[startA+i], b[startB+i])

# Comparison
# ------------------------------------------------------------

func lt*(a, b: distinct LimbsViewAny, len: int): SecretBool =
  ## Returns true if a < b
  ## Comparison is constant-time
  var diff: SecretWord
  var borrow: Borrow
  for i in 0 ..< len:
    subB(borrow, diff, a[i], b[i], borrow)

  result = (SecretBool)(borrow)

# Type-erased add-sub
# ------------------------------------------------------------

func cadd*(a: LimbsViewMut, b: LimbsViewAny, ctl: SecretBool, len: int): Carry =
  ## Type-erased conditional addition
  ## Returns the carry
  ##
  ## if ctl is true: a <- a + b
  ## if ctl is false: a <- a
  ## The carry is always computed whether ctl is true or false
  ##
  ## Time and memory accesses are the same whether a copy occurs or not
  result = Carry(0)
  var sum: SecretWord
  for i in 0 ..< len:
    addC(result, sum, a[i], b[i], result)
    ctl.ccopy(a[i], sum)

func csub*(a: LimbsViewMut, b: LimbsViewAny, ctl: SecretBool, len: int): Borrow =
  ## Type-erased conditional addition
  ## Returns the borrow
  ##
  ## if ctl is true: a <- a - b
  ## if ctl is false: a <- a
  ## The borrow is always computed whether ctl is true or false
  ##
  ## Time and memory accesses are the same whether a copy occurs or not
  result = Borrow(0)
  var diff: SecretWord
  for i in 0 ..< len:
    subB(result, diff, a[i], b[i], result)
    ctl.ccopy(a[i], diff)

# Modular reduction
# ------------------------------------------------------------

func numWordsFromBits*(bits: int): int {.inline.} =
  const divShiftor = log2_vartime(uint32(WordBitWidth))
  result = (bits + WordBitWidth - 1) shr divShiftor

{.pop.} # raises no exceptions
