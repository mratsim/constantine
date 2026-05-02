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
       N: int) =
  if N <= 0:
    return

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
  # in affs[i].x and zero-tracking in affs[i].y
  template zero(i: int): SecretWord =
    affs[i].y.mres.limbs[0]

  affs[0].x = projs[0].z
  zero(0) = SecretWord affs[0].x.isZero()
  affs[0].x.csetOne(SecretBool zero(0))

  for i in 1 ..< N:
    # Skip zero z-coordinates (infinity points)
    var z = projs[i].z
    zero(i) = SecretWord z.isZero()
    z.csetOne(SecretBool zero(i))

    if i != N-1:
      affs[i].x.prod(affs[i-1].x, z, lazyReduce = true)
    else:
      affs[i].x.prod(affs[i-1].x, z, lazyReduce = false)

  var accInv {.noInit.}: F
  accInv.inv(affs[N-1].x)

  for i in countdown(N-1, 1):
    # Extract 1/Pᵢ
    var invi {.noInit.}, invi_next {.noInit.}: F
    invi.prod(accInv, affs[i-1].x, lazyReduce = true)
    invi.csetZero(SecretBool zero(i))

    # next iteration
    invi_next = projs[i].z
    invi_next.csetOne(SecretBool zero(i))
    accInv.prod(accInv, invi_next, lazyReduce = true)

    # Now convert Pᵢ to affine
    affs[i].x.prod(projs[i].x, invi)
    affs[i].y.prod(projs[i].y, invi)

  block: # tail
    accInv.csetZero(SecretBool zero(0))
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
       N: int) {.tags:[VarTime].} =
  if N <= 0:
    return

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
  # in affs[i].x and zero-tracking in affs[i].y
  template zero(i: int): SecretWord =
    affs[i].y.mres.limbs[0]

  zero(0) = SecretWord projs[0].z.isZero()
  if zero(0).bool():
    affs[0].x.setOne()
  else:
    affs[0].x = projs[0].z

  for i in 1 ..< N:
    # Skip zero z-coordinates (infinity points)
    zero(i) = SecretWord projs[i].z.isZero()
    if zero(i).bool():
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
    if zero(i).bool():
      # accInv is unchanged
      affs[i].setNeutral()
    else:
      invi.prod(accInv, affs[i-1].x, lazyReduce = true)
      accInv.prod(accInv, projs[i].z, lazyReduce = true)

      # Now convert Pᵢ to affine
      affs[i].x.prod(projs[i].x, invi)
      affs[i].y.prod(projs[i].y, invi)

  block: # tail
    if zero(0).bool():
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
