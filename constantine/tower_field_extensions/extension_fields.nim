# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/[common, curves],
  ../primitives,
  ../arithmetic

# Note: to avoid burdening the Nim compiler, we rely on generic extension
# to complain if the base field procedures don't exist

# No exceptions allowed
{.push raises: [].}
{.push inline.}

# ############################################################
#                                                            #
#                    Extension Fields                        #
#                                                            #
# ############################################################

type
  NonResidue* = object
    ## Non-Residue
    ##
    ## Placeholder for the appropriate quadratic, cubic or sectic non-residue

  QuadraticExt*[F] = object
    ## Quadratic Extension field
    coords*: array[2, F]

  CubicExt*[F] = object
    ## Cubic Extension field
    coords*: array[3, F]

  ExtensionField*[F] = QuadraticExt[F] or CubicExt[F]

template c0*(a: ExtensionField): auto =
  a.coords[0]
template c1*(a: ExtensionField): auto =
  a.coords[1]
template c2*(a: CubicExt): auto =
  a.coords[2]

template `c0=`*(a: var ExtensionField, v: auto) =
  a.coords[0] = v
template `c1=`*(a: var ExtensionField, v: auto) =
  a.coords[1] = v
template `c2=`*(a: var CubicExt, v: auto) =
  a.coords[2] = v

template C*(E: type ExtensionField): Curve =
  E.F.C

template fieldMod*(E: type ExtensionField): auto =
  Fp[E.F.C].fieldMod()

# Initialization
# -------------------------------------------------------------------

func setZero*(a: var ExtensionField) =
  ## Set ``a`` to 0 in the extension field
  staticFor i, 0, a.coords.len:
    a.coords[i].setZero()

func setOne*(a: var ExtensionField) =
  ## Set ``a`` to 1 in the extension field
  a.coords[0].setOne()
  staticFor i, 1, a.coords.len:
    a.coords[i].setZero()

func fromBig*(a: var ExtensionField, src: BigInt) =
  ## Set ``a`` to the bigint value in the extension field
  a.coords[0].fromBig(src)
  staticFor i, 1, a.coords.len:
    a.coords[i].setZero()

# Comparison
# -------------------------------------------------------------------

func `==`*(a, b: ExtensionField): SecretBool =
  ## Constant-time equality check
  result = CtTrue
  staticFor i, 0, a.coords.len:
    result = result and (a.coords[i] == b.coords[i])

func isZero*(a: ExtensionField): SecretBool =
  ## Constant-time check if zero
  result = CtTrue
  staticFor i, 0, a.coords.len:
    result = result and a.coords[i].isZero()

func isOne*(a: ExtensionField): SecretBool =
  ## Constant-time check if one
  result = CtTrue
  result = result and a.coords[0].isOne()
  staticFor i, 1, a.coords.len:
    result = result and a.coords[i].isZero()

func isMinusOne*(a: ExtensionField): SecretBool =
  ## Constant-time check if -1
  result = CtTrue
  result = result and a.coords[0].isMinusOne()
  staticFor i, 1, a.coords.len:
    result = result and a.coords[i].isZero()

# Copies
# -------------------------------------------------------------------

func ccopy*(a: var ExtensionField, b: ExtensionField, ctl: SecretBool) =
  ## Constant-time conditional copy
  ## If ctl is true: b is copied into a
  ## if ctl is false: b is not copied and a is unmodified
  ## Time and memory accesses are the same whether a copy occurs or not
  staticFor i, 0, a.coords.len:
    a.coords[i].ccopy(b.coords[i], ctl)

# Abelian group
# -------------------------------------------------------------------

func neg*(r: var ExtensionField, a: ExtensionField) =
  ## Field out-of-place negation
  staticFor i, 0, a.coords.len:
    r.coords[i].neg(a.coords[i])

func neg*(a: var ExtensionField) =
  ## Field in-place negation
  staticFor i, 0, a.coords.len:
    a.coords[i].neg()

func `+=`*(a: var ExtensionField, b: ExtensionField) =
  ## Addition in the extension field
  staticFor i, 0, a.coords.len:
    a.coords[i] += b.coords[i]

func `-=`*(a: var ExtensionField, b: ExtensionField) =
  ## Substraction in the extension field
  staticFor i, 0, a.coords.len:
    a.coords[i] -= b.coords[i]

func double*(r: var ExtensionField, a: ExtensionField) =
  ## Field out-of-place doubling
  staticFor i, 0, a.coords.len:
    r.coords[i].double(a.coords[i])

func double*(a: var ExtensionField) =
  ## Field in-place doubling
  staticFor i, 0, a.coords.len:
    a.coords[i].double()

func div2*(a: var ExtensionField) =
  ## Field in-place division by 2
  staticFor i, 0, a.coords.len:
    a.coords[i].div2()

func sum*(r: var ExtensionField, a, b: ExtensionField) =
  ## Sum ``a`` and ``b`` into ``r``
  staticFor i, 0, a.coords.len:
    r.coords[i].sum(a.coords[i], b.coords[i])

func diff*(r: var ExtensionField, a, b: ExtensionField) =
  ## Diff ``a`` and ``b`` into ``r``
  staticFor i, 0, a.coords.len:
    r.coords[i].diff(a.coords[i], b.coords[i])

func conj*(a: var QuadraticExt) =
  ## Computes the conjugate in-place
  a.c1.neg()

func conj*(r: var QuadraticExt, a: QuadraticExt) =
  ## Computes the conjugate out-of-place
  r.c0 = a.c0
  r.c1.neg(a.c1)

func conjneg*(a: var QuadraticExt) =
  ## Computes the negated conjugate in-place
  a.c0.neg()

func conjneg*(r: var QuadraticExt, a: QuadraticExt) =
  ## Computes the negated conjugate out-of-place
  r.c0.neg(a.c0)
  r.c1 = a.c1

func conj*(a: var CubicExt) =
  ## Computes the conjugate in-place
  a.c0.conj()
  a.c1.conjneg()
  a.c2.conj()

func conj*(r: var CubicExt, a: CubicExt) =
  ## Computes the conjugate out-of-place
  r.c0.conj(a.c0)
  r.c1.conjneg(a.c1)
  r.c2.conj(a.c2)

# Conditional arithmetic
# -------------------------------------------------------------------

func cneg*(a: var ExtensionField, ctl: SecretBool) =
  ## Constant-time in-place conditional negation
  ## Only negate if ctl is true
  staticFor i, 0, a.coords.len:
    a.coords[i].cneg(ctl)

func cadd*(a: var ExtensionField, b: ExtensionField, ctl: SecretBool) =
  ## Constant-time in-place conditional addition
  staticFor i, 0, a.coords.len:
    a.coords[i].cadd(b.coords[i], ctl)

