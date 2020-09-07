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
  ../arithmetic

# Note: to avoid burdening the Nim compiler, we rely on generic extension
# to complain if the base field procedures don't exist

# Common type definition
# -------------------------------------------------------------------

type
  NonResidue* = object
    ## Non-Residue
    ##
    ## Placeholder for the appropriate quadratic, cubic or sectic non-residue

  CubicExt* = concept x
    ## Cubic Extension field concept
    type BaseField = auto
    x.c0 is BaseField
    x.c1 is BaseField
    x.c2 is BaseField

  QuadraticExt* = concept x
    ## Quadratic Extension field concept
    not(x is CubicExt)

    type BaseField = auto
    x.c0 is BaseField
    x.c1 is BaseField

  ExtensionField* = QuadraticExt or CubicExt

# Initialization
# -------------------------------------------------------------------

func setZero*(a: var ExtensionField) =
  ## Set ``a`` to 0 in the extension field
  for field in fields(a):
    field.setZero()

func setOne*(a: var ExtensionField) =
  ## Set ``a`` to 1 in the extension field
  for fieldName, fA in fieldPairs(a):
    when fieldName == "c0":
      fA.setOne()
    else:
      fA.setZero()

func fromBig*(a: var ExtensionField, src: BigInt) =
  ## Set ``a`` to the bigint value int eh extension field
  for fieldName, fA in fieldPairs(a):
    when fieldName == "c0":
      fA.fromBig(src)
    else:
      fA.setZero()

# Comparison
# -------------------------------------------------------------------

func `==`*(a, b: ExtensionField): SecretBool =
  ## Constant-time equality check
  result = CtTrue
  for fA, fB in fields(a, b):
    result = result and (fA == fB)

func isZero*(a: ExtensionField): SecretBool =
  ## Constant-time check if zero
  result = CtTrue
  for fA in fields(a):
    result = result and fA.isZero()

func isOne*(a: ExtensionField): SecretBool =
  ## Constant-time check if one
  result = CtTrue
  for fieldName, fA in fieldPairs(a):
    when fieldName == "c0":
      result = result and fA.isOne()
    else:
      result = result and fA.isZero()

# Copies
# -------------------------------------------------------------------

func ccopy*(a: var ExtensionField, b: ExtensionField, ctl: SecretBool) =
  ## Constant-time conditional copy
  ## If ctl is true: b is copied into a
  ## if ctl is false: b is not copied and a is unmodified
  ## Time and memory accesses are the same whether a copy occurs or not
  for fA, fB in fields(a, b):
    ccopy(fA, fB, ctl)

# Abelian group
# -------------------------------------------------------------------

func neg*(r: var ExtensionField, a: ExtensionField) =
  ## Field out-of-place negation
  for fR, fA in fields(r, a):
    fR.neg(fA)

func neg*(a: var ExtensionField) =
  ## Field out-of-place negation
  for fA in fields(a):
    fA.neg()

func `+=`*(a: var ExtensionField, b: ExtensionField) =
  ## Addition in the extension field
  for fA, fB in fields(a, b):
    fA += fB

func `-=`*(a: var ExtensionField, b: ExtensionField) =
  ## Substraction in the extension field
  for fA, fB in fields(a, b):
    fA -= fB

func double*(r: var ExtensionField, a: ExtensionField) =
  ## Field out-of-place doubling
  for fR, fA in fields(r, a):
    fR.double(fA)

func double*(a: var ExtensionField) =
  ## Field in-place doubling
  for fA in fields(a):
    fA.double()

func div2*(a: var ExtensionField) =
  ## Field in-place division by 2
  for fA in fields(a):
    fA.div2()

func sum*(r: var QuadraticExt, a, b: QuadraticExt) =
  ## Sum ``a`` and ``b`` into ``r``
  r.c0.sum(a.c0, b.c0)
  r.c1.sum(a.c1, b.c1)

func sum*(r: var CubicExt, a, b: CubicExt) =
  ## Sum ``a`` and ``b`` into ``r``
  r.c0.sum(a.c0, b.c0)
  r.c1.sum(a.c1, b.c1)
  r.c2.sum(a.c2, b.c2)

func diff*(r: var QuadraticExt, a, b: QuadraticExt) =
  ## Diff ``a`` and ``b`` into ``r``
  r.c0.diff(a.c0, b.c0)
  r.c1.diff(a.c1, b.c1)

func diff*(r: var CubicExt, a, b: CubicExt) =
  ## Diff ``a`` and ``b`` into ``r``
  r.c0.diff(a.c0, b.c0)
  r.c1.diff(a.c1, b.c1)
  r.c2.diff(a.c2, b.c2)

func diffAlias*(r: var QuadraticExt, a, b: QuadraticExt) =
  ## Diff ``a`` and ``b`` into ``r``
  ## Handles r and b aliasing
  r.c0.diffAlias(a.c0, b.c0)
  r.c1.diffAlias(a.c1, b.c1)

func diffAlias*(r: var CubicExt, a, b: CubicExt) =
  ## Diff ``a`` and ``b`` into ``r``
  ## Handles r and b aliasing
  r.c0.diffAlias(a.c0, b.c0)
  r.c1.diffAlias(a.c1, b.c1)
  r.c2.diffAlias(a.c2, b.c2)

# Multiplication by a small integer known at compile-time
# -------------------------------------------------------------------

func `*=`*(a: var ExtensionField, b: static int) {.inline.} =
  ## Multiplication by a small integer known at compile-time

  const negate = b < 0
  const b = if negate: -b
            else: b
  when negate:
    a.neg(a)
  when b == 0:
    a.setZero()
  elif b == 1:
    return
  elif b == 2:
    a.double()
  elif b == 3:
    let t1 = a
    a.double()
    a += t1
  elif b == 4:
    a.double()
    a.double()
  elif b == 5:
    let t1 = a
    a.double()
    a.double()
    a += t1
  elif b == 6:
    a.double()
    let t2 = a
    a.double() # 4
    a += t2
  elif b == 7:
    let t1 = a
    a.double()
    let t2 = a
    a.double() # 4
    a += t2
    a += t1
  elif b == 8:
    a.double()
    a.double()
    a.double()
  elif b == 9:
    let t1 = a
    a.double()
    a.double()
    a.double() # 8
    a += t1
  elif b == 10:
    a.double()
    let t2 = a
    a.double()
    a.double() # 8
    a += t2
  elif b == 11:
    let t1 = a
    a.double()
    let t2 = a
    a.double()
    a.double() # 8
    a += t2
    a += t1
  elif b == 12:
    a.double()
    a.double() # 4
    let t4 = a
    a.double() # 8
    a += t4
  else:
    {.error: "Multiplication by this small int not implemented".}
