# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/named/algebras,
  constantine/math/arithmetic,
  constantine/math/io/io_fields,
  constantine/platforms/[primitives, allocs, static_for]

## ############################################################
##
##                    Polynomials
##
## ############################################################

type
  PolynomialCoef*[N: static int, Group] = object
    ## A polynomial in monomial basis
    ## [a₀, a₁, a₂, ..., aₙ₋₁]
    ## of degree N-1
    ##
    ## mapping to the canonical formula
    ## p(x) = a₀ + a₁ x + a₂ x² + ... + aₙ₋₁ xⁿ⁻¹
    coefs*{.align: 64.}: array[N, Group]

  PolynomialEval*[N: static int, Group] = object
    ## A polynomial in Lagrange basis (evaluation form)
    ##
    ## The evaluation points must be specified either with
    ## - PolyEvalRootsDomain for evaluation over roots of unity
    ##    [f(0), f(ω), ..., f(ωⁿ⁻¹)]
    ##    with n < 2ᵗ, t the prime 2-adicity and ω a root of unity
    ##
    ##    mapping to the barycentric Lagrange formula
    ##    p(z) = (1-zⁿ)/n ∑ ωⁱ/(ωⁱ-z) . p(ωⁱ)
    ##
    ##    https://ethresear.ch/t/kate-commitments-from-the-lagrange-basis-without-ffts/6950
    ##    https://en.wikipedia.org/wiki/Lagrange_polynomial#Barycentric_form
    ##
    ## - or PolyEvalDomain for evaluation over generic points
    ##   for example [f(0), f(1), ..., f(n-1)]
    evals*{.align: 64.}: array[N, Group]

  PolyEvalRootsDomain*[N: static int, Field] = object
    ## Metadata for polynomial in Lagrange basis (evaluation form)
    ## with evaluation points at roots of unity.
    ##
    ## Note on inverses
    ##   1/ωⁱ (mod N) = ωⁿ⁻ⁱ (mod N)
    ## Hence in canonical representation rootsOfUnity[(N-i) and (N-1)] contains the inverse of rootsOfUnity[i]
    ## This translates into rootsOfUnity[brp((N-brp(i)) and (N-1))] when bit-reversal permuted
    rootsOfUnity*{.align: 64.}: array[N, Field]
    invMaxDegree*: Field
    isBitReversed*: bool

  PolyEvalDomain*[N: static int, Field] = object
    ## Metadata for polynomial in Lagrange basis (evaluation form)
    ## with generic evaluation points

    domain*{.align: 64.}: array[N, Field]     # Evaluation domain for a polynomial in Lagrange basis

    vanishing_deriv_poly_eval*{.align: 64.}: PolynomialEval[N, Field]     # A'(X) evaluated on domain
    vanishing_deriv_poly_eval_inv*{.align: 64.}: PolynomialEval[N, Field] # 1/A'(X) evaluated on domain

  PolyEvalLinearDomain*[N: static int, Field] = object
    ## Metadata for polynomial in Lagrange basis (evaluation form)
    ## with evaluation points linear in [0, ..., n-1]
    ##
    # This allows more efficient polynomial division on the domain.
    # has we can precompute the inverses 1/(xᵢ-z) with xᵢ,z ∈ [0, ..., n-1]
    # The first element is 1/0 and unused.
    dom*{.align: 64.}: PolyEvalDomain[N, Field]
    domain_inverses*{.align: 64.}: array[N, Field]

# Polynomials in coefficient form
# ------------------------------------------------------

func evalPolyAt*[N: static int, Field](
       r: var Field,
       poly: PolynomialCoef[N, Field],
       z: Field) =
  ## Evaluate a polynomial p at z: r <- p(z)
  # Implementation using the Horner's method
  r = poly.coefs[poly.coefs.len-1]
  for i in countdown(poly.coefs.len-2, 0):
    r *= z
    r += poly.coefs[i]

func evalPolyAndDerivAt*[N: static int, Field](
       r: var Field, rprime: var Field,
       poly: PolynomialCoef[N, Field],
       z: Field) =
  ## Evaluate a polynomial p and its formal derivative p'
  ## at z:
  ##  r  <- p(z)
  ##  r' <- p'(z)
  # Implementation using the Horner's method
  r = poly.coefs[poly.coefs.len-1]
  rprime.setZero()
  for i in countdown(poly.coefs.len-1, 1):
    rprime *= z
    rprime += r
    r *= z
    r += poly.coefs[i-1]