func csub*(a: var ExtensionField, b: ExtensionField, ctl: SecretBool) =
  ## Constant-time in-place conditional substraction
  staticFor i, 0, a.coords.len:
    a.coords[i].csub(b.coords[i], ctl)

# Multiplication by a small integer known at compile-time
# -------------------------------------------------------------------

func `*=`*(a: var ExtensionField, b: static int) =
  ## Multiplication by a small integer known at compile-time
  for i in 0 ..< a.coords.len:
    a.coords[i] *= b

func prod*(r: var ExtensionField, a: ExtensionField, b: static int) =
  ## Multiplication by a small integer known at compile-time
  r = a
  r *= b

{.pop.} # inline

# ############################################################
#                                                            #
#              Lazy reduced extension fields                 #
#                                                            #
# ############################################################

type
  QuadraticExt2x[F] = object
    ## Quadratic Extension field for lazy reduced fields
    coords: array[2, F]

  CubicExt2x[F] = object
    ## Cubic Extension field for lazy reduced fields
    coords: array[3, F]

  ExtensionField2x[F] = QuadraticExt2x[F] or CubicExt2x[F]

template doublePrec(T: type ExtensionField): type =
  # For now naive unrolling, recursive template don't match
  # and I don't want to deal with types in macros
  when T is QuadraticExt:
    when T.F is QuadraticExt: # Fp4Dbl
      QuadraticExt2x[QuadraticExt2x[doublePrec(T.F.F)]]
    elif T.F is Fp:           # Fp2Dbl
      QuadraticExt2x[doublePrec(T.F)]
  elif T is CubicExt:
    when T.F is QuadraticExt: #
      when T.F.F is QuadraticExt: # Fp12
        CubicExt2x[QuadraticExt2x[QuadraticExt2x[doublePrec(T.F.F.F)]]]
      elif T.F.F is Fp: # Fp6
        CubicExt2x[QuadraticExt2x[doublePrec(T.F.F)]]

func has1extraBit(F: type Fp): bool =
  ## We construct extensions only on Fp (and not Fr)
  getSpareBits(F) >= 1

func has2extraBits(F: type Fp): bool =
  ## We construct extensions only on Fp (and not Fr)
  getSpareBits(F) >= 2

func has1extraBit(E: type ExtensionField): bool =
  ## We construct extensions only on Fp (and not Fr)
  getSpareBits(Fp[E.F.C]) >= 1

func has2extraBits(E: type ExtensionField): bool =
  ## We construct extensions only on Fp (and not Fr)
  getSpareBits(Fp[E.F.C]) >= 2

template C(E: type ExtensionField2x): Curve =
  E.F.C

template c0(a: ExtensionField2x): auto =
  a.coords[0]
template c1(a: ExtensionField2x): auto =
  a.coords[1]
template c2(a: CubicExt2x): auto =
  a.coords[2]

template `c0=`(a: var ExtensionField2x, v: auto) =
  a.coords[0] = v
template `c1=`(a: var ExtensionField2x, v: auto) =
  a.coords[1] = v
template `c2=`(a: var CubicExt2x, v: auto) =
  a.coords[2] = v

# Initialization
# -------------------------------------------------------------------

func setZero*(a: var ExtensionField2x) =
  ## Set ``a`` to 0 in the extension field
  staticFor i, 0, a.coords.len:
    a.coords[i].setZero()

# Abelian group
# -------------------------------------------------------------------

func sumUnr(r: var ExtensionField, a, b: ExtensionField) =
  ## Sum ``a`` and ``b`` into ``r``
  staticFor i, 0, a.coords.len:
    r.coords[i].sumUnr(a.coords[i], b.coords[i])

func diff2xUnr(r: var ExtensionField2x, a, b: ExtensionField2x) =
  ## Double-precision substraction without reduction
  staticFor i, 0, a.coords.len:
    r.coords[i].diff2xUnr(a.coords[i], b.coords[i])

func diff2xMod(r: var ExtensionField2x, a, b: ExtensionField2x) =
  ## Double-precision modular substraction
  staticFor i, 0, a.coords.len:
    r.coords[i].diff2xMod(a.coords[i], b.coords[i])

func sum2xUnr(r: var ExtensionField2x, a, b: ExtensionField2x) =
  ## Double-precision addition without reduction
  staticFor i, 0, a.coords.len:
    r.coords[i].sum2xUnr(a.coords[i], b.coords[i])

func sum2xMod(r: var ExtensionField2x, a, b: ExtensionField2x) =
  ## Double-precision modular addition
  staticFor i, 0, a.coords.len:
    r.coords[i].sum2xMod(a.coords[i], b.coords[i])

func neg2xMod(r: var ExtensionField2x, a: ExtensionField2x) =
  ## Double-precision modular negation
  staticFor i, 0, a.coords.len:
    r.coords[i].neg2xMod(a.coords[i], b.coords[i])

# Reductions
# -------------------------------------------------------------------

func redc2x(r: var ExtensionField, a: ExtensionField2x) =
  ## Reduction
  staticFor i, 0, a.coords.len:
    r.coords[i].redc2x(a.coords[i])

# Multiplication by a small integer known at compile-time
# -------------------------------------------------------------------

func prod2x(r: var ExtensionField2x, a: ExtensionField2x, b: static int) =
  ## Multiplication by a small integer known at compile-time
  for i in 0 ..< a.coords.len:
    r.coords[i].prod2x(a.coords[i], b)

# NonResidue
# ----------------------------------------------------------------------

func prod2x(r: var FpDbl, a: FpDbl, _: type NonResidue){.inline.} =
  ## Multiply an element of 𝔽p by the quadratic non-residue
  ## chosen to construct 𝔽p2
  static: doAssert FpDbl.C.getNonResidueFp() != -1, "𝔽p2 should be specialized for complex extension"
  r.prod2x(a, FpDbl.C.getNonResidueFp())

