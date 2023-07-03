# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/abstractions,
  ../config/curves,
  ../arithmetic,
  ../io/io_fields

export Fp

when UseASM_X86_64:
  import
    ./assembly/fp2_asm_x86_adx_bmi2

# Note: to avoid burdening the Nim compiler, we rely on generic extension
# to complain if the base field procedures don't exist

# No exceptions allowed
{.push raises: [].}

# ############################################################
#                                                            #
#                    Extension Fields                        #
#                                                            #
# ############################################################
{.push inline.}

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

  Fp2*[C: static Curve] =
    QuadraticExt[Fp[C]]

  Fp4*[C: static Curve] =
    QuadraticExt[Fp2[C]]

  Fp6*[C: static Curve] =
    CubicExt[Fp2[C]]

  Fp12*[C: static Curve] =
    CubicExt[Fp4[C]]
    # QuadraticExt[Fp6[C]]

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
  Mod(E.F.C)

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

func setMinusOne*(a: var ExtensionField) =
  ## Set ``a`` to -1 in the extension field
  a.coords[0].setMinusOne()
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

func csetZero*(a: var ExtensionField, ctl: SecretBool) =
  ## Set ``a`` to 0 if ``ctl`` is true
  staticFor i, 0, a.coords.len:
    a.coords[i].csetZero(ctl)

func csetOne*(a: var ExtensionField, ctl: SecretBool) =
  ## Set ``a`` to 1 if ``ctl`` is true
  a.coords[0].csetOne(ctl)
  staticFor i, 1, a.coords.len:
    a.coords[i].csetZero(ctl)

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

# Multiplication by an Fp element
# -------------------------------------------------------------------

func `*=`*(a: var ExtensionField, b: Fp) =
  ## Multiply an element of Fp2 by an element of Fp
  for i in 0 ..< a.coords.len:
    a.coords[i] *= b

{.pop.} # inline

# ############################################################
#                                                            #
#              Lazy reduced extension fields                 #
#                                                            #
# ############################################################
{.push inline.}

type
  QuadraticExt2x*[F] = object
    ## Quadratic Extension field for lazy reduced fields
    coords*: array[2, F]

  CubicExt2x*[F] = object
    ## Cubic Extension field for lazy reduced fields
    coords*: array[3, F]

  ExtensionField2x*[F] = QuadraticExt2x[F] or CubicExt2x[F]

template doublePrec*(T: type ExtensionField): type =
  # For now naive unrolling, recursive template don't match
  # and I don't want to deal with types in macros
  when T is QuadraticExt:
    when T.F is QuadraticExt: # Fp4Dbl
      QuadraticExt2x[QuadraticExt2x[doublePrec(T.F.F)]]
    elif T.F is CubicExt:
      when T.F.F is QuadraticExt: # Fp12 over Fp6 over Fp2
        QuadraticExt2x[CubicExt2x[QuadraticExt2x[doublePrec(T.F.F.F)]]]
    elif T.F is Fp:           # Fp2Dbl
      QuadraticExt2x[doublePrec(T.F)]
  elif T is CubicExt:
    when T.F is QuadraticExt: #
      when T.F.F is QuadraticExt: # Fp12 over Fp4 over Fp2
        CubicExt2x[QuadraticExt2x[QuadraticExt2x[doublePrec(T.F.F.F)]]]
      elif T.F.F is Fp: # Fp6
        CubicExt2x[QuadraticExt2x[doublePrec(T.F.F)]]

func has1extraBit*(F: type Fp): bool =
  ## We construct extensions only on Fp (and not Fr)
  getSpareBits(F) >= 1

func has2extraBits*(F: type Fp): bool =
  ## We construct extensions only on Fp (and not Fr)
  getSpareBits(F) >= 2

func has1extraBit*(E: type ExtensionField): bool =
  ## We construct extensions only on Fp (and not Fr)
  getSpareBits(Fp[E.F.C]) >= 1

func has2extraBits*(E: type ExtensionField): bool =
  ## We construct extensions only on Fp (and not Fr)
  getSpareBits(Fp[E.F.C]) >= 2

template C(E: type ExtensionField2x): Curve =
  E.F.C

template c0*(a: ExtensionField2x): auto =
  a.coords[0]
template c1*(a: ExtensionField2x): auto =
  a.coords[1]
template c2*(a: CubicExt2x): auto =
  a.coords[2]

template `c0=`*(a: var ExtensionField2x, v: auto) =
  a.coords[0] = v
template `c1=`*(a: var ExtensionField2x, v: auto) =
  a.coords[1] = v
template `c2=`*(a: var CubicExt2x, v: auto) =
  a.coords[2] = v

# Initialization
# -------------------------------------------------------------------

func setZero*(a: var ExtensionField2x) =
  ## Set ``a`` to 0 in the extension field
  staticFor i, 0, a.coords.len:
    a.coords[i].setZero()

# Abelian group
# -------------------------------------------------------------------

func sumUnr*(r: var ExtensionField, a, b: ExtensionField) =
  ## Sum ``a`` and ``b`` into ``r``
  staticFor i, 0, a.coords.len:
    r.coords[i].sumUnr(a.coords[i], b.coords[i])

func diff2xUnr*(r: var ExtensionField2x, a, b: ExtensionField2x) =
  ## Double-precision substraction without reduction
  staticFor i, 0, a.coords.len:
    r.coords[i].diff2xUnr(a.coords[i], b.coords[i])

func diff2xMod*(r: var ExtensionField2x, a, b: ExtensionField2x) =
  ## Double-precision modular substraction
  staticFor i, 0, a.coords.len:
    r.coords[i].diff2xMod(a.coords[i], b.coords[i])

func sum2xUnr*(r: var ExtensionField2x, a, b: ExtensionField2x) =
  ## Double-precision addition without reduction
  staticFor i, 0, a.coords.len:
    r.coords[i].sum2xUnr(a.coords[i], b.coords[i])

func sum2xMod*(r: var ExtensionField2x, a, b: ExtensionField2x) =
  ## Double-precision modular addition
  staticFor i, 0, a.coords.len:
    r.coords[i].sum2xMod(a.coords[i], b.coords[i])

func neg2xMod*(r: var ExtensionField2x, a: ExtensionField2x) =
  ## Double-precision modular negation
  staticFor i, 0, a.coords.len:
    r.coords[i].neg2xMod(a.coords[i], b.coords[i])

# Reductions
# -------------------------------------------------------------------

func redc2x*(r: var ExtensionField, a: ExtensionField2x) =
  ## Reduction
  staticFor i, 0, a.coords.len:
    r.coords[i].redc2x(a.coords[i])

# Multiplication by a small integer known at compile-time
# -------------------------------------------------------------------

func prod2x*(r: var ExtensionField2x, a: ExtensionField2x, b: static int) =
  ## Multiplication by a small integer known at compile-time
  staticFor i, 0, a.coords.len:
    r.coords[i].prod2x(a.coords[i], b)

{.pop.} # inline

# ############################################################
#                                                            #
#                        Non-Residues                        #
#                                                            #
# ############################################################
{.push inline.}

# 𝔽p
# ----------------------------------------------------------------

func `*=`*(a: var Fp, _: type NonResidue) =
  ## Multiply an element of 𝔽p by the quadratic non-residue
  ## chosen to construct 𝔽p2
  static: doAssert Fp.C.getNonResidueFp() != -1, "𝔽p2 should be specialized for complex extension"
  a *= Fp.C.getNonResidueFp()