func formal_derivative*[N, M: static int, Field](
       polyprime: var PolynomialCoef[N, Field],
       poly: PolynomialCoef[M, Field]) =
  ## Compute P'(x), the formal derivative of the polynomial P(x)
  ## The derivative of aₙ.xⁿ is n.aₙ.xⁿ⁻¹
  ## Hence the degree of P'(X) is one less than P(X)
  static: doAssert N == M-1, "N was " & $N & " and M was " & $M

  # For the part lesser or equal 12, we use addition chains
  staticFor i, 1, min(13, poly.coefs.len):
    polyprime.coefs[i-1].prod(poly.coefs[i], i)
  for i in 13 ..< poly.coefs.len:
    var degree {.noinit.}: Field
    degree.fromInt(i)
    polyprime.coefs[i-1].prod(poly.coefs[i], degree)

# Polynomials in evaluation/Lagrange form
# ------------------------------------------------------

func areStrictlyIncreasing[Field](a: openArray[Field]): bool {.used.} =
  ## Check whether points in the domain are ordered
  if a.len == 0:
    return false

  var prev = a[0].toBig()
  for i in 1 ..< a.len:
    let cur = a[i].toBig()
    if bool(cur <= prev):
      return false
  return true

type InvDiffArrayKind* = enum
  kArrayMinus
  kMinusArray

func sum*(r: var PolynomialEval, f, g: PolynomialEval) =
  ## Polynomial addition
  for i in 0 ..< r.evals.len:
    r.evals[i].sum(f.evals[i], g.evals[i])

func `+=`*(f: var PolynomialEval, g: PolynomialEval) =
  ## Polynomial addition
  for i in 0 ..< f.evals.len:
    f.evals[i] += g.evals[i]

func diff*(r: var PolynomialEval, f, g: PolynomialEval) =
  ## Polynomial substraction
  for i in 0 ..< r.evals.len:
    r.evals[i].diff(f.evals[i], g.evals[i])

func `-=`*(f: var PolynomialEval, g: PolynomialEval) =
  ## Polynomial addition
  for i in 0 ..< f.evals.len:
    f.evals[i] -= g.evals[i]

func prod*[N, F](r: var PolynomialEval[N, F], s: F, f: PolynomialEval[N, F]) =
  ## Rescale a polynomial r(X) <- s.f(X)
  for i in 0 ..< N:
    r.evals[i].prod(s, f.evals[i])

func `*=`*[N, F](f: var PolynomialEval[N, F], s: F) =
  ## Rescale a polynomial f(X) <- s.f(X)
  for i in 0 ..< N:
    f.evals[i] *= s

func multiplyAccumulate*[N, F](f: var PolynomialEval[N, F], s: F, g: PolynomialEval[N, F]) =
  ## Polynomial f(X) += s.g(X)
  for i in 0 ..< N:
    var t {.noInit.}: F
    t.prod(s, g.evals[i])
    f.evals[i] += t