func prod2x[C: static Curve](
       r: var QuadraticExt2x[FpDbl[C]],
       a: QuadraticExt2x[FpDbl[C]],
       _: type NonResidue) {.inline.} =
  ## Multiplication by non-residue
  const complex = C.getNonResidueFp() == -1
  const U = C.getNonResidueFp2()[0]
  const V = C.getNonResidueFp2()[1]
  const Beta {.used.} = C.getNonResidueFp()

  when complex and U == 1 and V == 1:
    let a1 = a.c1
    r.c1.sum2xMod(a.c0, a1)
    r.c0.diff2xMod(a.c0, a1)
  else:
    # Case:
    # - BN254_Snarks, QNR_Fp: -1, SNR_Fp2: 9+1𝑖  (𝑖 = √-1)
    # - BLS12_377, QNR_Fp: -5, SNR_Fp2: 0+1j    (j = √-5)
    # - BW6_761, SNR_Fp: -4, CNR_Fp2: 0+1j      (j = √-4)
    when U == 0:
      # mul_sparse_by_0v
      # r0 = β a1 v
      # r1 = a0 v
      var t {.noInit.}: FpDbl[C]
      t.prod2x(a.c1, V)
      r.c1.prod2x(a.c0, V)
      r.c0.prod2x(t, NonResidue)
    else:
      # ξ = u + v x
      # and x² = β
      #
      # (c0 + c1 x) (u + v x) => u c0 + (u c0 + u c1)x + v c1 x²
      #                       => u c0 + β v c1 + (v c0 + u c1) x
      var t {.noInit.}: FpDbl[C]

      t.prod2x(a.c0, U)
      when V == 1 and Beta == -1:  # Case BN254_Snarks
        t.diff2xMod(t, a.c1)       # r0 = u c0 + β v c1
      else:
        {.error: "Unimplemented".}


      r.c1.prod2x(a.c1, U)
      when V == 1:                 # r1 = v c0 + u c1
        r.c1.sum2xMod(r.c1, a.c0)
        # aliasing: a.c0 is unused
        `=`(r.c0, t) # "r.c0 = t", is refused by the compiler.
      else:
        {.error: "Unimplemented".}

func prod2x(
       r: var QuadraticExt2x,
       a: QuadraticExt2x,
       _: type NonResidue) {.inline.} =
  ## Multiplication by non-residue
  static: doAssert not(r.c0 is FpDbl), "Wrong dispatch, there is a specific non-residue multiplication for the base extension."
  let t = a.c0
  r.c0.prod2x(a.c1, NonResidue)
  `=`(r.c1, t) # "r.c1 = t", is refused by the compiler.

func prod2x(
       r: var CubicExt2x,
       a: CubicExt2x,
       _: type NonResidue) {.inline.} =
  ## Multiplication by non-residue
  ## For all curves γ = v with v the factor for cubic extension coordinate
  ## and v³ = ξ
  ## (c0 + c1 v + c2 v²) v => ξ c2 + c0 v + c1 v²
  let t = a.c2
  r.c1 = a.c0
  r.c2 = a.c1
  r.c0.prod2x(t, NonResidue)

# ############################################################
#                                                            #
#          Quadratic extensions - Lazy Reductions            #
#                                                            #
# ############################################################

# Forward declarations
# ----------------------------------------------------------------------

func prod2x(r: var QuadraticExt2x, a, b: QuadraticExt)
func square2x(r: var QuadraticExt2x, a: QuadraticExt)

# Commutative ring implementation for complex quadratic extension fields
# ----------------------------------------------------------------------

func prod2x_complex(r: var QuadraticExt2x, a, b: QuadraticExt) =
  ## Double-precision unreduced complex multiplication
  # r and a or b cannot alias

  mixin fromComplexExtension
  static: doAssert a.fromComplexExtension()

  var D {.noInit.}: typeof(r.c0)
  var t0 {.noInit.}, t1 {.noInit.}: typeof(a.c0)

  r.c0.prod2x(a.c0, b.c0)        # r0 = a0 b0
  D.prod2x(a.c1, b.c1)           # d =  a1 b1
  when QuadraticExt.has1extraBit():
    t0.sumUnr(a.c0, a.c1)
    t1.sumUnr(b.c0, b.c1)
  else:
    t0.sum(a.c0, a.c1)
    t1.sum(b.c0, b.c1)
  r.c1.prod2x(t0, t1)            # r1 = (b0 + b1)(a0 + a1)
  when QuadraticExt.has1extraBit():
    r.c1.diff2xUnr(r.c1, r.c0) # r1 = (b0 + b1)(a0 + a1) - a0 b0
    r.c1.diff2xUnr(r.c1, D)    # r1 = (b0 + b1)(a0 + a1) - a0 b0 - a1b1
  else:
    r.c1.diff2xMod(r.c1, r.c0)
    r.c1.diff2xMod(r.c1, D)
  r.c0.diff2xMod(r.c0, D)        # r0 = a0 b0 - a1 b1

func square2x_complex(r: var QuadraticExt2x, a: QuadraticExt) =
  ## Double-precision unreduced complex squaring

  mixin fromComplexExtension
  static: doAssert a.fromComplexExtension()

  var t0 {.noInit.}, t1 {.noInit.}: typeof(a.c0)

  when QuadraticExt.has1extraBit():
    t0.sumUnr(a.c1, a.c1)
    t1.sumUnr(a.c0, a.c1)
  else:
    t0.double(a.c1)
    t1.sum(a.c0, a.c1)

  r.c1.prod2x(t0, a.c0)     # r1 = 2a0a1
  t0.diff(a.c0, a.c1)
  r.c0.prod2x(t0, t1)       # r0 = (a0 + a1)(a0 - a1)

# Commutative ring implementation for generic quadratic extension fields
# ----------------------------------------------------------------------
#
# Some sparse functions, reconstruct a Fp4 from disjoint pieces
# to limit copies, we provide versions with disjoint elements
# prod2x_disjoint:
# - 2 products in mul_sparse_by_line_xyz000 (Fp4)
# - 2 products in mul_sparse_by_line_xy000z (Fp4)
# - mul_by_line_xy0 in mul_sparse_by_line_xy00z0 (Fp6)
#
# square2x_disjoint:
# - cyclotomic square in Fp2 -> Fp6 -> Fp12 towering
#   needs Fp4 as special case

func prod2x_disjoint[Fdbl, F](
       r: var QuadraticExt2x[FDbl],
       a: QuadraticExt[F],
       b0, b1: F) =
  ## Return a * (b0, b1) in r
  static: doAssert Fdbl is doublePrec(F)

  var V0 {.noInit.}, V1 {.noInit.}: typeof(r.c0) # Double-precision
  var t0 {.noInit.}, t1 {.noInit.}: typeof(a.c0) # Single-width

  # Require 2 extra bits
  V0.prod2x(a.c0, b0)           # v0 = a0b0
  V1.prod2x(a.c1, b1)           # v1 = a1b1
  when F.has1extraBit():
    t0.sumUnr(a.c0, a.c1)
    t1.sumUnr(b0, b1)
  else:
    t0.sum(a.c0, a.c1)
    t1.sum(b0, b1)

  r.c1.prod2x(t0, t1)           # r1 = (a0 + a1)(b0 + b1)
  r.c1.diff2xMod(r.c1, V0)      # r1 = (a0 + a1)(b0 + b1) - a0b0
  r.c1.diff2xMod(r.c1, V1)      # r1 = (a0 + a1)(b0 + b1) - a0b0 - a1b1

  r.c0.prod2x(V1, NonResidue)   # r0 = β a1 b1
  r.c0.sum2xMod(r.c0, V0)       # r0 = a0 b0 + β a1 b1