func prod*(r: var Fp, a: Fp, _: type NonResidue) =
  ## Multiply an element of 𝔽p by the quadratic non-residue
  ## chosen to construct 𝔽p2
  static: doAssert Fp.C.getNonResidueFp() != -1, "𝔽p2 should be specialized for complex extension"
  r.prod(a, Fp.C.getNonResidueFp())

func prod2x(r: var FpDbl, a: FpDbl, _: type NonResidue) =
  ## Multiply an element of 𝔽p by the quadratic non-residue
  ## chosen to construct 𝔽p2
  static: doAssert FpDbl.C.getNonResidueFp() != -1, "𝔽p2 should be specialized for complex extension"
  r.prod2x(a, FpDbl.C.getNonResidueFp())

# 𝔽p2
# ----------------------------------------------------------------

template fromComplexExtension*[F](elem: QuadraticExt[F]): static bool =
  ## Returns true if the input is a complex extension
  ## i.e. the irreducible polynomial chosen is
  ##   x² - µ with µ = -1
  ## and so 𝔽p2 = 𝔽p[x] / x² - µ = 𝔽p[𝑖]
  when F is Fp and F.C.getNonResidueFp() == -1:
    true
  else:
    false

func prod*[C: static Curve](
       r: var Fp2[C],
       a: Fp2[C],
       _: type NonResidue) =
  ## Multiply an element of 𝔽p2 by the non-residue
  ## chosen to construct the next extension or the twist:
  ## - if quadratic non-residue: 𝔽p4
  ## - if cubic non-residue: 𝔽p6
  ## - if sextic non-residue: 𝔽p4, 𝔽p6 or 𝔽p12
  # Yet another const tuple unpacking bug
  const u = C.getNonResidueFp2()[0]
  const v = C.getNonResidueFp2()[1]
  const Beta {.used.} = C.getNonResidueFp()
  # ξ = u + v x
  # and x² = β
  #
  # (c0 + c1 x) (u + v x) => u c0 + (u c0 + u c1)x + v c1 x²
  #                       => u c0 + β v c1 + (v c0 + u c1) x
  when a.fromComplexExtension() and u == 1 and v == 1:
    let t {.noInit.} = a.c0
    r.c0.diff(t, a.c1)
    r.c1.sum(t, a.c1)
  else:
    # Case:
    # - BN254_Snarks, QNR_Fp: -1, SNR_Fp2: 9+1𝑖  (𝑖 = √-1)
    # - BLS12_377, QNR_Fp: -5, SNR_Fp2: 0+1j    (j = √-5)
    # - BW6_761, SNR_Fp: -4, CNR_Fp2: 0+1j      (j = √-4)
    when u == 0:
      # BLS12_377 and BW6_761, use small addition chain
      r.mul_sparse_by_0y(a, v)
    else:
      # BN254_Snarks, u = 9, v = 1, β = -1
      # Even with u = 9, the 2x9 addition chains (8 additions total)
      # are cheaper than full Fp2 multiplication
      var t {.noInit.}: typeof(a.c0)

      t.prod(a.c0, u)
      when v == 1 and Beta == -1: # Case BN254_Snarks
        t -= a.c1                 # r0 = u c0 + β v c1
      else:
        {.error: "Unimplemented".}

      r.c1.prod(a.c1, u)
      when v == 1:                # r1 = v c0 + u c1
        r.c1 += a.c0
        # aliasing: a.c0 is unused
        r.c0 = t
      else:
        {.error: "Unimplemented".}

func `*=`*[C: static Curve](a: var Fp2[C], _: type NonResidue) =
  ## Multiply an element of 𝔽p2 by the non-residue
  ## chosen to construct the next extension or the twist:
  ## - if quadratic non-residue: 𝔽p4
  ## - if cubic non-residue: 𝔽p6
  ## - if sextic non-residue: 𝔽p4, 𝔽p6 or 𝔽p12
  a.prod(a, NonResidue)

func prod2x*[C: static Curve](
       r: var QuadraticExt2x[FpDbl[C]],
       a: QuadraticExt2x[FpDbl[C]],
       _: type NonResidue) =
  ## Multiplication by non-residue
  const complex = C.getNonResidueFp() == -1
  const U = C.getNonResidueFp2()[0]
  const V = C.getNonResidueFp2()[1]
  const Beta {.used.} = C.getNonResidueFp()

  when complex and U == 1 and V == 1:
    let a1 {.noInit.} = a.c1
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

func `/=`*[C: static Curve](a: var Fp2[C], _: type NonResidue) =
  ## Divide an element of 𝔽p by the non-residue
  ## chosen to construct the next extension or the twist:
  ## - if quadratic non-residue: 𝔽p4
  ## - if cubic non-residue: 𝔽p6
  ## - if sextic non-residue: 𝔽p4, 𝔽p6 or 𝔽p12

  # Yet another const tuple unpacking bug
  const u = C.getNonresidueFp2()[0] # Sextic non-residue to construct 𝔽p12
  const v = C.getNonresidueFp2()[1]
  const Beta = C.getNonResidueFp()  # Quadratic non-residue to construct 𝔽p2
  # ξ = u + v x
  # and x² = β
  #
  # (c0 + c1 x) / (u + v x) => (c0 + c1 x)(u - v x) / ((u + vx)(u-vx))
  #                         => u c0 - v c1 x² + (u c1 - v c0) x / (u² - x²v²)
  #                         => 1/(u² - βv²) * (uc0 - β v c1, u c1 - v c0)
  # With β = 𝑖 = √-1
  #   1/(u² + v²) * (u c0 + v c1, u c1 - v c0)
  #
  # With β = 𝑖 = √-1 and ξ = 1 + 𝑖
  #   1/2 * (c0 + c1, c1 - c0)

  when a.fromComplexExtension() and u == 1 and v == 1:
    let t {.noInit.} = a.c0
    a.c0 += a.c1
    a.c1 -= t
    a.div2()
  else:
    var a0 {.noInit.} = a.c0
    let a1 {.noInit.} = a.c1
    const u2v2 = u*u - Beta*v*v # (u² - βv²)
    # TODO can be precomputed to avoid costly inversion.
    var u2v2inv {.noInit.}: a.c0.typeof
    u2v2inv.fromUint(u2v2)
    u2v2inv.inv()

    a.c0 *= u
    a.c1 *= Beta * v
    a.c0 -= a.c1

    a.c1 = a1
    a.c1 *= u
    a0 *= v
    a.c1 -= a0
    a.c0 *= u2v2inv
    a.c1 *= u2v2inv

# Quadratic extensions
# ----------------------------------------------------------------

func prod*(r: var QuadraticExt, a: QuadraticExt, _: type NonResidue) =
  ## Multiplication by non-residue.
  ##
  ## For example is a is an element of 𝔽p4
  ## it is multiplied by the non-residue
  ## chosen to construct the next extension or the twist:
  ## - if quadratic non-residue: 𝔽p8
  ## - if cubic non-residue: 𝔽p12
  ## - if sextic non-residue: 𝔽p8, 𝔽p12 or 𝔽p24
  ##
  ## Assumes that the non-residue is sqrt(lower extension non-residue)
  let t {.noInit.} = a.c0
  r.c0.prod(a.c1, NonResidue)
  r.c1 = t