func inverseDifferenceArray*[Field, W](
       r: ptr UncheckedArray[Field],
       w: ptr UncheckedArray[W],
       N: int,
       z: Field,
       differenceKind: static InvDiffArrayKind,
       earlyReturnOnZero: static bool): int =
  ## Compute 1/(wᵢ-z) or 1/(z-wᵢ) for i in [0, N)
  ##
  ## Returns -1 if z ∉ {w₀, ω₁, ω₂, ... , wₙ₋₁}
  ## Returns the index of wᵢ==z otherwise
  ##
  ## If wᵢ-z == 0 AND earlyReturnOnZero is false
  ##   the other inverses are still computed
  ##   and 0 is returned at that index
  ## If wᵢ-z == 0 AND earlyReturnOnZero is true
  ##   the index of wᵢ==z is returned
  ##   the content of the result r is undefined
  ##
  ## The wᵢ must be unique
  ## so that wᵢ == 0 can happen only once.
  ##
  ## **variable-time**:
  ## This leaks whether z is in the domain or not.

  # Mongomery's batch inversion
  # The wᵢ are unique
  # so if wᵢ-z == 0, it can only happen in one place
  var accInv{.noInit.}: Field
  var diffs = allocHeapArrayAligned(Field, N, alignment = 64)

  accInv.setOne()
  var index0 = -1

  template toF(w: W): Field =
    when W is Field: w
    elif W is SomeUnsignedInt: Field.fromUint(w)
    elif W is SomeSignedInt: Field.fromInt(w)
    else:
      {.error: "Unsupported input type for w: " & $W.}

  for i in 0 ..< N:
    when differenceKind == kArrayMinus:
      diffs[i].diff(toF(w[i]), z)
    else:
      diffs[i].diff(z, toF(w[i]))

    if diffs[i].isZero().bool():
      when earlyReturnOnZero:
        freeHeapAligned(diffs)
        return i
      else:
        index0 = i

  for i in 0 ..< N:
    if i != index0:
      r[i] = accInv
      accInv *= diffs[i]
    else:
      r[i].setZero()

  accInv.inv_vartime()

  for i in countdown(N-1, 1):
    if i == index0:
      continue

    r[i] *= accInv
    accInv *= diffs[i]

  if index0 == 0:
    r[0].setZero()
  else: # invRootsMinusZ[0] was init to accInv=1
    r[0] = accInv

  freeHeapAligned(diffs)
  return index0

func inverseDifferenceArray*[N: static int, Field](
       r: var array[N, Field],
       w: array[N, Field],
       z: Field,
       differenceKind: static InvDiffArrayKind,
       earlyReturnOnZero: static bool): int {.inline.}=
  inverseDifferenceArray(
    r.asUnchecked(),
    w.asUnchecked(),
    N,
    z,
    differenceKind,
    earlyReturnOnZero)

# Polynomials in evaluation/Lagrange form
#   Domain = roots of unity
# ------------------------------------------------------

func evalPolyOffDomainAt*[N: static int, Field](
       domain: PolyEvalRootsDomain[N, Field],
       r: var Field,
       poly: PolynomialEval[N, Field],
       z: Field,
       invRootsMinusZ: array[N, Field]) =
  ## Evaluate a polynomial in evaluation form
  ## at the point z
  ## z MUST NOT be one of the roots of unity
  # p(z) = (1-zⁿ)/n ∑ ωⁱ/(ωⁱ-z) . p(ωⁱ)

  static: doAssert N.isPowerOf2_vartime()

  r.setZero()
  for i in 0 ..< N:
    var summand {.noInit.}: Field
    summand.prod(domain.rootsOfUnity[i], invRootsMinusZ[i])
    summand *= poly.evals[i]
    r += summand

  var t {.noInit.}: Field
  t = z
  const numDoublings = log2_vartime(uint32 N) # N is a power of 2
  t.square_repeated(int numDoublings)         # exponentiation by a power of 2
  t.diff(Field.getOne(), t)
  r *= t
  r *= domain.invMaxDegree

func evalPolyAt*[N: static int, Field](
       domain: PolyEvalRootsDomain[N, Field],
       r: var Field,
       poly: PolynomialEval[N, Field],
       z: Field) =
  ## Evaluate a polynomial in evaluation form
  ## at the point z

  # Lagrange Polynomial evaluation
  # ------------------------------
  # 1. Compute 1/(ωⁱ - z) with ω a root of unity, i in [0, N).
  #    zIndex = i if ωⁱ - z == 0 (it is the i-th root of unity) and -1 otherwise.
  let invRootsMinusZ = allocHeapAligned(array[N, Field], alignment = 64)
  let zIndex = invRootsMinusZ[].inverseDifferenceArray(
                                  domain.rootsOfUnity,
                                  z,
                                  differenceKind = kArrayMinus,
                                  earlyReturnOnZero = true)

  # 2. Actual evaluation
  if zIndex == -1:
    domain.evalPolyOffDomainAt(
      r,
      poly, z,
      invRootsMinusZ[])
  else:
    r = poly.evals[zIndex]

  freeHeapAligned(invRootsMinusZ)

