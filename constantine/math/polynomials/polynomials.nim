# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/curves,
  ../arithmetic,
  ../io/io_fields,
  ../../platforms/[bithacks, static_for]

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

  PolyEvalDomain*[N: static int, Field] = object
    ## Metadata for polynomial in Lagrange basis (evaluation form)
    ## with generic evaluation points

    domain*{.align: 64.}: array[N, Field]     # Evaluation domain for a polynomial in Lagrange basis
    domain_inv*{.align: 64.}: array[N, Field] # Multiplicative inverse of evaluation domain

    vanishing_poly*{.align: 64.}: PolynomialCoef[N, Field]       # A(X)
    vanishing_deriv_poly*{.align: 64.}: PolynomialCoef[N, Field] # A'(X)

    vanishing_deriv_poly_eval*{.align: 64.}: PolynomialEval[N, Field]     # A'(X) evaluated on domain
    vanishing_deriv_poly_eval_inv*{.align: 64.}: PolynomialEval[N, Field] # A'(X) evaluated on domain and inverted

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

func inverseRootsMinusZ_vartime*[N: static int, Field](
       invRootsMinusZ: var array[N, Field],
       domain: PolyEvalRootsDomain[N, Field],
       z: Field,
       earlyReturnOnZero: static bool): int =
  ## Compute 1/(ωⁱ-z) for i in [0, N)
  ##
  ## Returns -1 if z ∉ {1, ω, ω², ... , ωⁿ⁻¹}
  ## Returns the index of ωⁱ==z otherwise
  ##
  ## If ωⁱ-z == 0 AND earlyReturnOnZero is false
  ##   the other inverses are still computed
  ##   and 0 is returned at that index
  ## If ωⁱ-z == 0 AND earlyReturnOnZero is true
  ##   the index of ωⁱ==z is returned
  ##   the content of invRootsMinusZ is undefined

  # Mongomery's batch inversion
  # ω is a root of unity of order N,
  # so if ωⁱ-z == 0, it can only happen in one place
  var accInv{.noInit.}: Field
  var rootsMinusZ{.noInit.}: array[N, Field]

  accInv.setOne()
  var index0 = -1

  when earlyReturnOnZero: # Split computation in 2 phases
    for i in 0 ..< N:
      rootsMinusZ[i].diff(domain.rootsOfUnity[i], z)
      if rootsMinusZ[i].isZero().bool():
        return i

  for i in 0 ..< N:
    when not earlyReturnOnZero: # Fused substraction and batch inversion
      rootsMinusZ[i].diff(domain.rootsOfUnity[i], z)
      if rootsMinusZ[i].isZero().bool():
        index0 = i
        invRootsMinusZ[i].setZero()
        continue

    invRootsMinusZ[i] = accInv
    accInv *= rootsMinusZ[i]

  accInv.inv_vartime()

  for i in countdown(N-1, 1):
    if i == index0:
      continue

    invRootsMinusZ[i] *= accInv
    accInv *= rootsMinusZ[i]

  if index0 == 0:
    invRootsMinusZ[0].setZero()
  else: # invRootsMinusZ[0] was init to accInv=1
    invRootsMinusZ[0] = accInv
  return index0

func evalPolyAt*[N: static int, Field](
       r: var Field,
       poly: PolynomialEval[N, Field],
       z: Field,
       invRootsMinusZ: array[N, Field],
       domain: PolyEvalRootsDomain[N, Field]) =
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
  t.diff(Field(mres: Field.getMontyOne()), t) # TODO: refactor getMontyOne to getOne and return a field element.
  r *= t
  r *= domain.invMaxDegree

func differenceQuotientEvalOffDomain*[N: static int, Field](
       r: var PolynomialEval[N, Field],
       poly: PolynomialEval[N, Field],
       pZ: Field,
       invRootsMinusZ: array[N, Field]) =
  ## Compute r(x) = (p(x) - p(z)) / (x - z)
  ##
  ## for z != ωⁱ a power of a root of unity
  ##
  ## Input:
  ##   - invRootsMinusZ:  1/(ωⁱ-z)
  ##   - poly:            p(x) a polynomial in evaluation form as an array of p(ωⁱ)
  ##   - rootsOfUnity:    ωⁱ
  ##   - p(z)
  for i in 0 ..< N:
    # qᵢ = (p(ωⁱ) - p(z))/(ωⁱ-z)
    var qi {.noinit.}: Field
    qi.diff(poly.evals[i], pZ)
    r.evals[i].prod(qi, invRootsMinusZ[i])