func `*=`*(a: var QuadraticExt, _: type NonResidue) =
  ## Multiplication by non-residue
  ##
  ## For example is `a` is an element of 𝔽p4
  ## it is multiplied by the non-residue
  ## chosen to construct the next extension or the twist:
  ## - if quadratic non-residue: 𝔽p8
  ## - if cubic non-residue: 𝔽p12
  ## - if sextic non-residue: 𝔽p8, 𝔽p12 or 𝔽p24
  ##
  ## Assumes that the non-residue is sqrt(lower extension non-residue)
  a.prod(a, NonResidue)

func prod2x*(
       r: var QuadraticExt2x,
       a: QuadraticExt2x,
       _: type NonResidue) =
  ## Multiplication by non-residue
  static: doAssert not(r.c0 is FpDbl), "Wrong dispatch, there is a specific non-residue multiplication for the base extension."
  let t {.noInit.} = a.c0
  r.c0.prod2x(a.c1, NonResidue)
  `=`(r.c1, t) # "r.c1 = t", is refused by the compiler.

# Cubic extensions
# ----------------------------------------------------------------

func prod*(r: var CubicExt, a: CubicExt, _: type NonResidue) =
  ## Multiplication by non-residue.
  ##
  ## For example is `a` is an element of 𝔽p6
  ## it is multiplied by the non-residue
  ## chosen to construct the next extension or the twist:
  ## - if quadratic non-residue: 𝔽p12
  ## - if cubic non-residue: 𝔽p18
  ## - if sextic non-residue: 𝔽p12, 𝔽p18 or 𝔽p36
  ##
  ## Assumes that the non-residue is cube_root(lower extension non-residue)
  ##
  ## For all curves γ = v with v the factor for the cubic extension coordinate
  ## and v³ = ξ
  ## (c0 + c1 v + c2 v²) v => ξ c2 + c0 v + c1 v²
  let t {.noInit.} = a.c2
  r.c2 = a.c1
  r.c1 = a.c0
  r.c0.prod(t, NonResidue)

func `*=`*(a: var CubicExt, _: type NonResidue) {.inline.} =
  ## Multiply an element of 𝔽p6 by the non-residue
  ## chosen to construct the next extension or the twist:
  ## - if quadratic non-residue: 𝔽p12
  ## - if cubic non-residue: 𝔽p18
  ## - if sextic non-residue: 𝔽p12, 𝔽p18 or 𝔽p36
  ##
  ## Assumes that it is cube_root(NonResidue_Fp2)
  ##
  ## For all curves γ = v with v the factor for the cubic extension coordinate
  ## and v³ = ξ
  ## (c0 + c1 v + c2 v²) v => ξ c2 + c0 v + c1 v²
  a.prod(a, NonResidue)

func prod2x*(
       r: var CubicExt2x,
       a: CubicExt2x,
       _: type NonResidue) {.inline.} =
  ## Multiplication by non-residue
  ## For all curves γ = v with v the factor for cubic extension coordinate
  ## and v³ = ξ
  ## (c0 + c1 v + c2 v²) v => ξ c2 + c0 v + c1 v²
  let t {.noInit.} = a.c2
  r.c2 = a.c1
  r.c1 = a.c0
  r.c0.prod2x(t, NonResidue)

{.pop.} # inline

# ############################################################
#                                                            #
#                     Cost functions                         #
#                                                            #
# ############################################################

func prefer_3sqr_over_2mul(F: type ExtensionField): bool {.compileTime.} =
  ## Returns true
  ## if time(3sqr) < time(2mul) in the extension fields

  let a = default(F)
  # No shortcut in the VM
  when a.c0 is Fp12:
    # Benchmarked on BLS12-381
    when a.c0.c0 is Fp6:
      return true
    elif a.c0.c0 is Fp4:
      return false
    else: return false
  else: return false

func has_large_NR_norm(C: static Curve): bool =
  ## Returns true if the non-residue of the extension fields
  ## has a large norm

  const j = C.getNonResidueFp()
  const u = C.getNonResidueFp2()[0]
  const v = C.getNonResidueFp2()[1]

  const norm2 = u*u + (j*v)*(j*v)

  # Compute integer square root
  var norm = 0
  while (norm+1) * (norm+1) <= norm2:
    norm += 1

  return norm > 5

func has_large_field_elem*(C: static Curve): bool =
  ## Returns true if field element are large
  ## and necessitate custom routine for assembly in particular
  let a = default(Fp[C])
  return a.mres.limbs.len > 6

# ############################################################
#                                                            #
#                  Quadratic extensions                      #
#                                                            #
# ############################################################

# Forward declarations
# ----------------------------------------------------------------------

func prod2x*(r: var QuadraticExt2x, a, b: QuadraticExt)
func square2x*(r: var QuadraticExt2x, a: QuadraticExt)

# Complex squarings
# ----------------------------------------------------------------------

func square_complex(r: var Fp2, a: Fp2) =
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
  static: doAssert r.fromComplexExtension()

  var v0 {.noInit.}, v1 {.noInit.}: typeof(r.c0)
  v0.diff(a.c0, a.c1)    # v0 = c0 - c1               [1 Sub]
  v1.sum(a.c0, a.c1)     # v1 = c0 + c1               [1 Dbl, 1 Sub]
  r.c1.prod(a.c0, a.c1)  # r.c1 = c0 c1               [1 Mul, 1 Dbl, 1 Sub]
  # aliasing: a unneeded now
  r.c1.double()          # r.c1 = 2 c0 c1             [1 Mul, 2 Dbl, 1 Sub]
  r.c0.prod(v0, v1)      # r.c0 = (c0 + c1)(c0 - c1)  [2 Mul, 2 Dbl, 1 Sub]

func square2x_complex(r: var QuadraticExt2x, a: Fp2) =
  ## Double-precision unreduced complex squaring
  static: doAssert a.fromComplexExtension()

  var t0 {.noInit.}, t1 {.noInit.}: typeof(a.c0)

  when Fp2.has1extraBit():
    t0.sumUnr(a.c1, a.c1)
    t1.sumUnr(a.c0, a.c1)
  else:
    t0.double(a.c1)
    t1.sum(a.c0, a.c1)

  r.c1.prod2x(t0, a.c0)     # r1 = 2a0a1
  t0.diff(a.c0, a.c1)
  r.c0.prod2x(t0, t1)       # r0 = (a0 + a1)(a0 - a1)

# Complex multiplications
# ----------------------------------------------------------------------

func prod_complex(r: var Fp2, a, b: Fp2) {.used.} =
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
  # Hence we can consider using q Karatsuba approach to save a multiplication
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
  static: doAssert r.fromComplexExtension()
  var t {.noInit.}: typeof(r)
  var na1 {.noInit.}: typeof(r.c0)
  na1.neg(a.c1)
  t.c0.sumprod([a.c0, na1], [b.c0, b.c1])
  t.c1.sumprod([a.c0, a.c1], [b.c1, b.c0])
  r = t

func prod2x_complex(r: var QuadraticExt2x, a, b: Fp2) =
  ## Double-precision unreduced complex multiplication
  # r and a or b cannot alias
  static: doAssert a.fromComplexExtension()

  var D {.noInit.}: typeof(r.c0)
  var t0 {.noInit.}, t1 {.noInit.}: typeof(a.c0)

  when Fp2.has1extraBit():
    t0.sumUnr(a.c0, a.c1)
    t1.sumUnr(b.c0, b.c1)
  else:
    t0.sum(a.c0, a.c1)
    t1.sum(b.c0, b.c1)

  r.c0.prod2x(a.c0, b.c0)        # r0 = a0 b0
  D.prod2x(a.c1, b.c1)           # d =  a1 b1

  r.c1.prod2x(t0, t1)            # r1 = (b0 + b1)(a0 + a1)
  when Fp2.has1extraBit():
    r.c1.diff2xUnr(r.c1, r.c0)   # r1 = (b0 + b1)(a0 + a1) - a0 b0
    r.c1.diff2xUnr(r.c1, D)      # r1 = (b0 + b1)(a0 + a1) - a0 b0 - a1b1
  else:
    r.c1.diff2xMod(r.c1, r.c0)
    r.c1.diff2xMod(r.c1, D)
  r.c0.diff2xMod(r.c0, D)        # r0 = a0 b0 - a1 b1

