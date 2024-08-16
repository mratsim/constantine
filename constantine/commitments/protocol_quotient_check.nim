# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../math/arithmetic,
  ../math/polynomials/polynomials,
  ../platforms/primitives

## ############################################################
##
##                 Quotient check protocol
##
## ############################################################

# Lagrange polynomial with domain = roots of unity
# -------------------------------------------------------------

func getQuotientPolyOffDomain[N: static int, Field](
       r: var PolynomialEval[N, Field],
       poly: PolynomialEval[N, Field],
       pZ: Field,
       invDomainMinusZ: array[N, Field]) =
  ## Compute r(x) = (p(x) - p(z)) / (x - z)
  ##
  ## for z not in evaluation domain
  ##
  ## (x-z) MUST be a factor of p(x) - p(z)
  ## or the result is undefined.
  ##
  ## Input:
  ##   - invDomainMinusZ:  1/(xᵢ-z)
  ##   - poly:             p(x) a polynomial in evaluation form as an array of p(ωⁱ)
  ##   - p(z)
  for i in 0 ..< N:
    # qᵢ = (p(xᵢ) - p(z))/(xᵢ-z)
    var qi {.noinit.}: Field
    qi.diff(poly.evals[i], pZ)
    r.evals[i].prod(qi, invDomainMinusZ[i])


func getQuotientPolyInDomain*[N: static int, Field](
       domain: PolyEvalRootsDomain[N, Field],
       r: var PolynomialEval[N, Field],
       poly: PolynomialEval[N, Field],
       zIndex: uint32,
       invRootsMinusZ: array[N, Field]) =
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
      #
      # Due to qᵢ = 0/0, we can't directly compute
      # the polynomial evaluation at i == zIndex.
      # However we can rewrite it as a sum that depends
      # on all other evaluations.
      continue

    # qᵢ = (p(ωⁱ) - p(z))/(ωⁱ-z)
    var qi {.noinit.}: Field
    qi.diff(poly.evals[i], poly.evals[zIndex])
    r.evals[i].prod(qi, invRootsMinusZ[i])

    # Compute contribution of qᵢ to qz which can't be computed directly
    # qz = - ∑ q'ᵢ * ωⁱ/z
    var ri {.noinit.}: Field
    if domain.isBitReversed:
      const logN = log2_vartime(uint32 N)
      let invZidx = N - reverseBits(uint32 zIndex, logN)
      let canonI = reverseBits(i, logN)
      let idx = reverseBits((canonI + invZidx) and (N-1), logN)
      ri.prod(r.evals[i], domain.rootsOfUnity[idx])        # qᵢ * ωⁱ/z  (explanation at the bottom)
    else:
      ri.prod(r.evals[i],
              domain.rootsOfUnity[(i+N-zIndex) and (N-1)]) # qᵢ * ωⁱ/z  (explanation at the bottom)
    r.evals[zIndex] -= ri                                  # r[zIndex] = - ∑ qᵢ * ωⁱ/z

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

