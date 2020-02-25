# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../arithmetic/finite_fields,
  ../config/common,
  ../primitives/constant_time

# ############################################################
#
#                     Algebraic concepts
#
# ############################################################
# Too heavy on the Nim compiler, we just rely on generic instantiation
# to complain if the base field procedures don't exist.

# type
#   AbelianGroup* {.explain.} = concept a, b, var mA, var mR
#     setZero(mA)
#     setOne(mA)
#     `+=`(mA, b)
#     `-=`(mA, b)
#     double(mR, a)
#     sum(mR, a, b)
#     diff(mR, a, b)

# ############################################################
#
#                 Quadratic Extension fields
#
# ############################################################

type
  QuadExtAddGroup* = concept x
    ## Quadratic extension fields - Abelian Additive Group concept
    type BaseField = auto
    x.c0 is BaseField
    x.c1 is BaseField

func `==`*(a, b: QuadExtAddGroup): CTBool[Word] =
  ## Constant-time equality check
  (a.c0 == b.c0) and (a.c1 == b.c1)

func setZero*(a: var QuadExtAddGroup) =
  ## Set ``a`` to zero in the extension field
  ## Coordinates 0 + 0 𝛼
  ## with 𝛼 the solution of f(x) = x² - µ = 0
  a.c0.setZero()
  a.c1.setZero()

func setOne*(a: var QuadExtAddGroup) =
  ## Set ``a`` to one in the extension field
  ## Coordinates 1 + 0 𝛼
  ## with 𝛼 the solution of f(x) = x² - µ = 0
  a.c0.setOne()
  a.c1.setZero()

func `+=`*(a: var QuadExtAddGroup, b: QuadExtAddGroup) =
  ## Addition in the extension field
  a.c0 += b.c0
  a.c1 += b.c1

func `-=`*(a: var QuadExtAddGroup, b: QuadExtAddGroup) =
  ## Substraction in the extension field
  a.c0 -= b.c0
  a.c1 -= b.c1

func double*(r: var QuadExtAddGroup, a: QuadExtAddGroup) =
  ## Double in the extension field
  r.c0.double(a.c0)
  r.c1.double(a.c1)

func sum*(r: var QuadExtAddGroup, a, b: QuadExtAddGroup) =
  ## Sum ``a`` and ``b`` into r
  r.c0.sum(a.c0, b.c0)
  r.c1.sum(a.c1, b.c1)

func diff*(r: var QuadExtAddGroup, a, b: QuadExtAddGroup) =
  ## Difference of ``a`` by `b`` into r
  r.c0.diff(a.c0, b.c0)
  r.c1.diff(a.c1, b.c1)

# ############################################################
#
#                 Cubic Extension fields
#
# ############################################################

type
  CubicExtAddGroup* = concept x
    ## Cubic extension fields - Abelian Additive Group concept
    type BaseField = auto
    x.c0 is BaseField
    x.c1 is BaseField
    x.c2 is BaseField

func `==`*(a, b: CubicExtAddGroup): CTBool[Word] =
  ## Constant-time equality check
  (a.c0 == b.c0) and (a.c1 == b.c1) and (a.c2 == b.c2)

func setZero*(a: var CubicExtAddGroup) =
  ## Set ``a`` to zero in the extension field
  ## Coordinates 0 + 0 w + 0 w²
  ## with w the solution of f(x) = x³ - µ = 0
  a.c0.setZero()
  a.c1.setZero()
  a.c2.setZero()

func setOne*(a: var CubicExtAddGroup) =
  ## Set ``a`` to one in the extension field
  ## Coordinates 1 + 0 w + 0 w²
  ## with w the solution of f(x) = x³ - µ = 0
  a.c0.setOne()
  a.c1.setZero()
  a.c2.setZero()

func `+=`*(a: var CubicExtAddGroup, b: CubicExtAddGroup) =
  ## Addition in the extension field
  a.c0 += b.c0
  a.c1 += b.c1
  a.c2 += b.c2

func `-=`*(a: var CubicExtAddGroup, b: CubicExtAddGroup) =
  ## Substraction in the extension field
  a.c0 -= b.c0
  a.c1 -= b.c1
  a.c2 -= b.c2

func double*(r: var CubicExtAddGroup, a: CubicExtAddGroup) =
  ## Double in the extension field
  r.c0.double(a.c0)
  r.c1.double(a.c1)
  r.c2.double(a.c2)

func sum*(r: var CubicExtAddGroup, a, b: CubicExtAddGroup) =
  ## Sum ``a`` and ``b`` into r
  r.c0.sum(a.c0, b.c0)
  r.c1.sum(a.c1, b.c1)
  r.c2.sum(a.c2, b.c2)

func diff*(r: var CubicExtAddGroup, a, b: CubicExtAddGroup) =
  ## Difference of ``a`` by `b`` into r
  r.c0.diff(a.c0, b.c0)
  r.c1.diff(a.c1, b.c1)
  r.c2.diff(a.c2, b.c2)
