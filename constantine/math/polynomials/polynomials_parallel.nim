# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./polynomials {.all.}
export polynomials

import
  constantine/named/algebras,
  constantine/math/arithmetic,
  constantine/platforms/[allocs, bithacks],
  ../../threadpool/threadpool

## ############################################################
##
##                    Polynomials
##                 Parallel Edition
##
## ############################################################

proc evalPolyOffDomainAt_parallel*[N: static int, Field](
       tp: Threadpool,
       domain: ptr PolyEvalRootsDomain[N, Field],
       r: var Field,
       poly: ptr PolynomialEval[N, Field],
       z: ptr Field,
       invRootsMinusZ: ptr array[N, Field]) =
  ## Evaluate a polynomial in evaluation form
  ## at the point z
  ## z MUST NOT be one of the roots of unity
  ##
  ## Parallelism: This only returns when computation is fully done

  # p(z) = (1-zⁿ)/n ∑ ωⁱ/(ωⁱ-z) . p(ωⁱ)

  mixin globalSum
  static: doAssert N.isPowerOf2_vartime()

  tp.parallelFor i in 0 ..< N:
    captures: {poly, domain, invRootsMinusZ}
    reduceInto(globalSum: Flowvar[Field]):
      prologue:
        var workerSum {.noInit.}: Field
        workerSum.setZero()
      forLoop:
        var iterSummand {.noInit.}: Field
        iterSummand.prod(domain.rootsOfUnity[i], invRootsMinusZ[i])
        iterSummand *= poly.evals[i]
        workerSum += iterSummand
      merge(remoteSum: Flowvar[Field]):
        workerSum += sync(remoteSum)
      epilogue:
        return workerSum

  var t {.noInit.}: Field
  t = z[]
  const numDoublings = log2_vartime(uint32 N) # N is a power of 2
  t.square_repeated(int numDoublings)         # exponentiation by a power of 2
  t.diff(Field.getOne(), t)

  r.prod(t, domain.invMaxDegree)
  r *= sync(globalSum)

proc evalPolyAt_parallel*[N: static int, Field](
       tp: Threadpool,
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
    tp.evalPolyOffDomainAt_parallel(
      domain.unsafeAddr,
      r,
      poly.unsafeAddr, z.unsafeAddr,
      invRootsMinusZ)
  else:
    r = poly.evals[zIndex]

  freeHeapAligned(invRootsMinusZ)
