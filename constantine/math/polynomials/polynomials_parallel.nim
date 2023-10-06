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
  ../config/curves,
  ../arithmetic,
  ../../platforms/bithacks,
  ../../threadpool/threadpool

## ############################################################
##
##                    Polynomials
##                 Parallel Edition
##
## ############################################################

proc evalPolyAt_parallel*[N: static int, Field](
       tp: Threadpool,
       r: var Field,
       poly: ptr PolynomialEval[N, Field],
       z: ptr Field,
       invRootsMinusZ: ptr array[N, Field],
       domain: ptr PolyDomainEval[N, Field]) =
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
    reduceInto(globalSum: Field):
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
  t.diff(Field(mres: Field.getMontyOne()), t) # TODO: refactor getMontyOne to getOne and return a field element.

  r.prod(t, domain.invMaxDegree)
  r *= sync(globalSum)

proc differenceQuotientEvalOffDomain_parallel*[N: static int, Field](
       tp: Threadpool,
       r: ptr PolynomialEval[N, Field],
       poly: ptr PolynomialEval[N, Field],
       pZ: ptr Field,
       invRootsMinusZ: ptr array[N, Field]) =
  ## Compute r(x) = (p(x) - p(z)) / (x - z)
  ##
  ## for z != ωⁱ a power of a root of unity
  ##
  ## Input:
  ##   - invRootsMinusZ:  1/(ωⁱ-z)
  ##   - poly:            p(x) a polynomial in evaluation form as an array of p(ωⁱ)
  ##   - rootsOfUnity:    ωⁱ
  ##   - p(z)
  ##
  ## Parallelism: This only returns when computation is fully done
  # TODO: we might want either awaitable for-loops
  #       or awaitable individual iterations
  #       for latency-hiding techniques

  syncScope:
    tp.parallelFor i in 0 ..< N:
      captures: {r, poly, pZ, invRootsMinusZ}
      # qᵢ = (p(ωⁱ) - p(z))/(ωⁱ-z)
      var qi {.noinit.}: Field
      qi.diff(poly.evals[i], pZ[])
      r.evals[i].prod(qi, invRootsMinusZ[i])

proc differenceQuotientEvalInDomain_parallel*[N: static int, Field](
       tp: Threadpool,
       r: ptr PolynomialEval[N, Field],
       poly: ptr PolynomialEval[N, Field],
       zIndex: uint32,
       invRootsMinusZ: ptr array[N, Field],
       domain: ptr PolyDomainEval[N, Field],
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
  ##
  ## Parallelism: This only returns when computation is fully done

  static:
    # For powers of 2: x mod N == x and (N-1)
    doAssert N.isPowerOf2_vartime()

  mixin evalsZindex

  tp.parallelFor i in 0 ..< N:
    captures: {r, poly, domain, invRootsMinusZ, zIndex}
    reduceInto(evalsZindex: Field):
      prologue:
        var worker_ri {.noInit.}: Field
        worker_ri.setZero()
      forLoop:
        var iter_ri {.noInit.}: Field
        if i == int(zIndex):
          iter_ri.setZero()
        else:
          # qᵢ = (p(ωⁱ) - p(z))/(ωⁱ-z)
          var qi {.noinit.}: Field
          qi.diff(poly.evals[i], poly.evals[zIndex])
          r.evals[i].prod(qi, invRootsMinusZ[i])

          # q'ᵢ = -qᵢ * ωⁱ/z
          # q'idx = ∑ q'ᵢ
          iter_ri.neg(r.evals[i])                                  # -qᵢ
          when isBitReversedDomain:
            const logN = log2_vartime(uint32 N)
            let invZidx = N - reverseBits(uint32 zIndex, logN)
            let canonI = reverseBits(uint32 i, logN)
            let idx = reverseBits((canonI + invZidx) and (N-1), logN)
            iter_ri *= domain.rootsOfUnity[idx]                    # -qᵢ * ωⁱ/z  (explanation at the bottom of serial impl)
          else:
            iter_ri *= domain.rootsOfUnity[(i+N-zIndex) and (N-1)] # -qᵢ * ωⁱ/z  (explanation at the bottom of serial impl)
          worker_ri += iter_ri
      merge(remote_ri: Flowvar[Field]):
        worker_ri += sync(remote_ri)
      epilogue:
        return worker_ri

  r.evals[zIndex] = sync(evalsZindex)