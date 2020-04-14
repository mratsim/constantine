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
  β* = object
    ## Non-Residue β
    ##
    ## Placeholder for the appropriate quadratic or cubic non-residue

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

  ExtensionField = QuadraticExt or CubicExt

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

# Abelian group
# -------------------------------------------------------------------

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

func neg*(r: var ExtensionField, a: ExtensionField) =
  ## Field out-of-place negation
  for fR, fA in fields(r, a):
    fR.neg(fA)

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