func square2x_disjoint[Fdbl, F](
       r: var QuadraticExt2x[FDbl],
       a0, a1: F) =
  ## Return (a0, a1)² in r
  var V0 {.noInit.}, V1 {.noInit.}: typeof(r.c0) # Double-precision
  var t {.noInit.}: F # Single-width

  # TODO: which is the best formulation? 3 squarings or 2 Mul?
  # It seems like the higher the tower the better squarings are
  # So for Fp12 = 2xFp6, prefer squarings.
  V0.square2x(a0)
  V1.square2x(a1)
  t.sum(a0, a1)

  # r0 = a0² + β a1² (option 1) <=> (a0 + a1)(a0 + β a1) - β a0a1 - a0a1 (option 2)
  r.c0.prod2x(V1, NonResidue)
  r.c0.sum2xMod(r.c0, V0)

  # r1 = 2 a0 a1 (option 1) = (a0 + a1)² - a0² - a1² (option 2)
  r.c1.square2x(t)
  r.c1.diff2xMod(r.c1, V0)
  r.c1.diff2xMod(r.c1, V1)

# Dispatch
# ----------------------------------------------------------------------

func prod2x(r: var QuadraticExt2x, a, b: QuadraticExt) =
  mixin fromComplexExtension
  when a.fromComplexExtension():
    r.prod2x_complex(a, b)
  else:
    r.prod2x_disjoint(a, b.c0, b.c1)

func square2x(r: var QuadraticExt2x, a: QuadraticExt) =
  mixin fromComplexExtension
  when a.fromComplexExtension():
    r.square2x_complex(a)
  else:
    r.square2x_disjoint(a.c0, a.c1)

# ############################################################
#                                                            #
#            Cubic extensions - Lazy Reductions              #
#                                                            #
# ############################################################

# Commutative ring implementation for Cubic Extension Fields
# -------------------------------------------------------------------

func square2x_Chung_Hasan_SQR2(r: var CubicExt2x, a: CubicExt) =
  ## Returns r = a²
  var m01{.noInit.}, m12{.noInit.}: typeof(r.c0) # double-width
  var t{.noInit.}: typeof(a.c0)                  # single width

  m01.prod2x(a.c0, a.c1)
  m01.sum2xMod(m01, m01)  # 2a₀a₁
  m12.prod2x(a.c1, a.c2)
  m12.sum2xMod(m12, m12)  # 2a₁a₂
  r.c0.square2x(a.c2)     # borrow r₀ = a₂² for a moment

  # r₂ = (a₀ - a₁ + a₂)²
  t.sum(a.c2, a.c0)
  t -= a.c1
  r.c2.square2x(t)

  # r₂ = (a₀ - a₁ + a₂)² + 2a₀a₁ + 2a₁a₂ - a₂²
  r.c2.sum2xMod(r.c2, m01)
  r.c2.sum2xMod(r.c2, m12)
  r.c2.diff2xMod(r.c2, r.c0)

  # r₁ = 2a₀a₁ + β a₂²
  r.c1.prod2x(r.c0, NonResidue)
  r.c1.sum2xMod(r.c1, m01)

  # r₂ = (a₀ - a₁ + a₂)² + 2a₀a₁ + 2a₁a₂ - a₀² - a₂²
  r.c0.square2x(a.c0)
  r.c2.diff2xMod(r.c2, r.c0)

  # r₀ = a₀² + β 2a₁a₂
  m12.prod2x(m12, NonResidue)
  r.c0.sum2xMod(r.c0, m12)

func prod2x(r: var CubicExt2x, a, b: CubicExt) =
  var V0 {.noInit.}, V1 {.noInit.}, V2 {.noinit.}: typeof(r.c0)
  var t0 {.noInit.}, t1 {.noInit.}: typeof(a.c0)

  # TODO: The delayed reductions are deactivated, they work for all curves
  # except for BN254_Snarks in the FP2 -> Fp4 -> Fp12 towering

  V0.prod2x(a.c0, b.c0)
  V1.prod2x(a.c1, b.c1)
  V2.prod2x(a.c2, b.c2)

  # r₀ = β ((a₁ + a₂)(b₁ + b₂) - v₁ - v₂) + v₀
  when false: # CubicExt.has1extraBit():
    t0.sumUnr(a.c1, a.c2)
    t1.sumUnr(b.c1, b.c2)
  else:
    t0.sum(a.c1, a.c2)
    t1.sum(b.c1, b.c2)
  r.c0.prod2x(t0, t1) # r cannot alias a or b since it's double precision
  r.c0.diff2xMod(r.c0, V1)
  r.c0.diff2xMod(r.c0, V2)
  r.c0.prod2x(r.c0, NonResidue)
  r.c0.sum2xMod(r.c0, V0)

  # r₁ = (a₀ + a₁) * (b₀ + b₁) - v₀ - v₁ + β v₂
  when false: # CubicExt.has1extraBit():
    t0.sumUnr(a.c0, a.c1)
    t1.sumUnr(b.c0, b.c1)
  else:
    t0.sum(a.c0, a.c1)
    t1.sum(b.c0, b.c1)
  r.c1.prod2x(t0, t1)
  r.c1.diff2xMod(r.c1, V0)
  r.c1.diff2xMod(r.c1, V1)
  r.c2.prod2x(V2, NonResidue) # r₂ is unused and cannot alias
  r.c1.sum2xMod(r.c1, r.c2)

  # r₂ = (a₀ + a₂) * (b₀ + b₂) - v₀ - v₂ + v₁
  when false: # CubicExt.has1extraBit():
    t0.sumUnr(a.c0, a.c2)
    t1.sumUnr(b.c0, b.c2)
  else:
    t0.sum(a.c0, a.c2)
    t1.sum(b.c0, b.c2)
  r.c2.prod2x(t0, t1)
  r.c2.diff2xMod(r.c2, V0)
  r.c2.diff2xMod(r.c2, V2)
  r.c2.sum2xMod(r.c2, V1)

# ############################################################
#                                                            #
#                Quadratic extensions                        #
#                                                            #
# ############################################################

# Commutative ring implementation for complex quadratic extension fields
# ----------------------------------------------------------------------