func differenceQuotientEvalInDomain*[N: static int, Field](
       r: var PolynomialEval[N, Field],
       poly: PolynomialEval[N, Field],
       zIndex: uint32,
       invRootsMinusZ: array[N, Field],
       domain: PolyEvalRootsDomain[N, Field],
       isBitReversedDomain: static bool) =
  ## Compute r(x) = (p(x) - p(z)) / (x - z)
  ##
  ## for z = ωⁱ a power of a root of unity
  ##
  ## Input:
  ##   - poly:            p(x) a polynomial in evaluation form as an array of p(ωⁱ)
  ##   - rootsOfUnity:    ωⁱ
  ##   - invRootsMinusZ:  1/(ωⁱ-z)
  ##   - zIndex:          the index of the root of unity power that matches z = ωⁱᵈˣ

  static:
    # For powers of 2: x mod N == x and (N-1)
    doAssert N.isPowerOf2_vartime()

  r.evals[zIndex].setZero()

  for i in 0'u32 ..< N:
    if i == zIndex:
      # https://dankradfeist.de/ethereum/2021/06/18/pcs-multiproofs.html
      # section "Dividing when one of the points is zero".
      continue

    # qᵢ = (p(ωⁱ) - p(z))/(ωⁱ-z)
    var qi {.noinit.}: Field
    qi.diff(poly.evals[i], poly.evals[zIndex])
    r.evals[i].prod(qi, invRootsMinusZ[i])

    # q'ᵢ = -qᵢ * ωⁱ/z
    # q'idx = ∑ q'ᵢ
    var ri {.noinit.}: Field
    ri.neg(r.evals[i])                                  # -qᵢ
    when isBitReversedDomain:
      const logN = log2_vartime(uint32 N)
      let invZidx = N - reverseBits(uint32 zIndex, logN)
      let canonI = reverseBits(i, logN)
      let idx = reverseBits((canonI + invZidx) and (N-1), logN)
      ri *= domain.rootsOfUnity[idx]                    # -qᵢ * ωⁱ/z  (explanation at the bottom)
    else:
      ri *= domain.rootsOfUnity[(i+N-zIndex) and (N-1)] # -qᵢ * ωⁱ/z  (explanation at the bottom)
    r.evals[zIndex] += ri                               # r[zIndex] = ∑ -qᵢ * ωⁱ/z

    # * 1/z computation detail
    #    from ωⁿ = 1 and z = ωⁱᵈˣ
    #    hence ωⁿ⁻ⁱᵈˣ = 1/z
    #    However our z may be in bit-reversal permuted
    #
    # * We want ωⁱ/z which translate to ωⁱ*ωⁿ⁻ⁱᵈˣ hence ωⁱ⁺ⁿ⁻ⁱᵈˣ
    #   with the roots of unity being a cyclic group of order N so we compute i+N-zIndex (mod N)
    #
    #   However some protocols use bit-reversal permutation (brp) to store the ωⁱ
    #   Hence retrieving the data requires roots[brp((brp(i)-n-brp(idx)) mod n)] for those (note: n = brp(n))
    #
    #   For Ethereum:
    #     A 254~255-bit multiplication takes 11ns / 38 cycles (Fr[BLS12-381]),
    #     A brp with n = 2¹² = 4096 (for EIP4844) takes about 6ns
    #   We could also cache either ωⁿ⁻ⁱ or a map i' = brp(n - brp(i))
    #   in non-brp order but cache misses are expensive
    #   and brp can benefits from instruction-level parallelism

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

func areStrictlyIncreasing[Field](a: openArray[Field]): bool =
  if a.len == 0:
    return false

  var prev = a[0].toBig()
  for i in 1 ..< a.len:
    let cur = a[i].toBig()
    if bool(cur <= prev):
      return false
  return true

func setupEvaluationDomain*[N: static int, Field](
      dom: var PolyEvalDomain[N, Field],
      evaluation_points: array[N, Field]) =
  ## Configure an evaluation domain
  ## for computation with polynomials in barycentric Lagrange form
  ##
  ## evaluation points must be strictly increasing.

  doAssert evaluation_points.areStrictlyIncreasing()