# Generic squarings
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

  when QuadraticExt.prefer_3sqr_over_2mul() or
       # Other path multiplies twice by non-residue
       QuadraticExt.C.has_large_NR_norm():
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

func square2x_disjoint*[Fdbl, F](
       r: var QuadraticExt2x[FDbl],
       a0, a1: F) =
  ## Return (a0, a1)² in r
  var V0 {.noInit.}, V1 {.noInit.}: typeof(r.c0) # Double-precision
  var t {.noInit.}: F # Single-width

  # square2x is faster than prod2x even on Fp
  # hence we always use 3 squarings over 2 products
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

# Multiplications (specializations)
# -------------------------------------------------------------------

func prodImpl_fp4o2_complex_snr_1pi[C: static Curve](r: var Fp4[C], a, b: Fp4[C]) =
  ## Returns r = a * b
  ## For 𝔽p4/𝔽p2 with the following non-residue (NR) constraints:
  ##   * -1 is a quadratic non-residue in 𝔽p hence 𝔽p2 has coordinates a+𝑖b with i = √-1. This implies p ≡ 3 (mod 4)
  ##   * (1 + i) is a quadratic non-residue in 𝔽p hence 𝔽p2 has coordinates a+vb with v = √(1+𝑖).
  ##
  ## According to Benger-Scott 2009(https://eprint.iacr.org/2009/556.pdf)
  ## About 2/3 of the p ≡ 3 (mod 8) primes are in this case
  static:
    doAssert C.getNonResidueFp() == -1
    doAssert C.getNonresidueFp2() == (1, 1)
  var
    b10_m_b11{.noInit.}, b10_p_b11{.noInit.}: Fp[C]
    n_a01{.noInit.}, n_a11{.noInit.}: Fp[C]

    t{.noInit.}: Fp4[C]

  b10_m_b11.diff(b.c1.c0, b.c1.c1)
  b10_p_b11.sum(b.c1.c0, b.c1.c1)
  n_a01.neg(a.c0.c1)
  n_a11.neg(a.c1.c1)

  t.c0.c0.sumprod([a.c0.c0,   n_a01,   a.c1.c0,     n_a11],
                  [b.c0.c0, b.c0.c1, b10_m_b11, b10_p_b11])
  t.c0.c1.sumprod([a.c0.c0, a.c0.c1,   a.c1.c0,   a.c1.c1],
                  [b.c0.c1, b.c0.c0, b10_p_b11, b10_m_b11])
  t.c1.c0.sumprod([a.c0.c0,   n_a01,   a.c1.c0,     n_a11],
                  [b.c1.c0, b.c1.c1,   b.c0.c0,   b.c0.c1])
  t.c1.c1.sumprod([a.c0.c0, a.c0.c1,   a.c1.c0,   a.c1.c1],
                  [b.c1.c1, b.c1.c0,   b.c0.c1,   b.c0.c0])
  r = t

# Multiplications (generic)
# ----------------------------------------------------------------------

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

func prod2x_disjoint*[Fdbl, F](
       r: var QuadraticExt2x[FDbl],
       a0, a1: F,
       b0, b1: F) =
  ## Return a * (b0, b1) in r
  static: doAssert Fdbl is doublePrec(F)

  var V0 {.noInit.}, V1 {.noInit.}: typeof(r.c0) # Double-precision
  var t0 {.noInit.}, t1 {.noInit.}: typeof(a0)   # Single-width

  when F.has1extraBit():
    t0.sumUnr(a0, a1)
    t1.sumUnr(b0, b1)
  else:
    t0.sum(a0, a1)
    t1.sum(b0, b1)

  V0.prod2x(a0, b0)             # v0 = a0b0
  V1.prod2x(a1, b1)             # v1 = a1b1

  r.c1.prod2x(t0, t1)           # r1 = (a0 + a1)(b0 + b1)
  r.c1.diff2xMod(r.c1, V0)      # r1 = (a0 + a1)(b0 + b1) - a0b0
  r.c1.diff2xMod(r.c1, V1)      # r1 = (a0 + a1)(b0 + b1) - a0b0 - a1b1

  r.c0.prod2x(V1, NonResidue)   # r0 = β a1 b1
  r.c0.sum2xMod(r.c0, V0)       # r0 = a0 b0 + β a1 b1

# Sparse complex multiplication
# -------------------------------------------------------------------

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

# Sparse generic multiplication
# -------------------------------------------------------------------

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

func mul_sparse_generic_by_x0(r: var QuadraticExt, a: QuadraticExt, sparseB: auto) =
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
  when typeof(sparseB) is typeof(a):
    template b(): untyped = sparseB.c0
  elif typeof(sparseB) is typeof(a.c0):
    template b(): untyped = sparseB
  else:
    {.error: "sparseB type is " & $typeof(sparseB) &
      " which does not match with either a (" & $typeof(a) &
      ") or a.c0 (" & $typeof(a.c0) & ")".}

  r.c0.prod(a.c0, b)
  r.c1.prod(a.c1, b)

func mul2x_sparse_by_x0*[Fdbl, F](
       r: var QuadraticExt2x[Fdbl], a: QuadraticExt[F],
       sparseB: auto) =
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
  static: doAssert Fdbl is doublePrec(F)

  when typeof(sparseB) is typeof(a):
    template b(): untyped = sparseB.c0
  elif typeof(sparseB) is typeof(a.c0):
    template b(): untyped = sparseB
  else:
    {.error: "sparseB type is " & $typeof(sparseB) &
      " which does not match with either a (" & $typeof(a) &
      ") or a.c0 (" & $typeof(a.c0) & ")".}

  r.c0.prod2x(a.c0, b)
  r.c1.prod2x(a.c1, b)