func square_complex(r: var QuadraticExt, a: QuadraticExt) =
  ## Return a² in 𝔽p2 = 𝔽p[𝑖] in ``r``
  ## ``r`` is initialized/overwritten
  ##
  ## Requires a complex extension field
  # (c0, c1)² => (c0 + c1𝑖)²
  #           => c0² + 2 c0 c1𝑖 + (c1𝑖)²
  #           => c0²-c1² + 2 c0 c1𝑖
  #           => (c0²-c1², 2 c0 c1)
  #           or
  #           => ((c0-c1)(c0+c1), 2 c0 c1)
  #           => ((c0-c1)(c0-c1 + 2 c1), c0 * 2 c1)
  #
  # Costs (naive implementation)
  # - 1 Multiplication 𝔽p
  # - 2 Squarings 𝔽p
  # - 1 Doubling 𝔽p
  # - 1 Substraction 𝔽p
  # Stack: 4 * ModulusBitSize (4x 𝔽p element)
  #
  # Or (with 1 less Mul/Squaring at the cost of 1 addition and extra 2 𝔽p stack space)
  #
  # - 2 Multiplications 𝔽p
  # - 1 Addition 𝔽p
  # - 1 Doubling 𝔽p
  # - 1 Substraction 𝔽p
  #
  # To handle aliasing between r and a, we need
  # r to be used only when a is unneeded
  # so we can't use r fields as a temporary
  mixin fromComplexExtension
  static: doAssert r.fromComplexExtension()

  var v0 {.noInit.}, v1 {.noInit.}: typeof(r.c0)
  v0.diff(a.c0, a.c1)    # v0 = c0 - c1               [1 Sub]
  v1.sum(a.c0, a.c1)     # v1 = c0 + c1               [1 Dbl, 1 Sub]
  r.c1.prod(a.c0, a.c1)  # r.c1 = c0 c1               [1 Mul, 1 Dbl, 1 Sub]
  # aliasing: a unneeded now
  r.c1.double()          # r.c1 = 2 c0 c1             [1 Mul, 2 Dbl, 1 Sub]
  r.c0.prod(v0, v1)      # r.c0 = (c0 + c1)(c0 - c1)  [2 Mul, 2 Dbl, 1 Sub]

func prod_complex(r: var QuadraticExt, a, b: QuadraticExt) =
  ## Return a * b in 𝔽p2 = 𝔽p[𝑖] in ``r``
  ## ``r`` is initialized/overwritten
  ##
  ## Requires a complex extension field
  # (a0, a1) (b0, b1) => (a0 + a1𝑖) (b0 + b1𝑖)
  #                   => (a0 b0 - a1 b1) + (a0 b1 + a1 b0) 𝑖
  #
  # In Fp, multiplication has cost O(n²) with n the number of limbs
  # while addition has cost O(3n) (n for addition, n for overflow, n for conditional substraction)
  # and substraction has cost O(2n) (n for substraction + underflow, n for conditional addition)
  #
  # Even for 256-bit primes, we are looking at always a minimum of n=5 limbs (with 2^63 words)
  # where addition/substraction are significantly cheaper than multiplication
  #
  # So we always reframe the imaginary part using Karatsuba approach to save a multiplication
  # (a0, a1) (b0, b1) => (a0 b0 - a1 b1) + 𝑖( (a0 + a1)(b0 + b1) - a0 b0 - a1 b1 )
  #
  # Costs (naive implementation)
  # - 4 Multiplications 𝔽p
  # - 1 Addition 𝔽p
  # - 1 Substraction 𝔽p
  # Stack: 6 * ModulusBitSize (4x 𝔽p element + 2x named temporaries)
  #
  # Costs (Karatsuba)
  # - 3 Multiplications 𝔽p
  # - 3 Substraction 𝔽p (2 are fused)
  # - 2 Addition 𝔽p
  # Stack: 6 * ModulusBitSize (4x 𝔽p element + 2x named temporaries + 1 in-place multiplication temporary)
  mixin fromComplexExtension
  static: doAssert r.fromComplexExtension()

  var a0b0 {.noInit.}, a1b1 {.noInit.}: typeof(r.c0)
  a0b0.prod(a.c0, b.c0)                                         # [1 Mul]
  a1b1.prod(a.c1, b.c1)                                         # [2 Mul]

  r.c0.sum(a.c0, a.c1)  # r0 = (a0 + a1)                        # [2 Mul, 1 Add]
  r.c1.sum(b.c0, b.c1)  # r1 = (b0 + b1)                        # [2 Mul, 2 Add]
  # aliasing: a and b unneeded now
  r.c1 *= r.c0          # r1 = (b0 + b1)(a0 + a1)               # [3 Mul, 2 Add] - 𝔽p temporary

  r.c0.diff(a0b0, a1b1) # r0 = a0 b0 - a1 b1                    # [3 Mul, 2 Add, 1 Sub]
  r.c1 -= a0b0          # r1 = (b0 + b1)(a0 + a1) - a0b0        # [3 Mul, 2 Add, 2 Sub]
  r.c1 -= a1b1          # r1 = (b0 + b1)(a0 + a1) - a0b0 - a1b1 # [3 Mul, 2 Add, 3 Sub]

func mul_sparse_complex_by_0y(
       r: var QuadraticExt, a: QuadraticExt,
       sparseB: auto) =
  ## Multiply `a` by `b` with sparse coordinates (0, y)
  ## On a complex quadratic extension field 𝔽p2 = 𝔽p[𝑖]
  #
  # r0 = a0 b0 - a1 b1
  # r1 = (a0 + a1) (b0 + b1) - a0 b0 - a1 b1 (Karatsuba)
  #
  # with b0 = 0, hence
  #
  # r0 = - a1 b1
  # r1 = (a0 + a1) b1 - a1 b1 = a0 b1
  mixin fromComplexExtension
  static: doAssert r.fromComplexExtension()

  when typeof(sparseB) is typeof(a):
    template b(): untyped = sparseB.c1
  elif typeof(sparseB) is typeof(a.c0):
    template b(): untyped = sparseB
  else:
    {.error: "sparseB type is " & $typeof(sparseB) &
      " which does not match with either a (" & $typeof(a) &
      ") or a.c0 (" & $typeof(a.c0) & ")".}

  var t{.noInit.}: typeof(a.c0)
  t.prod(a.c1, b)
  r.c1.prod(a.c0, b)
  r.c0.neg(t)

# Commutative ring implementation for generic quadratic extension fields
# ----------------------------------------------------------------------

