# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

type
  CttCodecScalarStatus* = enum
    cttCodecScalar_Success
    cttCodecScalar_Zero
    cttCodecScalar_ScalarLargerThanCurveOrder

  CttCodecEccStatus* = enum
    cttCodecEcc_Success
    cttCodecEcc_InvalidEncoding
    cttCodecEcc_CoordinateGreaterThanOrEqualModulus
    cttCodecEcc_PointNotOnCurve
    cttCodecEcc_PointNotInSubgroup
    cttCodecEcc_PointAtInfinity