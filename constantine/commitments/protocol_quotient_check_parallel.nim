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
  ../platforms/primitives,
  ../threadpool/threadpool

## ############################################################
##
##                 Quotient check protocol
##                     Parallel edition
##
## ############################################################

proc getQuotientPolyOffDomain_parallel*[N: static int, Field](
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
  ##   - poly:            p(x) a polynomial in evaluation form as an array of p(ωⁱ)
  ##   - p(z)
  ##   - invRootsMinusZ:  1/(ωⁱ-z)
  ##
  ## Output
  ##   - r(x): the quotient polynomial
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

proc getQuotientPolyInDomain_parallel*[N: static int, Field](
      tp: Threadpool,
      domain: ptr PolyEvalRootsDomain[N, Field],
      r: ptr PolynomialEval[N, Field],
      poly: ptr PolynomialEval[N, Field],
      zIndex: uint32,
      invRootsMinusZ: ptr array[N, Field]) =
  ## Compute r(x) = (p(x) - p(z)) / (x - z)
  ##
  ## for z = ωⁱ a power of a root of unity
  ##
  ## Input:
  ##   - domain:          roots of unity ωⁱ
  ##   - poly:            p(x) a polynomial in evaluation form as an array of p(ωⁱ)
  ##   - zIndex:          the index of the root of unity power that matches z = ωⁱᵈˣ
  ##   - invRootsMinusZ:  1/(ωⁱ-z)
  ##
  ## Output
  ##   - r(x): the quotient polynomial
  ##
  ## Parallelism: This only returns when computation is fully done

  static:
    # For powers of 2: x mod N == x and (N-1)
    doAssert N.isPowerOf2_vartime()

  mixin evalsZindex

  tp.parallelFor i in 0 ..< N:
    captures: {r, poly, domain, invRootsMinusZ, zIndex}
    reduceInto(evalsZindex: Flowvar[Field]):
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
          if domain.isBitReversed:
            const logN = log2_vartime(uint32 N)
            let invZidx = N - reverseBits(uint32 zIndex, logN)
            let canonI = reverseBits(uint32 i, logN)
            let idx = reverseBits((canonI + invZidx) and (N-1), logN)
            iter_ri *= domain.rootsOfUnity[idx]                    # -qᵢ * ωⁱ/z  (explanation at the bottom of serial impl)
          else:
            iter_ri *= domain.rootsOfUnity[(i+N-int(zIndex)) and (N-1)] # -qᵢ * ωⁱ/z  (explanation at the bottom of serial impl)
          worker_ri += iter_ri
      merge(remote_ri: Flowvar[Field]):
        worker_ri += sync(remote_ri)
      epilogue:
        return worker_ri

  r.evals[zIndex] = sync(evalsZindex)

proc getQuotientPoly_parallel*[N: static int, Field](
      tp: Threadpool,
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
  ##
  ## Input:
  ##   - domain:          roots of unity ωⁱ
  ##   - poly:            p(x) a polynomial in evaluation form as an array of p(ωⁱ)
  ##   - zIndex:          the index of the root of unity power that matches z = ωⁱᵈˣ
  ##
  ## Output
  ##   - quotientPoly
  ##   - eval_at_challenge

  # Compute 1/(ωⁱ - z) with ω a root of unity, i in [0, N).
  # zIndex = i if ωⁱ - z == 0 (it is the i-th root of unity) and -1 otherwise.
  let invRootsMinusZ = allocHeapAligned(array[N, Field], alignment = 64)
  let zIndex = invRootsMinusZ[].inverseDifferenceArray(
                                  domain.rootsOfUnity,
                                  opening_challenge,
                                  differenceKind = kArrayMinus,
                                  earlyReturnOnZero = false)

  if zIndex == -1:
    # p(z)
    tp.evalPolyOffDomainAt_parallel(
      domain.unsafeAddr,
      eval_at_challenge,
      poly.unsafeAddr, opening_challenge.unsafeAddr,
      invRootsMinusZ)

    # q(x) = (p(x) - p(z)) / (x - z)
    tp.getQuotientPolyOffDomain_parallel(
      quotientPoly.addr,
      poly.unsafeAddr, eval_at_challenge.unsafeAddr, invRootsMinusZ)
  else:
    # p(z)
    # But the opening_challenge z is equal to one of the roots of unity (how likely is that?)
    eval_at_challenge = poly.evals[zIndex]

    # q(x) = (p(x) - p(z)) / (x - z)
    tp.getQuotientPolyInDomain_parallel(
      domain.unsafeAddr,
      quotientPoly.addr,
      poly.unsafeAddr, uint32 zIndex, invRootsMinusZ)

  freeHeapAligned(invRootsMinusZ)