func square_generic(r: var QuadraticExt, a: QuadraticExt) =
  ## Return a² in ``r``
  ## ``r`` is initialized/overwritten
  # Algorithm (with β the non-residue in the base field)
  #
  # (c0, c1)² => (c0 + c1 w)²
  #           => c0² + 2 c0 c1 w + c1²w²
  #           => c0² + β c1² + 2 c0 c1 w
  #           => (c0² + β c1², 2 c0 c1)
  # We have 2 squarings and 1 multiplication in the base field
  # which are significantly more costly than additions.
  # For example when construction 𝔽p12 from 𝔽p6:
  # - 4 limbs like BN254:     multiplication is 20x slower than addition/substraction
  # - 6 limbs like BLS12-381: multiplication is 28x slower than addition/substraction
  #
  # We can save operations with one of the following expressions
  # of c0² + β c1² and noticing that c0c1 is already computed for the "y" coordinate
  #
  # Alternative 1:
  #   c0² + β c1² <=> (c0 - c1)(c0 - β c1) + β c0c1 + c0c1
  #
  # Alternative 2:
  #   c0² + β c1² <=> (c0 + c1)(c0 + β c1) - β c0c1 - c0c1
  #
  # This gives us 2 Mul and 2 mul-nonresidue (which is costly for BN254_Snarks)
  #
  # We can also reframe the 2nd term with only squarings
  # which might be significantly faster on higher tower degrees
  #
  #   2 c0 c1 <=> (a0 + a1)² - a0² - a1²
  #
  # This gives us 3 Sqr and 1 Mul-non-residue
  const costlyMul = block:
    # No shortcutting in the VM :/
    when a.c0 is ExtensionField:
      when a.c0.c0 is ExtensionField:
        true
      else:
        false
    else:
      false

  when QuadraticExt.C == BN254_Snarks or costlyMul:
    var v0 {.noInit.}, v1 {.noInit.}: typeof(r.c0)
    v0.square(a.c0)
    v1.square(a.c1)

    # Aliasing: a unneeded now
    r.c1.sum(a.c0, a.c1)

    # r0 = c0² + β c1²
    r.c0.prod(v1, NonResidue)
    r.c0 += v0

    # r1 = (a0 + a1)² - a0² - a1²
    r.c1.square()
    r.c1 -= v0
    r.c1 -= v1

  else:
    var v0 {.noInit.}, v1 {.noInit.}: typeof(r.c0)

    # v1 <- (c0 + β c1)
    v1.prod(a.c1, NonResidue)
    v1 += a.c0

    # v0 <- (c0 + c1)(c0 + β c1)
    v0.sum(a.c0, a.c1)
    v0 *= v1

    # v1 <- c0 c1
    v1.prod(a.c0, a.c1)

    # aliasing: a unneeded now

    # r0 = (c0 + c1)(c0 + β c1) - c0c1
    v0 -= v1

    # r1 = 2 c0c1
    r.c1.double(v1)

    # r0 = (c0 + c1)(c0 + β c1) - c0c1 - β c0c1
    v1 *= NonResidue
    r.c0.diff(v0, v1)

func prod_generic(r: var QuadraticExt, a, b: QuadraticExt) =
  ## Returns r = a * b
  # Algorithm (with β the non-residue in the base field)
  #
  # r0 = a0 b0 + β a1 b1
  # r1 = (a0 + a1) (b0 + b1) - a0 b0 - a1 b1 (Karatsuba)
  var v0 {.noInit.}, v1 {.noInit.}, v2 {.noInit.}: typeof(r.c0)

  # v2 <- (a0 + a1)(b0 + b1)
  v0.sum(a.c0, a.c1)
  v1.sum(b.c0, b.c1)
  v2.prod(v0, v1)

  # v0 <- a0 b0
  # v1 <- a1 b1
  v0.prod(a.c0, b.c0)
  v1.prod(a.c1, b.c1)

  # aliasing: a and b unneeded now

  # r1 <- (a0 + a1)(b0 + b1) - a0 b0 - a1 b1
  r.c1.diff(v2, v1)
  r.c1 -= v0

  # r0 <- a0 b0 + β a1 b1
  v1 *= NonResidue
  r.c0.sum(v0, v1)

func mul_sparse_generic_by_x0(r: var QuadraticExt, a, sparseB: QuadraticExt) =
  ## Multiply `a` by `b` with sparse coordinates (x, 0)
  ## On a generic quadratic extension field
  # Algorithm (with β the non-residue in the base field)
  #
  # r0 = a0 b0 + β a1 b1
  # r1 = (a0 + a1) (b0 + b1) - a0 b0 - a1 b1 (Karatsuba)
  #
  # with b1 = 0, hence
  #
  # r0 = a0 b0
  # r1 = (a0 + a1) b0 - a0 b0 = a1 b0
  template b(): untyped = sparseB

  r.c0.prod(a.c0, b.c0)
  r.c1.prod(a.c1, b.c0)

func mul_sparse_generic_by_0y(
       r: var QuadraticExt, a: QuadraticExt,
       sparseB: auto) =
  ## Multiply `a` by `b` with sparse coordinates (0, y)
  ## On a generic quadratic extension field
  # Algorithm (with β the non-residue in the base field)
  #
  # r0 = a0 b0 + β a1 b1
  # r1 = (a0 + a1) (b0 + b1) - a0 b0 - a1 b1 (Karatsuba)
  #
  # with b0 = 0, hence
  #
  # r0 = β a1 b1
  # r1 = (a0 + a1) b1 - a1 b1 = a0 b1
  when typeof(sparseB) is typeof(a):
    template b(): untyped = sparseB.c1
  elif typeof(sparseB) is typeof(a.c0):
    template b(): untyped = sparseB
  else:
    {.error: "sparseB type is " & $typeof(sparseB) &
      " which does not match with either a (" & $typeof(a) &
      ") or a.c0 (" & $typeof(a.c0) & ")".}

  var t{.noInit.}: typeof(a.c0)

  t.prod(a.c1, b)
  r.c1.prod(a.c0, b)
  # aliasing: a unneeded now
  r.c0.prod(t, NonResidue)

func mul_sparse_generic_by_0y(
       r: var QuadraticExt, a: QuadraticExt,
       sparseB: static int) =
  ## Multiply `a` by `b` with sparse coordinates (0, y)
  ## On a generic quadratic extension field
  # Algorithm (with β the non-residue in the base field)
  #
  # r0 = a0 b0 + β a1 b1
  # r1 = (a0 + a1) (b0 + b1) - a0 b0 - a1 b1 (Karatsuba)
  #
  # with b0 = 0, hence
  #
  # r0 = β a1 b1
  # r1 = (a0 + a1) b1 - a1 b1 = a0 b1
  template b(): untyped = sparseB

  var t{.noInit.}: typeof(a.c0)

  t.prod(a.c1, b)
  r.c1.prod(a.c0, b)
  # aliasing: a unneeded now
  r.c0.prod(t, NonResidue)

func invImpl(r: var QuadraticExt, a: QuadraticExt) =
  ## Compute the multiplicative inverse of ``a``
  ##
  ## The inverse of 0 is 0.
  #
  # Algorithm:
  #
  # 1 / (a0 + a1 w) <=> (a0 - a1 w) / (a0 + a1 w)(a0 - a1 w)
  #                 <=> (a0 - a1 w) / (a0² - a1² w²)
  # with w being our coordinate system and β the quadratic non-residue
  # we have w² = β
  # So the inverse is (a0 - a1 w) / (a0² - β a1²)
  mixin fromComplexExtension

  # [2 Sqr, 1 Add]
  var v0 {.noInit.}, v1 {.noInit.}: typeof(r.c0)
  v0.square(a.c0)
  v1.square(a.c1)
  when r.fromComplexExtension():
    v0 += v1
  else:
    v1 *= NonResidue
    v0 -= v1              # v0 = a0² - β a1² (the norm / squared magnitude of a)

  # [1 Inv, 2 Sqr, 1 Add]
  v1.inv(v0)              # v1 = 1 / (a0² - β a1²)

  # [1 Inv, 2 Mul, 2 Sqr, 1 Add, 1 Neg]
  r.c0.prod(a.c0, v1)     # r0 = a0 / (a0² - β a1²)
  v0.neg(v1)              # v0 = -1 / (a0² - β a1²)
  r.c1.prod(a.c1, v0)     # r1 = -a1 / (a0² - β a1²)

