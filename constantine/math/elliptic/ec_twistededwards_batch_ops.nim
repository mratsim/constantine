# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/abstractions,
  constantine/math/arithmetic,
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
       affs: ptr UncheckedArray[EC_TwEdw_Aff[F]],
       projs: ptr UncheckedArray[EC_TwEdw_Prj[F]],
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
      affs[i].x.prod(affs[i-1].x, z, lazyReduce = true)
    else:
      affs[i].x.prod(affs[i-1].x, z, lazyReduce = false)

  var accInv {.noInit.}: F
  accInv.inv(affs[N-1].x)

  for i in countdown(N-1, 1):
    # Extract 1/Pᵢ
    var invi {.noInit.}: F
    invi.prod(accInv, affs[i-1].x, lazyReduce = true)
    invi.csetZero(zeroes[i])

    # Now convert Pᵢ to affine
    affs[i].x.prod(projs[i].x, invi)
    affs[i].y.prod(projs[i].y, invi)

    # next iteration
    invi = projs[i].z
    invi.csetOne(zeroes[i])
    accInv.prod(accInv, invi, lazyReduce = true)

  block: # tail
    accInv.csetZero(zeroes[0])
    affs[0].x.prod(projs[0].x, accInv)
    affs[0].y.prod(projs[0].y, accInv)

func batchAffine*[N: static int, F](
       affs: var array[N, EC_TwEdw_Aff[F]],
       projs: array[N, EC_TwEdw_Prj[F]]) {.inline.} =
  batchAffine(affs.asUnchecked(), projs.asUnchecked(), N)

func batchAffine*[M, N: static int, F](
       affs: var array[M, array[N, EC_TwEdw_Aff[F]]],
       projs: array[M, array[N, EC_TwEdw_Prj[F]]]) {.inline.} =
  batchAffine(affs[0].asUnchecked(), projs[0].asUnchecked(), M*N)

# Variable-time batch conversion
# ---------------------------------------------------------------

func batchAffine_vartime*[F](
       affs: ptr UncheckedArray[EC_TwEdw_Aff[F]],
       projs: ptr UncheckedArray[EC_TwEdw_Prj[F]],
       N: int) {.noInline, tags:[VarTime, Alloca].} =
  # Algorithm: Montgomery's batch inversion (variable-time version)
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
  let zeroes = allocStackArray(bool, N)

  zeroes[0] = projs[0].z.isZero().bool()
  if zeroes[0]:
    affs[0].x.setOne()
  else:
    affs[0].x = projs[0].z

  for i in 1 ..< N:
    zeroes[i] = projs[i].z.isZero().bool()
    if zeroes[i]:
      # Maintain the product chain: multiply by 1
      affs[i].x = affs[i-1].x
    else:
      if i != N-1:
        affs[i].x.prod(affs[i-1].x, projs[i].z, lazyReduce = true)
      else:
        affs[i].x.prod(affs[i-1].x, projs[i].z, lazyReduce = false)

  var accInv {.noInit.}: F
  accInv.inv_vartime(affs[N-1].x)

  for i in countdown(N-1, 1):
    # Extract 1/Pᵢ
    var invi {.noInit.}: F
    if zeroes[i]:
      # accInv is unchanged
      affs[i].setNeutral()
    else:
      invi.prod(accInv, affs[i-1].x, lazyReduce = true)
      accInv.prod(accInv, projs[i].z, lazyReduce = true)

      # Now convert Pᵢ to affine
      affs[i].x.prod(projs[i].x, invi)
      affs[i].y.prod(projs[i].y, invi)

  block: # tail
    if zeroes[0]:
      affs[0].setNeutral()
    else:
      affs[0].x.prod(projs[0].x, accInv)
      affs[0].y.prod(projs[0].y, accInv)

func batchAffine_vartime*[N: static int, F](
       affs: var array[N, EC_TwEdw_Aff[F]],
       projs: array[N, EC_TwEdw_Prj[F]]) {.inline.} =
  batchAffine_vartime(affs.asUnchecked(), projs.asUnchecked(), N)

func batchAffine_vartime*[M, N: static int, F](
       affs: var array[M, array[N, EC_TwEdw_Aff[F]]],
       projs: array[M, array[N, EC_TwEdw_Prj[F]]]) {.inline.} =
  batchAffine_vartime(affs[0].asUnchecked(), projs[0].asUnchecked(), M*N)
