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
  ../../platforms/bithacks

## ############################################################
##
##                    Polynomials
##
## ############################################################

type
  PolynomialCoef*[N: static int, Field] = object
    ## A polynomial in monomial basis
    ## [a₀, a₁, a₂, ..., aₙ]
    ##
    ## mapping to the canonical formula
    ## p(x) = a₀ + a₁ x + a₂ x² + ... + aₙ xⁿ
    coefs*{.align: 64.}: array[N, Field]

  PolynomialEval*[N: static int, Field] = object
    ## A polynomial in Lagrange basis (evaluation form)
    ## [f(0), f(ω), ..., f(ωⁿ⁻¹)]
    ## with n < 2³² and ω a root of unity
    ##
    ## mapping to the barycentric Lagrange formula
    ## p(z) = (1-zⁿ)/n ∑ ωⁱ/(ωⁱ-z) . p(ωⁱ)
    ##
    ## https://ethresear.ch/t/kate-commitments-from-the-lagrange-basis-without-ffts/6950
    ## https://en.wikipedia.org/wiki/Lagrange_polynomial#Barycentric_form
    evals*{.align: 64.}: array[N, Field]

  PolyDomainEval*[N: static int, Field] = object
    ## Metadata for polynomial in Lagrange basis (evaluation form)
    rootsOfUnity*{.align: 64.}: array[N, Field]
    invMaxDegree*: Field

func inverseRootsMinusZ_vartime*[N: static int, Field](
       invRootsMinusZ: var array[N, Field],
       domain: PolyDomainEval[N, Field],
       z: Field): int =
  ## Compute 1/(ωⁱ-z) for i in [0, N)
  ##
  ## Returns -1 if z ∉ {1, ω, ω², ... , ωⁿ⁻¹}
  ## Returns the index of ωⁱ==z otherwise
  ##
  ## If ωⁱ-z == 0, the other inverses are still computed
  ## and 0 is returned at that index.

  # Mongomery's batch inversion
  # ω is a root of unity of order N,
  # so if ωⁱ-z == 0, it can only happen in one place
  var accInv{.noInit.}: Field
  var index0 = -1

  for i in 0 ..< N:
    invRootsMinusZ[i].diff(domain.rootsOfUnity[i], z)

    if invRootsMinusZ[i].isZero().bool():
      index0 = i
      continue

    if i == 0:
      accInv = invRootsMinusZ[i]
    else:
      accInv *= invRootsMinusZ[i]

  accInv.inv_vartime()

  for i in countdown(N-1, 1):
    if i == index0:
      invRootsMinusZ[i].setZero()
      continue

    invRootsMinusZ[i] *= accInv
    accInv *= domain.rootsOfUnity[i]

  invRootsMinusZ[0] *= accInv
  return index0

func evalPolyAt_vartime*[N: static int, Field](
       r: var Field,
       poly: PolynomialEval[N, Field],
       domain: PolyDomainEval[N, Field],
       invRootsMinusZ: array[N, Field],
       z: Field) =
  ## Evaluate a polynomial in evaluation form
  ## at the point z
  ## z MUST NOT be one of the roots of unity
  # p(z) = (1-zⁿ)/n ∑ ωⁱ/(ωⁱ-z) . p(ωⁱ)

  static: doAssert N.isPowerOf2_vartime()

  r.setZero()
  for i in 0 ..< N:
    var summand {.noInit.}: Field
    summand.prod(domain.rootsOfUnity[i], invRootsMinusZ[i])
    summand *= poly[i]
    r += summand

  var t {.noInit.}: Field
  t = z
  const numDoublings = log2_vartime(N) # N is a power of 2
  t.square_repeated(numDoublings)      # exponentiation by a power of 2
  t.diff(Field(mres: Field.getMontyOne()), t) # TODO: refactor getMontyOne to getOne and return a field element.
  r *= t
  r *= domain.invMaxDegree

func differenceQuotientEvalOffDomain*[N: static int, Field](
       r: var PolynomialEval[N, Field],
       invRootsMinusZ: array[N, Field],
       poly: PolynomialEval[N, Field],
       pZ: Field) =
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
    qi.diff(poly[i], pZ)
    r[i].prod(qi, invRootsMinusZ[i])

func differenceQuotientEvalInDomain*[N: static int, Field](
       r: var PolynomialEval[N, Field],
       invRootsMinusZ: array[N, Field],
       poly: PolynomialEval[N, Field],
       domain: PolyDomainEval[N, Field],
       zIndex: int) =
  ## Compute r(x) = (p(x) - p(z)) / (x - z)
  ##
  ## for z = ωⁱ a power of a root of unity
  ##
  ## Input:
  ##   - poly:            p(x) a polynomial in evaluation form as an array of p(ωⁱ)
  ##   - rootsOfUnity:    ωⁱ
  ##   - invRootsMinusZ:  1/(ωⁱ-z)
  ##   - zIndex:          the index of the root of unity power that matches z = ωⁱᵈˣ
  r[zIndex].setZero()
  template invZ(): untyped =
    # 1/z
    #  from ωⁿ = 1 and z = ωⁱᵈˣ
    #  hence ωⁿ⁻ⁱᵈˣ = 1/z
    #  Note if using bit-reversal permutation (BRP):
    #    BRP maintains the relationship
    #    that the inverse of ωⁱ is at position n-i (mod n) in the array of roots of unity
    static: doAssert N.isPowerOf2_vartime()
    domain.rootsOfUnity[(N-zIndex) and (N-1)]

  for i in 0 ..< N:
    if i == zIndex:
      # https://dankradfeist.de/ethereum/2021/06/18/pcs-multiproofs.html
      # section "Dividing when one of the points is zero".
      continue

    # qᵢ = (p(ωⁱ) - p(z))/(ωⁱ-z)
    var qi {.noinit.}: Field
    qi.diff(poly[i], poly[zIndex])
    r[i].prod(qi, invRootsMinusZ[i])

    # q'ᵢ = -qᵢ * ωⁱ/z
    # q'idx = ∑ q'ᵢ
    # since z is a power of ω, ωⁱ/z = ωⁱ⁻ⁱᵈˣ
    # However some protocols use bit-reversal permutation (brp) to store the ωⁱ
    # Hence retrieving the data would require roots[brp((brp(i)-brp(index)) mod n)] for those
    # But is this fast? There is no single instruction for reversing bits of an integer.
    # and the reversal depends on N.
    # - https://stackoverflow.com/questions/746171/efficient-algorithm-for-bit-reversal-from-msb-lsb-to-lsb-msb-in-c
    # - https://stackoverflow.com/questions/52226858/bit-reversal-algorithm-by-rutkowska
    # - https://www.hpl.hp.com/techreports/93/HPL-93-89.pdf
    # - https://graphics.stanford.edu/~seander/bithacks.html#BitReverseObvious
    # The C version from Stanford's bithacks need log₂(n) loop iterations
    # A 254~255-bit multiplication takes 38 cycles, we need 3 brp so at most ~13 cycles per brp
    # For small Ethereum KZG, n = 2¹² = 4096, we're already at the breaking point
    # even if an iteration takes a single cycle with instruction-level parallelism
    var ri {.noinit.}: Field
    ri.neg(domain.rootsOfUnity[i])
    ri *= invZ
    r[zIndex].prod(ri, qi)
