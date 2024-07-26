# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/lowlevel_elliptic_curves_parallel,
  constantine/threadpool

export lowlevel_elliptic_curves_parallel

template genParallelBindings_EC_ShortW_NonAffine*(EC, EcAff, ScalarField: untyped) =
  # TODO: remove the need of explicit ScalarField

  # For some unknown reason {.push noconv.}
  # would overwrite the threadpool {.nimcall.}
  # in the parallel for-loop `generateClosure`
  #
  # Similarly, exportc breaks the threadpool generated closure
  # hence instead of push/pop we create a pragma alias

  when appType == "lib":
    {.pragma: libExport, dynlib, exportc,  raises: [].} # No exceptions allowed
  else:
    {.pragma: libExport, exportc,  raises: [].} # No exceptions allowed

  # --------------------------------------------------------------------------------------
  proc `ctt _ EC _ multi_scalar_mul_big_coefs_vartime_parallel`(
          tp: Threadpool,
          r: var EC,
          coefs: ptr UncheckedArray[BigInt[ScalarField.bits()]],
          points: ptr UncheckedArray[EcAff],
          len: csize_t) {.libExport.} =
    tp.multiScalarMul_vartime_parallel(r.addr, coefs, points, cast[int](len))

  proc `ctt _ EC _ multi_scalar_mul_fr_coefs_vartime_parallel`(
          tp: Threadpool,
          r: var EC,
          coefs: ptr UncheckedArray[ScalarField],
          points: ptr UncheckedArray[EcAff],
          len: csize_t) {.libExport.} =
    tp.multiScalarMul_vartime_parallel(r.addr, coefs, points, cast[int](len))
