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

# TODO: cleanup openArray vs LimbsView

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

# Bit operations
# ------------------------------------------------------------

func getMSB_vartime*[T](a: openArray[T]): int =
  ## Returns the position of the most significant bit
  ## of `a`.
  ## Returns -1 if a == 0
  result = -1
  for i in countdown(a.len-1, 0):
    if bool a[i] != T(0):
      return int(log2_vartime(uint64 a[i])) + 8*sizeof(T)*i

func getBits_vartime*[T](a: openArray[T]): int {.inline.} =
  ## Returns the number of bits used by `a`
  ## Returns 0 for 0
  1 + getMSB_vartime(a)

{.pop.} # raises no exceptions