func getQuotientPoly*[N: static int, Field](
       domain: PolyEvalRootsDomain[N, Field],
       quotientPoly: var PolynomialEval[N, Field],
       eval_at_challenge: var Field,
       poly: PolynomialEval[N, Field],
       opening_challenge: Field) =
  ## Compute r(x) = (p(x) - p(z)) / (x - z)
  ##
  ## for z a polynomial opening challenge
  ## that allow proving knowledge of a polynomial
  ## without transmitting the whole polynomial
  ##
  ## (x-z) MUST be a factor of p(x) - p(z)
  ## or the result is undefined.
  ## This property is used to implement a "quotient check"
  ## in proof systems.
  let invRootsMinusZ = allocHeapAligned(array[N, Field], alignment = 64)

  # Compute 1/(ωⁱ - z) with ω a root of unity, i in [0, N).
  # zIndex = i if ωⁱ - z == 0 (it is the i-th root of unity) and -1 otherwise.
  let zIndex = invRootsMinusZ[].inverseDifferenceArray(
                                  domain.rootsOfUnity,
                                  opening_challenge,
                                  differenceKind = kArrayMinus,
                                  earlyReturnOnZero = false)

  if zIndex == -1:
    # p(z)
    domain.evalPolyOffDomainAt(
      eval_at_challenge,
      poly, opening_challenge,
      invRootsMinusZ[])

    # q(x) = (p(x) - p(z)) / (x - z)
    quotientPoly.getQuotientPolyOffDomain(
      poly, eval_at_challenge, invRootsMinusZ[])
  else:
    # p(z)
    # But the opening_challenge z is equal to one of the roots of unity (how likely is that?)
    eval_at_challenge = poly.evals[zIndex]

    # q(x) = (p(x) - p(z)) / (x - z)
    domain.getQuotientPolyInDomain(
      quotientPoly,
      poly, uint32 zIndex, invRootsMinusZ[])

  freeHeapAligned(invRootsMinusZ)

# Lagrange polynomial with linear domain
# -------------------------------------------------------------

func getQuotientPolyInDomain*[N: static int, Field](
       lindom: PolyEvalLinearDomain[N, Field],
       r: var PolynomialEval[N, Field],
       poly: PolynomialEval[N, Field],
       zIndex: uint32) =
  ## Compute r(x) = (p(x) - p(z)) / (x - z)
  ##
  ## for z = xᵢ, one of the element in the domain.
  ## The domain MUST be linearly spaced [0, 1, ..., n-1]
  ##
  ## Input:
  ##   - poly:            p(x) a polynomial in evaluation form as an array of p(xᵢ)
  ##   - zIndex:          the index i of xᵢ that matches z = xᵢ
  ##   - domain           the array of evaluation points [0, 1, ..., n-1]
  ##                      and related precomputed constants like
  ##                      vanishing polynomial, its derivative and inverse.
  #
  # - https://dankradfeist.de/ethereum/2021/06/18/pcs-multiproofs.html
  #   section "Dividing when one of the points is zero".
  # - https://hackmd.io/@6iQDuIePQjyYBqDChYw_jg/B1FWLgtD9

  r.evals[zIndex].setZero()

  for i in 0'u32 ..< N:
    if i == zIndex:
      # https://dankradfeist.de/ethereum/2021/06/18/pcs-multiproofs.html
      # section "Dividing when one of the points is zero".
      #
      # Due to qᵢ = 0/0, we can't directly compute
      # the polynomial evaluation at i == zIndex.
      # However we can rewrite it as a sum that depends
      # on all other evaluations.
      continue

    # qᵢ = (p(xᵢ) - p(z))/(xᵢ-z)
    var qi {.noinit.}: Field
    if i > zIndex:
      qi.diff(poly.evals[i], poly.evals[zIndex])
      # 1/(xᵢ-z) does not need division as xᵢ, z ∈ [0, 1, ..., n-1]
      # and we can precompute [1/0, 1/1, ..., 1/(n-1)]
      # Since i != zIndex, 1/0 is actually unused and is just padding.
      r.evals[i].prod(qi, lindom.domain_inverses[i-zIndex])
    else:
      # We only precompute the positive inverses [1/1, ..., 1/(n-1)]
      # so we negate numerator and denominator.
      # qᵢ = (p(z) - p(xᵢ))/(z-xᵢ)
      qi.diff(poly.evals[zIndex], poly.evals[i])
      r.evals[i].prod(qi, lindom.domain_inverses[zIndex-i])

    # Compute contribution of qᵢ to qz which can't be computed directly
    # qz = - ∑ A'(z)/A'(xᵢ) qᵢ
    var ri {.noinit.}: Field
    ri.prod(
      lindom.dom.vanishing_deriv_poly_eval.evals[zIndex],
      lindom.dom.vanishing_deriv_poly_eval_inv.evals[i]
    )
    ri *= r.evals[i]
    r.evals[zIndex] -= ri