func mul2x_sparse_by_0y*[Fdbl, F](
       r: var QuadraticExt2x[Fdbl], a: QuadraticExt[F],
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
  static: doAssert Fdbl is doublePrec(F)

  when typeof(sparseB) is typeof(a):
    template b(): untyped = sparseB.c1
  elif typeof(sparseB) is typeof(a.c0):
    template b(): untyped = sparseB
  else:
    {.error: "sparseB type is " & $typeof(sparseB) &
      " which does not match with either a (" & $typeof(a) &
      ") or a.c0 (" & $typeof(a.c0) & ")".}

  r.c0.prod2x(a.c1, b)
  r.c0.prod2x(r.c0, NonResidue)
  r.c1.prod2x(a.c0, b)

# Inversion
# -------------------------------------------------------------------

func invImpl(r: var QuadraticExt, a: QuadraticExt, useVartime: static bool = false) =
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
  when useVartime:
    v1.inv_vartime(v0)
  else:
    v1.inv(v0)            # v1 = 1 / (a0² - β a1²)

  # [1 Inv, 2 Mul, 2 Sqr, 1 Add, 1 Neg]
  r.c0.prod(a.c0, v1)     # r0 = a0 / (a0² - β a1²)
  v0.neg(v1)              # v0 = -1 / (a0² - β a1²)
  r.c1.prod(a.c1, v0)     # r1 = -a1 / (a0² - β a1²)

func inv2xImpl(r: var QuadraticExt, a: QuadraticExt, useVartime: static bool = false) =
  ## Compute the multiplicative inverse of ``a``
  ##
  ## The inverse of 0 is 0.
  ##
  ## Inversion routine is using lazy reduction

  # [2 Sqr, 1 Add]
  var V0 {.noInit.}, V1 {.noInit.}: doublePrec(typeof(r.c0))
  var t {.noInit.}: typeof(r.c0)
  V0.square2x(a.c0)
  V1.square2x(a.c1)
  when r.fromComplexExtension():
    V0.sum2xUnr(V0, V1)
  else:
    V1.prod2x(V1, NonResidue)
    V0.diff2xMod(V0, V1)  # v0 = a0² - β a1² (the norm / squared magnitude of a)

  # [1 Inv, 2 Sqr, 1 Add]
  t.redc2x(V0)
  when useVartime:
    t.inv_vartime()
  else:
    t.inv()                 # v1 = 1 / (a0² - β a1²)

  # [1 Inv, 2 Mul, 2 Sqr, 1 Add, 1 Neg]
  r.c0.prod(a.c0, t)      # r0 = a0 / (a0² - β a1²)
  t.neg()                 # v0 = -1 / (a0² - β a1²)
  r.c1.prod(a.c1, t)      # r1 = -a1 / (a0² - β a1²)

# Dispatch
# ----------------------------------------------------------------------

{.push inline.}

func square2x*(r: var QuadraticExt2x, a: QuadraticExt) =
  when a.fromComplexExtension():
    when UseASM_X86_64 and not QuadraticExt.C.has_large_field_elem():
      if ({.noSideEffect.}: hasAdx()):
        r.coords.sqrx2x_complex_asm_adx(a.coords)
      else:
        r.square2x_complex(a)
    else:
      r.square2x_complex(a)
  else:
    r.square2x_disjoint(a.c0, a.c1)

func square_disjoint*[F](r: var QuadraticExt[F], a0, a1: F) =
  # TODO understand why Fp4[BLS12_377]
  # is so slow in the branch
  # TODO:
  # - On Fp4, we can have a.c0.c0 off by p
  #   a reduction is missing
  static: doAssert not r.fromComplexExtension(), "Faster specialization not implemented"

  var d {.noInit.}: doublePrec(typeof(r))
  d.square2x_disjoint(a0, a1)
  r.c0.redc2x(d.c0)
  r.c1.redc2x(d.c1)

func square*(r: var QuadraticExt, a: QuadraticExt) =
  when r.fromComplexExtension():
    when UseASM_X86_64 and not QuadraticExt.C.has_large_field_elem() and r.typeof.has1extraBit():
      if ({.noSideEffect.}: hasAdx()):
        r.coords.sqrx_complex_sparebit_asm_adx(a.coords)
      else:
        r.square_complex(a)
    else:
      r.square_complex(a)
  else:
    when QuadraticExt.C.has_large_field_elem():
      # BW6-761 requires too many registers for Dbl width path
      r.square_generic(a)
    elif QuadraticExt is Fp4[BLS12_377]:
      # TODO BLS12-377 slowness to fix
      r.square_generic(a)
    else:
      r.square_disjoint(a.c0, a.c1)

func square*(a: var QuadraticExt) =
  ## In-place squaring
  a.square(a)

func prod*(r: var QuadraticExt, a, b: QuadraticExt) =
  ## Multiplication r <- a*b

  when r.fromComplexExtension():
    when UseASM_X86_64 and not QuadraticExt.C.has_large_field_elem():
      if ({.noSideEffect.}: hasAdx()):
        r.coords.mul_fp2_complex_asm_adx(a.coords, b.coords)
      else:
        var d {.noInit.}: doublePrec(typeof(r))
        d.prod2x_complex(a, b)
        r.c0.redc2x(d.c0)
        r.c1.redc2x(d.c1)
    else:
      var d {.noInit.}: doublePrec(typeof(r))
      d.prod2x_complex(a, b)
      r.c0.redc2x(d.c0)
      r.c1.redc2x(d.c1)
  else:
    when QuadraticExt is Fp12 or r.typeof.F.C.has_large_field_elem():
      # BW6-761 requires too many registers for Dbl width path
      r.prod_generic(a, b)
    elif QuadraticExt is Fp4 and QuadraticExt.C.getNonResidueFp() == -1 and QuadraticExt.C.getNonResidueFp2() == (1, 1):
      r.prodImpl_fp4o2_complex_snr_1pi(a, b)
    else:
      var d {.noInit.}: doublePrec(typeof(r))
      d.prod2x_disjoint(a.c0, a.c1, b.c0, b.c1)
      r.c0.redc2x(d.c0)
      r.c1.redc2x(d.c1)

func `*=`*(a: var QuadraticExt, b: QuadraticExt) =
  ## In-place multiplication
  a.prod(a, b)

func prod2x_disjoint*[Fdbl, F](
       r: var QuadraticExt2x[FDbl],
       a: QuadraticExt[F],
       b0, b1: F) =
  ## Return (a0, a1) * (b0, b1) in r
  r.prod2x_disjoint(a.c0, a.c1, b0, b1)

func prod2x*(r: var QuadraticExt2x, a, b: QuadraticExt) =
  ## Double-precision multiplication r <- a*b
  when a.fromComplexExtension():
    when UseASM_X86_64 and not QuadraticExt.C.has_large_field_elem():
      if ({.noSideEffect.}: hasAdx()):
        r.coords.mul2x_fp2_complex_asm_adx(a.coords, b.coords)
      else:
        r.prod2x_complex(a, b)
    else:
      r.prod2x_complex(a, b)
  else:
    r.prod2x_disjoint(a.c0, a.c1, b.c0, b.c1)

func mul_sparse_by_0y*(r: var QuadraticExt, a: QuadraticExt, sparseB: auto) =
  ## Sparse multiplication
  when a.fromComplexExtension():
    r.mul_sparse_complex_by_0y(a, sparseB)
  else:
    r.mul_sparse_generic_by_0y(a, sparseB)

func mul_sparse_by_0y*(r: var QuadraticExt, a: QuadraticExt, sparseB: static int) =
  ## Sparse multiplication
  when a.fromComplexExtension():
    {.error: "Not implemented.".}
  else:
    r.mul_sparse_generic_by_0y(a, sparseB)

func mul_sparse_by_0y*(a: var QuadraticExt, sparseB: auto) =
  ## Sparse in-place multiplication
  a.mul_sparse_by_0y(a, sparseB)

func mul_sparse_by_x0*(r: var QuadraticExt, a: QuadraticExt, sparseB: auto) =
  ## Sparse in-place multiplication
  r.mul_sparse_generic_by_x0(a, sparseB)

func mul_sparse_by_x0*(a: var QuadraticExt, sparseB: QuadraticExt) =
  ## Sparse in-place multiplication
  a.mul_sparse_by_x0(a, sparseB)

template mulCheckSparse*(a: var QuadraticExt, b: QuadraticExt) =
  when isOne(b).bool:
    discard
  elif isMinusOne(b).bool:
    a.neg()
  elif isZero(c0(b)).bool and isOne(c1(b)).bool:
    var t {.noInit.}: type(a.c0)
    when fromComplexExtension(b):
      t.neg(a.c1)
      a.c1 = a.c0
      a.c0 = t
    else:
      t.prod(a.c1, NonResidue)
      a.c1 = a.c0
      a.c0 = t
  elif isZero(c0(b)).bool and isMinusOne(c1(b)).bool:
    var t {.noInit.}: type(a.c0)
    when fromComplexExtension(b):
      t = a.c1
      a.c1.neg(a.c0)
      a.c0 = t
    else:
      t.prod(a.c1, NonResidue)
      a.c1.neg(a.c0)
      a.c0.neg(t)
  elif isZero(c0(b)).bool:
    a.mul_sparse_by_0y(b)
  elif isZero(c1(b)).bool:
    a.mul_sparse_by_x0(b)
  else:
    a *= b

func inv*(r: var QuadraticExt, a: QuadraticExt) =
  ## Compute the multiplicative inverse of ``a``
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  when true:
    r.invImpl(a)
  else: # Lazy reduction, doesn't seem to gain speed.
    r.inv2xImpl(a)

func inv*(a: var QuadraticExt) =
  ## Compute the multiplicative inverse of ``a``
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  a.inv(a)

{.pop.} # inline

# ############################################################
#                                                            #
#                    Cubic extensions                        #
#                                                            #
# ############################################################

# Squarings
# -------------------------------------------------------------------
# Cubic extensions can use specific squaring procedures
# beyond Schoolbook and Karatsuba:
# - Chung-Hasan (3 different algorithms)
# - Toom-Cook-3x (only in Miller Loops)
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
# | Tom-Cook-3x | 5S       | 33A + 2B          | (Miller loop only, factor 6)
# | CH-SQR1     | 3M + 2S  | 11A + 2B          |
# | CH-SQR2     | 2M + 3S  | 10A + 2B          |
# | CH-SQR3     | 1M + 4S  | 11A + 2B + 1 Div2 |
# | CH-SQR3x    | 1M + 4S  | 14A + 2B          | (Miller loop only, factor 2)

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

# Multiplications (specializations)
# -------------------------------------------------------------------

func prodImpl_fp6o2_complex_snr_1pi[C: static Curve](r: var Fp6[C], a, b: Fp6[C]) =
  ## Returns r = a * b
  ## For 𝔽p4/𝔽p2 with the following non-residue (NR) constraints:
  ##   * -1 is a quadratic non-residue in 𝔽p hence 𝔽p2 has coordinates a+𝑖b with i = √-1. This implies p ≡ 3 (mod 4)
  ##   * (1 + i) is a cubic non-residue in 𝔽p hence 𝔽p2 has coordinates a+vb with v = √(1+𝑖).
  ##
  ## According to Benger-Scott 2009 (https://eprint.iacr.org/2009/556.pdf)
  ## About 2/3 of the p ≡ 3 (mod 8) primes are in this case
  # https://eprint.iacr.org/2022/367 - Equation 8
  static:
    doAssert C.getNonResidueFp() == -1
    doAssert C.getNonresidueFp2() == (1, 1)
  var
    b10_p_b11{.noInit.}, b10_m_b11{.noInit.}: Fp[C]
    b20_p_b21{.noInit.}, b20_m_b21{.noInit.}: Fp[C]

    n_a01{.noInit.}, n_a11{.noInit.}, n_a21{.noInit.}: Fp[C]

    t{.noInit.}: Fp6[C]

  b10_p_b11.sum(b.c1.c0, b.c1.c1)
  b10_m_b11.diff(b.c1.c0, b.c1.c1)
  b20_p_b21.sum(b.c2.c0, b.c2.c1)
  b20_m_b21.diff(b.c2.c0, b.c2.c1)

  n_a01.neg(a.c0.c1)
  n_a11.neg(a.c1.c1)
  n_a21.neg(a.c2.c1)

  t.c0.c0.sumprod([a.c0.c0,   n_a01,   a.c1.c0,     n_a11,   a.c2.c0,     n_a21],
                  [b.c0.c0, b.c0.c1, b20_m_b21, b20_p_b21, b10_m_b11, b10_p_b11])
  t.c0.c1.sumprod([a.c0.c0, a.c0.c1,   a.c1.c0,   a.c1.c1,   a.c2.c0,   a.c2.c1],
                  [b.c0.c1, b.c0.c0, b20_p_b21, b20_m_b21, b10_p_b11, b10_m_b11])
  t.c1.c0.sumprod([a.c0.c0,   n_a01,   a.c1.c0,     n_a11,   a.c2.c0,     n_a21],
                  [b.c1.c0, b.c1.c1,   b.c0.c0,   b.c0.c1, b20_m_b21, b20_p_b21])
  t.c1.c1.sumprod([a.c0.c0, a.c0.c1,   a.c1.c0,   a.c1.c1,   a.c2.c0,   a.c2.c1],
                  [b.c1.c1, b.c1.c0,   b.c0.c1,   b.c0.c0, b20_p_b21, b20_m_b21])
  t.c2.c0.sumprod([a.c0.c0,   n_a01,   a.c1.c0,     n_a11,   a.c2.c0,     n_a21],
                  [b.c2.c0, b.c2.c1,   b.c1.c0,   b.c1.c1,   b.c0.c0,   b.c0.c1])
  t.c2.c1.sumprod([a.c0.c0, a.c0.c1,   a.c1.c0,   a.c1.c1,   a.c2.c0,   a.c2.c1],
                  [b.c2.c1, b.c2.c0,   b.c1.c1,   b.c1.c0,   b.c0.c1,   b.c0.c0])

  r = t

# Multiplications (generic)
# -------------------------------------------------------------------

func prodImpl(r: var CubicExt, a, b: CubicExt) =
  ## Returns r = a * b
  ## Algorithm is Karatsuba
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

func prod2xImpl(r: var CubicExt2x, a, b: CubicExt) =
  var V0 {.noInit.}, V1 {.noInit.}, V2 {.noinit.}: typeof(r.c0)
  var t0 {.noInit.}, t1 {.noInit.}: typeof(a.c0)

  V0.prod2x(a.c0, b.c0)
  V1.prod2x(a.c1, b.c1)
  V2.prod2x(a.c2, b.c2)

  # r₀ = β ((a₁ + a₂)(b₁ + b₂) - v₁ - v₂) + v₀
  when a.c0 is Fp and CubicExt.has1extraBit():
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
  when a.c0 is Fp and CubicExt.has1extraBit():
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
  when a.c0 is Fp and CubicExt.has1extraBit():
    t0.sumUnr(a.c0, a.c2)
    t1.sumUnr(b.c0, b.c2)
  else:
    t0.sum(a.c0, a.c2)
    t1.sum(b.c0, b.c2)
  r.c2.prod2x(t0, t1)
  r.c2.diff2xMod(r.c2, V0)
  r.c2.diff2xMod(r.c2, V2)
  r.c2.sum2xMod(r.c2, V1)

# Sparse multiplication
# ----------------------------------------------------------------------

func mul_sparse_by_x00*(r: var CubicExt, a: CubicExt, sparseB: auto) =
  ## Sparse multiplication of a cubic extension element
  ## with coordinates (a₀, a₁, a₂) by (b₀, b0, 0)

  when typeof(sparseB) is typeof(a):
    template b(): untyped = sparseB.c0
  elif typeof(sparseB) is typeof(a.c0):
    template b(): untyped = sparseB
  else:
    {.error: "sparseB type is " & $typeof(sparseB) &
      " which does not match with either a (" & $typeof(a) &
      ") or a.c0 (" & $typeof(a.c0) & ")".}

  r.c0.prod(a.c0, b)
  r.c1.prod(a.c1, b)
  r.c2.prod(a.c2, b)

func mul2x_sparse_by_x00*(r: var CubicExt2x, a: CubicExt, sparseB: auto) =
  ## Sparse multiplication of a cubic extension element
  ## with coordinates (a₀, a₁, a₂) by (b₀, b0, 0)

  when typeof(sparseB) is typeof(a):
    template b(): untyped = sparseB.c0
  elif typeof(sparseB) is typeof(a.c0):
    template b(): untyped = sparseB
  else:
    {.error: "sparseB type is " & $typeof(sparseB) &
      " which does not match with either a (" & $typeof(a) &
      ") or a.c0 (" & $typeof(a.c0) & ")".}

  r.c0.prod2x(a.c0, b)
  r.c1.prod2x(a.c1, b)
  r.c2.prod2x(a.c2, b)

func mul_sparse_by_0y0*(r: var CubicExt, a: CubicExt, sparseB: auto) =
  ## Sparse multiplication of a cubic extenion element
  ## with coordinates (a₀, a₁, a₂) by (0, b₁, 0)

  # v0 = a0 b0 = 0
  # v1 = a1 b1
  # v2 = a2 b2 = 0
  #
  # r0 = ξ ((a1 + a2) * (b1 + b2) - v1 - v2) + v0
  #    = ξ (a1 b1 + a2 b1 - v1)
  #    = ξ a2 b1
  # r1 = (a0 + a1) * (b0 + b1) - v0 - v1 + ξ v2
  #    = a0 b1 + a1 b1 - v1
  #    = a0 b1
  # r2 = (a0 + a2) * (b0 + b2) - v0 - v2 + v1
  #    = v1
  #    = a1 b1

  when typeof(sparseB) is typeof(a):
    template b(): untyped = sparseB.c1
  elif typeof(sparseB) is typeof(a.c0):
    template b(): untyped = sparseB
  else:
    {.error: "sparseB type is " & $typeof(sparseB) &
      " which does not match with either a (" & $typeof(a) &
      ") or a.c0 (" & $typeof(a.c0) & ")".}

  r.c0.prod(a.c2, b)
  r.c0 *= NonResidue
  r.c1.prod(a.c0, b)
  r.c2.prod(a.c1, b)

func mul2x_sparse_by_0y0*(r: var CubicExt2x, a: CubicExt, sparseB: auto) =
  ## Sparse multiplication of a cubic extenion element
  ## with coordinates (a₀, a₁, a₂) by (0, b₁, 0)

  when typeof(sparseB) is typeof(a):
    template b(): untyped = sparseB.c1
  elif typeof(sparseB) is typeof(a.c0):
    template b(): untyped = sparseB
  else:
    {.error: "sparseB type is " & $typeof(sparseB) &
      " which does not match with either a (" & $typeof(a) &
      ") or a.c0 (" & $typeof(a.c0) & ")".}

  r.c0.prod2x(a.c2, b)
  r.c0.prod2x(r.c0, NonResidue)
  r.c1.prod2x(a.c0, b)
  r.c2.prod2x(a.c1, b)


func mul_sparse_by_xy0*[Fpkdiv3](r: var CubicExt, a: CubicExt,
                                 x, y: Fpkdiv3) =
  ## Sparse multiplication of a cubic extension element
  ## with coordinates (a₀, a₁, a₂) by (b₀, b₁, 0)
  ##
  ## r and a must not alias

  # v0 = a0 b0
  # v1 = a1 b1
  # v2 = a2 b2 = 0
  #
  # r0 = ξ ((a1 + a2) * (b1 + b2) - v1 - v2) + v0
  #    = ξ (a1 b1 + a2 b1 - v1) + v0
  #    = ξa2 b1 + v0
  # r1 = (a0 + a1) * (b0 + b1) - v0 - v1 + ξ v2
  #    = (a0 + a1) * (b0 + b1) - v0 - v1
  # r2 = (a0 + a2) * (b0 + b2) - v0 - v2 + v1
  #    = a0 b0 + a2 b0 - v0 + v1
  #    = a2 b0 + v1

  static: doAssert a.c0 is Fpkdiv3

  var
    v0 {.noInit.}: Fpkdiv3
    v1 {.noInit.}: Fpkdiv3

  v0.prod(a.c0, x)
  v1.prod(a.c1, y)

  r.c0.prod(a.c2, y)
  r.c0 *= NonResidue
  r.c0 += v0

  r.c1.sum(a.c0, a.c1) # Error when r and a alias as r.c0 was updated
  r.c2.sum(x, y)
  r.c1 *= r.c2
  r.c1 -= v0
  r.c1 -= v1

  r.c2.prod(a.c2, x)
  r.c2 += v1


func mul2x_sparse_by_xy0*[Fpkdiv3](r: var CubicExt2x, a: CubicExt,
                                 x, y: Fpkdiv3) =
  ## Sparse multiplication of a cubic extension element
  ## with coordinates (a₀, a₁, a₂) by (b₀, b₁, 0)
  ##
  ## r and a must not alias

  static: doAssert a.c0 is Fpkdiv3

  var
    V0 {.noInit.}: doubleprec(Fpkdiv3)
    V1 {.noInit.}: doubleprec(Fpkdiv3)
    t0{.noInit.}: Fpkdiv3
    t1{.noInit.}: Fpkdiv3

  V0.prod2x(a.c0, x)
  V1.prod2x(a.c1, y)

  r.c0.prod2x(a.c2, y)
  r.c0.prod2x(r.c0, NonResidue)
  r.c0.sum2xMod(r.c0, V0)

  t0.sum(a.c0, a.c1)
  t1.sum(x, y)
  r.c1.prod2x(t0, t1)
  r.c1.diff2xMod(r.c1, V0)
  r.c1.diff2xMod(r.c1, V1)

  r.c2.prod2x(a.c2, x)
  r.c2.sum2xMod(r.c2, V1)

func mul_sparse_by_0yz*[Fpkdiv3](r: var CubicExt, a: CubicExt, y, z: Fpkdiv3) =
  ## Sparse multiplication of a cubic extension element
  ## with coordinates (a₀, a₁, a₂) by (0, b₁, b₂)
  ##
  ## r and a must not alias

  # v0 = a0 b0 = 0
  # v1 = a1 b1
  # v2 = a2 b2
  #
  # r0 = ξ ((a1 + a2) * (b1 + b2) - v1 - v2) + v0
  #    = ξ ((a1 + a2) * (b1 + b2) - v1 - v2)
  # r1 = (a0 + a1) * (b0 + b1) - v0 - v1 + ξ v2
  #    = a0 b1 + a1 b1 - v1 + ξ v2
  #    = a0 b1 + ξ v2
  # r2 = (a0 + a2) * (b0 + b2) - v0 - v2 + v1
  #    = a0 b2 + a2 b2 - v0 - v2 + v1
  #    = a0 b2 + v1

  static: doAssert a.c0 is Fpkdiv3

  var
    v1 {.noInit.}: Fpkdiv3
    v2 {.noInit.}: Fpkdiv3

  v1.prod(a.c1, y)
  v2.prod(a.c2, z)

  r.c1.sum(a.c1, a.c2)
  r.c2.sum(   y,    z)
  r.c0.prod(r.c1, r.c2)
  r.c0 -= v1
  r.c0 -= v2
  r.c0 *= NonResidue

  r.c1.prod(a.c0, y)
  v2 *= NonResidue
  r.c1 += v2

  r.c2.prod(a.c0, z)
  r.c2 += v1

func mul2x_sparse_by_0yz*[Fpkdiv3](r: var CubicExt2x, a: CubicExt, y, z: Fpkdiv3) =
  ## Sparse multiplication of a cubic extension element
  ## with coordinates (a₀, a₁, a₂) by (0, b₁, b₂)
  ##
  ## r and a must not alias
  static: doAssert a.c0 is Fpkdiv3

  var
    V1 {.noInit.}: doubleprec(Fpkdiv3)
    V2 {.noInit.}: doubleprec(Fpkdiv3)
    t1 {.noInit.}: Fpkdiv3
    t2 {.noInit.}: Fpkdiv3

  V1.prod2x(a.c1, y)
  V2.prod2x(a.c2, z)

  t1.sum(a.c1, a.c2)
  t2.sum(   y,    z)
  r.c0.prod2x(t1, t2)
  r.c0.diff2xMod(r.c0, V1)
  r.c0.diff2xMod(r.c0, V2)
  r.c0.prod2x(r.c0, NonResidue)

  r.c1.prod2x(a.c0, y)
  V2.prod2x(V2, NonResidue)
  r.c1.sum2xMod(r.c1, V2)

  r.c2.prod2x(a.c0, z)
  r.c2.sum2xMod(r.c2, V1)

# Inversion
# ----------------------------------------------------------------------

func invImpl(r: var CubicExt, a: CubicExt, useVartime: static bool = false) =
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

  when useVartime:
    t.inv_vartime()
  else:
    t.inv()

  # (a0 + a1 v + a2 v²)^-1 = (A + B v + C v²) / F
  r.c0.prod(A, t)
  r.c1.prod(B, t)
  r.c2.prod(C, t)

func inv2xImpl(r: var CubicExt, a: CubicExt, useVartime: static bool = false) =
  ## Compute the multiplicative inverse of ``a``
  ## via lazy reduction
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  var aa{.noInit.}, bb{.noInit.}, cc{.noInit.}: doublePrec(typeof(r.c0))
  var ab{.noInit.}, bc{.noInit.}, ac{.noInit.}: doublePrec(typeof(r.c0))
  var A {.noInit.}, B {.noInit.}, C {.noInit.}: typeof(r.c0)
  var t {.noInit.}, t2{.noInit.}: doublePrec(typeof(r.c0))
  var f {.noInit.}: typeof(r.c0)

  aa.square2x(a.c0)
  bb.square2x(a.c1)
  cc.square2x(a.c2)
  ab.prod2x(a.c0, a.c1)
  bc.prod2x(a.c1, a.c2)
  ac.prod2x(a.c0, a.c2)

  # A <- a₀² - β a₁ a₂
  t.prod2x(bc, NonResidue)
  t.diff2xMod(aa, t)
  A.redc2x(t)

  # B <- β a₂² - a₀ a₁
  t.prod2x(cc, NonResidue)
  t.diff2xMod(t, ab)
  B.redc2x(t)

  # C <- a₁² - a₀ a₂
  t.diff2xMod(bb, ac)
  C.redc2x(t)

  # F in t
  # F <- β a₁ C + a₀ A + β a₂ B
  t.prod2x(B, a.c2)
  t2.prod2x(C, a.c1)
  t.sum2xMod(t, t2)
  t.prod2x(t, NonResidue)
  t2.prod2x(A, a.c0)
  t.sum2xUnr(t, t2)
  f.redc2x(t)

  when useVartime:
    f.inv_vartime()
  else:
    f.inv()

  # (a0 + a1 v + a2 v²)^-1 = (A + B v + C v²) / F
  r.c0.prod(A, f)
  r.c1.prod(B, f)
  r.c2.prod(C, f)

# Dispatch
# ----------------------------------------------------------------------

{.push inline.}

func square*(r: var CubicExt, a: CubicExt) =
  ## Returns r = a²
  when CubicExt.C.has_large_NR_norm() or CubicExt.C.has_large_field_elem():
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

func square2x*(r: var CubicExt2x, a: CubicExt) =
  ## Returns r = a²
  square2x_Chung_Hasan_SQR2(r, a)

func prod*(r: var CubicExt, a, b: CubicExt) =
  ## Out-of-place multiplication
  when CubicExt.C.has_large_field_elem():
    r.prodImpl(a, b)
  elif r is Fp6 and CubicExt.C.getNonResidueFp() == -1 and CubicExt.C.getNonResidueFp2() == (1, 1):
    r.prodImpl_fp6o2_complex_snr_1pi(a, b)
  else:
    var d {.noInit.}: doublePrec(typeof(r))
    d.prod2x(a, b)
    r.c0.redc2x(d.c0)
    r.c1.redc2x(d.c1)
    r.c2.redc2x(d.c2)

func prod2x*(r: var CubicExt2x, a, b: CubicExt) =
  ## Returns r = ab
  prod2xImpl(r, a, b)

func `*=`*(a: var CubicExt, b: CubicExt) =
  ## In-place multiplication
  a.prod(a, b)

func inv*(r: var CubicExt, a: CubicExt) =
  ## Compute the multiplicative inverse of ``a``
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  when CubicExt.C.has_large_field_elem() or r is Fp12:
    r.invImpl(a)
  else:
    r.inv2xImpl(a)

func inv*(a: var CubicExt) =
  ## Compute the multiplicative inverse of ``a``
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  a.invImpl(a)

# Convenience functions
# ----------------------------------------------------------------------

template square*(a: var ExtensionField, skipFinalSub: static bool) =
  # Square alias,
  # this allows using the same code for
  # the base field and its extensions while benefitting from skipping
  # the final substraction on Fp
  a.square()

template square*(r: var ExtensionField, a: ExtensionField, skipFinalSub: static bool) =
  # Square alias,
  # this allows using the same code for
  # the base field and its extensions while benefitting from skipping
  # the final substraction on Fp
  r.square(a)

template prod*(r: var ExtensionField, a, b: ExtensionField, skipFinalSub: static bool) =
  # Prod alias,
  # this allows using the same code for
  # the base field and its extensions while benefitting from skipping
  # the final substraction on Fp
  r.prod(a, b)

# ############################################################
#                                                            #
#                     Variable-time                          #
#                                                            #
# ############################################################

func inv_vartime*(r: var QuadraticExt, a: QuadraticExt) {.tags:[VarTime].} =
  ## Compute the multiplicative inverse of ``a``
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  when true:
    r.invImpl(a, useVartime = true)
  else: # Lazy reduction, doesn't seem to gain speed.
    r.inv2xImpl(a, useVartime = true)

func inv_vartime*(r: var CubicExt, a: CubicExt) {.tags:[VarTime].} =
  ## Compute the multiplicative inverse of ``a``
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  when CubicExt.C.has_large_field_elem() or r is Fp12:
    r.invImpl(a, useVartime = true)
  else:
    r.inv2xImpl(a, useVartime = true)

func inv_vartime*(a: var ExtensionField) {.tags:[VarTime].} =
  ## Compute the multiplicative inverse of ``a``
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  a.invImpl(a, useVartime = true)

{.pop.} # inline
{.pop.} # raises no exceptions