# Exported quadratic symbols
# -------------------------------------------------------------------

func square*(r: var QuadraticExt, a: QuadraticExt) =
  mixin fromComplexExtension
  when r.fromComplexExtension():
    when true:
      r.square_complex(a)
    else: # slower
      var d {.noInit.}: doublePrec(typeof(r))
      d.square2x_complex(a)
      r.c0.redc2x(d.c0)
      r.c1.redc2x(d.c1)
  else:
    when true: # r.typeof.F.C in {BLS12_377, BW6_761}:
      # BW6-761 requires too many registers for Dbl width path
      r.square_generic(a)
    else:
      # TODO understand why Fp4[BLS12_377]
      # is so slow in the branch
      # TODO:
      # - On Fp4, we can have a.c0.c0 off by p
      #   a reduction is missing
      var d {.noInit.}: doublePrec(typeof(r))
      d.square2x_disjoint(a.c0, a.c1)
      r.c0.redc2x(d.c0)
      r.c1.redc2x(d.c1)

func prod*(r: var QuadraticExt, a, b: QuadraticExt) =
  mixin fromComplexExtension
  when r.fromComplexExtension():
    when false:
      r.prod_complex(a, b)
    else: # faster
      var d {.noInit.}: doublePrec(typeof(r))
      d.prod2x_complex(a, b)
      r.c0.redc2x(d.c0)
      r.c1.redc2x(d.c1)
  else:
    when r.typeof.F.C == BW6_761 or typeof(r.c0) is Fp:
      # BW6-761 requires too many registers for Dbl width path
      r.prod_generic(a, b)
    else:
      var d {.noInit.}: doublePrec(typeof(r))
      d.prod2x_disjoint(a, b.c0, b.c1)
      r.c0.redc2x(d.c0)
      r.c1.redc2x(d.c1)

{.push inline.}

func inv*(r: var QuadraticExt, a: QuadraticExt) =
  ## Compute the multiplicative inverse of ``a``
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  r.invImpl(a)

func inv*(a: var QuadraticExt) =
  ## Compute the multiplicative inverse of ``a``
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  a.invImpl(a)

func `*=`*(a: var QuadraticExt, b: QuadraticExt) =
  ## In-place multiplication
  a.prod(a, b)

func square*(a: var QuadraticExt) =
  ## In-place squaring
  a.square(a)

func mul_sparse_by_0y*(r: var QuadraticExt, a: QuadraticExt, sparseB: auto) =
  ## Sparse multiplication
  mixin fromComplexExtension
  when a.fromComplexExtension():
    r.mul_sparse_complex_by_0y(a, sparseB)
  else:
    r.mul_sparse_generic_by_0y(a, sparseB)

func mul_sparse_by_0y*(r: var QuadraticExt, a: QuadraticExt, sparseB: static int) =
  ## Sparse multiplication
  mixin fromComplexExtension
  when a.fromComplexExtension():
    {.error: "Not implemented.".}
  else:
    r.mul_sparse_generic_by_0y(a, sparseB)

func mul_sparse_by_0y*(a: var QuadraticExt, sparseB: auto) =
  ## Sparse in-place multiplication
  a.mul_sparse_by_0y(a, sparseB)

func mul_sparse_by_x0*(a: var QuadraticExt, sparseB: QuadraticExt) =
  ## Sparse in-place multiplication
  a.mul_sparse_generic_by_x0(a, sparseB)

{.pop.} # inline

# ############################################################
#                                                            #
#                    Cubic extensions                        #
#                                                            #
# ############################################################

# Commutative ring implementation for Cubic Extension Fields
# -------------------------------------------------------------------
# Cubic extensions can use specific squaring procedures
# beyond Schoolbook and Karatsuba:
# - Chung-Hasan (3 different algorithms)
# - Toom-Cook-3x
#
# Chung-Hasan papers
# http://cacr.uwaterloo.ca/techreports/2006/cacr2006-24.pdf
# https://www.lirmm.fr/arith18/papers/Chung-Squaring.pdf
#
# The papers focus on polynomial squaring, they have been adapted
# to towered extension fields with the relevant costs in
#
# - Multiplication and Squaring on Pairing-Friendly Fields
#   Augusto Jun Devegili and Colm Ó hÉigeartaigh and Michael Scott and Ricardo Dahab, 2006
#   https://eprint.iacr.org/2006/471
#
# Costs in the underlying field
# M: Mul, S: Square, A: Add/Sub, B: Mul by non-residue
#
# | Method      | > Linear | Linear            |
# |-------------|----------|-------------------|
# | Schoolbook  | 3M + 3S  | 6A + 2B           |
# | Karatsuba   | 6S       | 13A + 2B          |
# | Tom-Cook-3x | 5S       | 33A + 2B          |
# | CH-SQR1     | 3M + 2S  | 11A + 2B          |
# | CH-SQR2     | 2M + 3S  | 10A + 2B          |
# | CH-SQR3     | 1M + 4S  | 11A + 2B + 1 Div2 |
# | CH-SQR3x    | 1M + 4S  | 14A + 2B          |

func square_Chung_Hasan_SQR2(r: var CubicExt, a: CubicExt) {.used.}=
  ## Returns r = a²
  var s0{.noInit.}, m01{.noInit.}, m12{.noInit.}: typeof(r.c0)

  # precomputations that use a
  m01.prod(a.c0, a.c1)
  m01.double()
  m12.prod(a.c1, a.c2)
  m12.double()
  s0.square(a.c2)
  # aliasing: a₂ unused

  # r₂ = (a₀ - a₁ + a₂)²
  r.c2.sum(a.c2, a.c0)
  r.c2 -= a.c1
  r.c2.square()
  # aliasing, a almost unneeded now

  # r₂ = (a₀ - a₁ + a₂)² + 2a₀a₁ + 2a₁a₂ - a₂²
  r.c2 += m01
  r.c2 += m12
  r.c2 -= s0

  # r₁ = 2a₀a₁ + β a₂²
  r.c1.prod(s0, NonResidue)
  r.c1 += m01

  # r₂ = (a₀ - a₁ + a₂)² + 2a₀a₁ + 2a₁a₂ - a₀² - a₂²
  s0.square(a.c0)
  r.c2 -= s0

  # r₀ = a₀² + β 2a₁a₂
  r.c0.prod(m12, NonResidue)
  r.c0 += s0