# Polynomials in evaluation/Lagrange form
#   Domain = generic
# ------------------------------------------------------

func vanishingPoly*[N, M: static int, Field](
      r: var PolynomialCoef[N, Field],
      roots: array[M, Field]) =
  ## Build a polynomial that returns 0 at all evaluation points,
  ## i.e. the specified polynomial roots.
  ## The polynomial is in coefficient form.
  ##
  ## The polynomial has M+1 coefficients (i.e. is degree M)
  ## with M the number of roots.
  ## Hence N == M+1
  static: doAssert N == M+1, "N was " & $N & " and M was " & $M
  zeroMem(r.addr, sizeof(r))
  r.coefs[r.coefs.len-1].setOne()
  for i in 0 ..< roots.len:
    for j in r.coefs.len-2-i ..< r.coefs.len-1:
      var t {.noInit.}: Field
      t.prod(r.coefs[j+1], roots[i])
      r.coefs[j] -= t

func evalVanishingPolyAt*[N: static int, Field](
      r: var Field,
      roots: array[N, Field],
      z: Field) =
  ## Evaluate the vanishing polynomial
  ## specified by "roots" at z
  # The vanishing polynomial is A(X) = (X-x₀)(X-x₁)...(X-xₙ)
  r.diff(z, roots[0])
  for i in 1 ..< N:
    var t {.noInit.}: Field
    t.diff(z, roots[i])
    r *= t

func evalVanishingPolyDerivativeAtRoot*[N: static int, Field](
      r: var Field,
      roots: array[N, Field],
      root_index: int) =
  ## Evaluate the derivative of vanishing polynomial
  ## at a specified root
  # The vanishing polynomial is A(X) = (X-x₀)(X-x₁)(X-x₂)...(X-xₙ)
  # With z the root we evaluate A'(X) at.
  #
  #   A'(z) = lim X->z (A(X) - A(z)) / (X - z)
  #
  # z is a root, hence A(z) = 0.
  # A(X) = (X-x₀)(X-x₁)(X-x₂)...(X-xₙ)
  # so (X-z) is a divisor of A(X)
  #
  # For example A'(x₁) = lim X->x₁ (X-x₀)(X-x₂)...(X-xₙ)
  let z {.noInit.} = roots[root_index]
  r.setOne()
  for i in 0 ..< N:
    if i != root_index:
      var t {.noInit.}: Field
      t.diff(z, roots[i])
      r *= t

func evalPolyAt*[N: static int, Field](
       domain: PolyEvalDomain[N, Field],
       r: var Field,
       poly: PolynomialEval[N, Field],
       z: Field) =
  ## Evaluate a polynomial p at z: r <- p(z)
  ##
  ## **variable-time**:
  ## This leaks whether z is in the domain or not.
  #
  # With A(X) the vanishing polynomial
  # that evaluates to 0 for each point xᵢ of the domain.
  # - https://dankradfeist.de/ethereum/2021/06/18/pcs-multiproofs.html#evaluating-a-polynomial-in-evaluation-form-on-a-point-outside-the-domain
  #
  #   p(z) = A(z) ∑ᵢ p(xᵢ).1/A'(xᵢ).1/(z-xᵢ)
  #
  # Wikipedia notation: https://en.wikipedia.org/wiki/Lagrange_polynomial#Barycentric_form
  #
  #   L(z) = l(z) ∑ⱼ ωⱼ/(z-xⱼ).yⱼ
  #
  #   with l(z) = A(z)
  #        ωⱼ   = 1/A'(xᵢ)
  #        yⱼ   = p(xᵢ)
  let invZminusDomain = allocHeapAligned(array[N, Field], alignment = 64)
  let zIndex = invZminusDomain[].inverseDifferenceArray(
    domain.domain,
    z,
    differenceKind = kMinusArray,
    earlyReturnOnZero = true
  )

  if zIndex == -1:
    r.setZero()
    for i in 0 ..< N:
      # p(xᵢ).1/A'(xᵢ).1/(z-xᵢ)
      var t {.noInit.}: Field
      t.prod(poly.evals[i], domain.vanishing_deriv_poly_eval_inv.evals[i])
      t *= invZminusDomain[i]
      r += t

    var az {.noInit.}: Field
    az.evalVanishingPolyAt(domain.domain, z)
    r *= az
  else:
    # We're on one of point of the domain
    r = poly.evals[zIndex]

  freeHeapAligned(invZminusDomain)

