# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/abstractions,
  ../arithmetic,
  ./ec_twistededwards_affine,
  ./ec_twistededwards_projective

# No exceptions allowed, or array bound checks or integer overflow
{.push raises: [], checks:off.}

# ############################################################
#
#             Elliptic Curve in Twisted Edwards form
#                     Batch conversion
#
# ############################################################

func batchAffine*[F](
       affs: ptr UncheckedArray[ECP_TwEdwards_Aff[F]],
       projs: ptr UncheckedArray[ECP_TwEdwards_Prj[F]],
       N: int) {.noInline, tags:[Alloca].} =
  # Algorithm: Montgomery's batch inversion
  # - Speeding the Pollard and Elliptic Curve Methods of Factorization
  #   Section 10.3.1
  #   Peter L. Montgomery
  #   https://www.ams.org/journals/mcom/1987-48-177/S0025-5718-1987-0866113-7/S0025-5718-1987-0866113-7.pdf
  # - Modern Computer Arithmetic
  #   Section 2.5.1 Several inversions at once
  #   Richard P. Brent and Paul Zimmermann
  #   https://members.loria.fr/PZimmermann/mca/mca-cup-0.5.9.pdf

  # To avoid temporaries, we store partial accumulations
  # in affs[i].x
  let zeroes = allocStackArray(SecretBool, N)
  affs[0].x = projs[0].z
  zeroes[0] = affs[0].x.isZero()
  affs[0].x.csetOne(zeroes[0])

  for i in 1 ..< N:
    # Skip zero z-coordinates (infinity points)
    var z = projs[i].z
    zeroes[i] = z.isZero()
    z.csetOne(zeroes[i])

    if i != N-1:
      affs[i].x.prod(affs[i-1].x, z, skipFinalSub = true)
    else:
      affs[i].x.prod(affs[i-1].x, z, skipFinalSub = false)

  var accInv {.noInit.}: F
  accInv.inv(affs[N-1].x)

  for i in countdown(N-1, 1):
    # Extract 1/Pᵢ
    var invi {.noInit.}: F
    invi.prod(accInv, affs[i-1].x, skipFinalSub = true)
    invi.csetZero(zeroes[i])

    # Now convert Pᵢ to affine
    affs[i].x.prod(projs[i].x, invi)
    affs[i].y.prod(projs[i].y, invi)

    # next iteration
    invi = projs[i].z
    invi.csetOne(zeroes[i])
    accInv.prod(accInv, invi, skipFinalSub = true)

  block: # tail
    accInv.csetZero(zeroes[0])
    affs[0].x.prod(projs[0].x, accInv)
    affs[0].y.prod(projs[0].y, accInv)

func batchAffine*[N: static int, F](
       affs: var array[N, ECP_TwEdwards_Aff[F]],
       projs: array[N, ECP_TwEdwards_Prj[F]]) {.inline.} =
  batchAffine(affs.asUnchecked(), projs.asUnchecked(), N)

func batchAffine*[M, N: static int, F](
       affs: var array[M, array[N, ECP_TwEdwards_Aff[F]]],
       projs: array[M, array[N, ECP_TwEdwards_Prj[F]]]) {.inline.} =
  batchAffine(affs[0].asUnchecked(), projs[0].asUnchecked(), M*N)

func batchInvert*[F](
        dst: ptr UncheckedArray[F],
        elements: ptr UncheckedArray[F],
        N: int
      ) {.noInline.} =
  ##  Montgomery's batch inversion
  var zeros = allocStackArray(bool, N)
  zeroMem(zeros, N)

  var accumulator: F
  accumulator.setOne()    # sets the accumulator to 1

  for i in 0 ..< N: 
    if elements[i].isZero().bool():
      zeros[i] = true
      continue

    dst[i] = accumulator
    accumulator *= elements[i]

  accumulator.inv()   # inversion of the accumulator

  for i in countdown(N-1, 0):
    if zeros[i] == true:
      continue
    dst[i] *= accumulator
    accumulator *= elements[i]

func batchInvert*[F](dst: var openArray[F], source: openArray[F]) {.inline.} =
  debug: doAssert dst.len == source.len
  batchInvert(dst.asUnchecked(), source.asUnchecked(), dst.len)

func batchInvert*[N: static int, F](dst: var array[N, F], src: array[N, F]) =
  batchInvert(dst.asUnchecked(), src.asUnchecked(), N)