func square_Chung_Hasan_SQR3(r: var CubicExt, a: CubicExt) =
  ## Returns r = a²
  var s0{.noInit.}, t{.noInit.}, m12{.noInit.}: typeof(r.c0)

  # s₀ = (a₀ + a₁ + a₂)²
  # t = ((a₀ + a₁ + a₂)² + (a₀ - a₁ + a₂)²) / 2
  s0.sum(a.c0, a.c2)
  t.diff(s0, a.c1)
  s0 += a.c1
  s0.square()
  t.square()
  t += s0
  t.div2()

  # m12 = 2a₁a₂ and r₁ = a₂²
  # then a₁ and a₂ are unused for aliasing
  m12.prod(a.c1, a.c2)
  m12.double()
  r.c1.square(a.c2)       # r₁ = a₂²

  r.c2.diff(t, r.c1)      # r₂ = t - a₂²
  r.c1 *= NonResidue      # r₁ = β a₂²
  r.c1 += s0              # r₁ = (a₀ + a₁ + a₂)² + β a₂²
  r.c1 -= m12             # r₁ = (a₀ + a₁ + a₂)² - 2a₁a₂ + β a₂²
  r.c1 -= t               # r₁ = (a₀ + a₁ + a₂)² - 2a₁a₂ - t + β a₂²

  s0.square(a.c0)
  # aliasing: a₀ unused

  r.c2 -= s0
  r.c0.prod(m12, NonResidue)
  r.c0 += s0

func prodImpl(r: var CubicExt, a, b: CubicExt) =
  ## Returns r = a * b  # Algorithm is Karatsuba
  var v0{.noInit.}, v1{.noInit.}, v2{.noInit.}: typeof(r.c0)
  var t0{.noInit.}, t1{.noInit.}, t2{.noInit.}: typeof(r.c0)

  v0.prod(a.c0, b.c0)
  v1.prod(a.c1, b.c1)
  v2.prod(a.c2, b.c2)

  # r₀ = β ((a₁ + a₂)(b₁ + b₂) - v₁ - v₂) + v₀
  t0.sum(a.c1, a.c2)
  t1.sum(b.c1, b.c2)
  t0 *= t1
  t0 -= v1
  t0 -= v2
  t0 *= NonResidue
  # r₀ = t₀ + v₀ at the end to handle aliasing

  # r₁ = (a₀ + a₁) * (b₀ + b₁) - v₀ - v₁ + β v₂
  t1.sum(a.c0, a.c1)
  t2.sum(b.c0, b.c1)
  r.c1.prod(t1, t2)
  r.c1 -= v0
  r.c1 -= v1
  t1.prod(v2, NonResidue)
  r.c1 += t1

  # r₂ = (a₀ + a₂) * (b₀ + b₂) - v₀ - v₂ + v₁
  t1.sum(a.c0, a.c2)
  t2.sum(b.c0, b.c2)
  r.c2.prod(t1, t2)
  r.c2 -= v0
  r.c2 -= v2
  r.c2 += v1

  # Finish r₀
  r.c0.sum(t0, v0)

func invImpl(r: var CubicExt, a: CubicExt) =
  ## Compute the multiplicative inverse of ``a``
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  #
  # Algorithm 5.23
  #
  # Arithmetic of Finite Fields
  # Chapter 5 of Guide to Pairing-Based Cryptography
  # Jean Luc Beuchat, Luis J. Dominguez Perez, Sylvain Duquesne, Nadia El Mrabet, Laura Fuentes-Castañeda, Francisco Rodríguez-Henríquez, 2017\
  # https://www.researchgate.net/publication/319538235_Arithmetic_of_Finite_Fields
  #
  # We optimize for stack usage and use 4 temporaries
  # instead of 9, because 4 * 2 (𝔽p2) * Bitsize would be:
  # - ~2032 bits for BN254
  # - ~3048 bits for BLS12-381
  var A {.noInit.}, B {.noInit.}, C {.noInit.}: typeof(r.c0)
  var t {.noInit.}: typeof(r.c0)

  # A <- a₀² - β a₁ a₂
  A.square(a.c0)
  t.prod(a.c1, a.c2)
  t *= NonResidue
  A -= t

  # B <- β a₂² - a₀ a₁
  B.square(a.c2)
  B *= NonResidue
  t.prod(a.c0, a.c1)
  B -= t

  # C <- a₁² - a₀ a₂
  C.square(a.c1)
  t.prod(a.c0, a.c2)
  C -= t

  # F in t
  # F <- β a₁ C + a₀ A + β a₂ B
  t.prod(a.c1, C)
  r.c2.prod(a.c2, B) # aliasing: last use of a₂, destroy r₂
  t += r.c2
  t *= NonResidue
  r.c0.prod(a.c0, A) # aliasing: last use of a₀, destroy r₀
  t += r.c0

  t.inv()

  # (a0 + a1 v + a2 v²)^-1 = (A + B v + C v²) / F
  r.c0.prod(A, t)
  r.c1.prod(B, t)
  r.c2.prod(C, t)

# Exported cubic symbols
# -------------------------------------------------------------------
{.push inline.}

func square*(r: var CubicExt, a: CubicExt) =
  ## Returns r = a²
  when CubicExt.F.C == BW6_761 or    # Too large
       CubicExt.F.C == BN254_Snarks: # 50 cycles slower on Fp2->Fp4->Fp1é towering
    square_Chung_Hasan_SQR3(r, a)
  else:
    var d {.noInit.}: doublePrec(typeof(a))
    d.square2x_Chung_Hasan_SQR2(a)
    r.c0.redc2x(d.c0)
    r.c1.redc2x(d.c1)
    r.c2.redc2x(d.c2)

func square*(a: var CubicExt) =
  ## In-place squaring
  a.square(a)

func prod*(r: var CubicExt, a, b: CubicExt) =
  ## In-place multiplication
  when CubicExt.F.C == BW6_761: # Too large
    r.prodImpl(a, b)
  else:
    var d {.noInit.}: doublePrec(typeof(r))
    d.prod2x(a, b)
    r.c0.redc2x(d.c0)
    r.c1.redc2x(d.c1)
    r.c2.redc2x(d.c2)

func `*=`*(a: var CubicExt, b: CubicExt) =
  ## In-place multiplication
  when CubicExt.F.C == BW6_761: # Too large
    a.prodImpl(a, b)
  else:
    var d {.noInit.}: doublePrec(typeof(a))
    d.prod2x(a, b)
    a.c0.redc2x(d.c0)
    a.c1.redc2x(d.c1)
    a.c2.redc2x(d.c2)

func inv*(r: var CubicExt, a: CubicExt) =
  ## Compute the multiplicative inverse of ``a``
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  r.invImpl(a)

func inv*(a: var CubicExt) =
  ## Compute the multiplicative inverse of ``a``
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  a.invImpl(a)

{.pop.} # inline
{.pop.} # raises no exceptions