func computeLagrangeBasisPolysAt*[N: static int, Field](
      domain: PolyEvalDomain[N, Field],
      lagrangePolys: var array[N, Field],
      z: Field) =
  ## A polynomial p(X) in evaluation form
  ## is represented by its evaluations
  ##   [f(0), f(1), ..., f(n-1)]
  ## over predefined points called a domain
  ##   [x₀, x₁, ..., xₙ₋₁]
  ##
  ## The representation is also called a polynomial in Lagrange form or Lagrange basis.
  ##
  ## p(x) = ∑ⱼ f(j).lⱼ(x)
  ##
  ## with lⱼ(x) a Lagrange basis polynomial that
  ## - takes value 1 for x == j
  ## - takes 0 for all other points in the domain.
  ##
  ## - https://en.wikipedia.org/wiki/Lagrange_polynomial
  ## - Barycentric Lagrange Interpolation
  ##   Jean-Paul Berrutt & Lloyd N. Trefethen, 2004
  ##   https://people.maths.ox.ac.uk/trefethen/barycentric.pdf
  ##   DOI. 10.1137/S0036144502417715
  ##
  ## That representation is an inner product and so
  ## can be used to commit to a polynomial in Lagrange form
  ## and build an Inner Product Argument.
  ##
  ## - Inner Product Argument
  ##   Dankrad Feist, 2021
  ##   https://dankradfeist.de/ethereum/2021/07/27/inner-product-arguments.html
  ##
  ## **variable-time**:
  ## This leaks whether z is in the domain or not.

  let invZminusDomain = allocHeapAligned(array[N, Field], alignment = 64)
  let zIndex = invZminusDomain[].inverseDifferenceArray(
    domain.domain,
    z,
    differenceKind = kMinusArray,
    earlyReturnOnZero = true
  )

  if zIndex == -1:
    var az {.noInit.}: Field
    az.evalVanishingPolyAt(domain.domain, z)

    for i in 0 ..< N:
      # A(z).1/A'(xᵢ).1/(z-xᵢ)
      lagrangePolys[i].prod(az, invZminusDomain[i])
      lagrangePolys[i] *= domain.vanishing_deriv_poly_eval_inv.evals[i]
  else:
    # We're on one of point of the domain
    # All lagrange basis polynomials are 0 except one that is 1.
    for i in 0 ..< N:
      if zIndex != i:
        lagrangePolys[i].setZero()
      else:
        lagrangePolys[i].setOne()

  freeHeapAligned(invZminusDomain)

# Polynomials in evaluation/Lagrange form
#   Domain = linear [0, 1, ..., N-1]
# ------------------------------------------------------

func evalPolyAt*[N: static int, Field](
       lindom: PolyEvalLinearDomain[N, Field],
       r: var Field,
       poly: PolynomialEval[N, Field],
       z: Field) =
  lindom.dom.evalPolyAt(r, poly, z)

func computeLagrangeBasisPolysAt*[N: static int, Field](
      lindom: PolyEvalLinearDomain[N, Field],
      lagrangePolys: var array[N, Field],
      z: Field) =
  lindom.dom.computeLagrangeBasisPolysAt(lagrangePolys, z)

func setupLinearEvaluationDomain*[N: static int, Field](
      lindom: var PolyEvalLinearDomain[N, Field]) =
  ## Configure a linear evaluation domain [0, ..., n-1]
  ## for computation with polynomials in barycentric Lagrange form

  for i in 0'u32 ..< N:
    lindom.dom.domain[i].fromInt(i)

  for i in 0 ..< N:
    lindom.dom.vanishing_deriv_poly_eval.evals[i]
              .evalVanishingPolyDerivativeAtRoot(
                lindom.dom.domain,
                i)

  lindom.domain_inverses
    .batchInv_vartime(lindom.dom.domain)

  lindom.dom.vanishing_deriv_poly_eval_inv.evals
    .batchInv_vartime(lindom.dom.vanishing_deriv_poly_eval.evals)
