/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
#ifndef __CTT_H_SERIALIZATION__
#define __CTT_H_SERIALIZATION__

#include "constantine/core/datatypes.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum __attribute__((__packed__)) {
    cttCodecScalar_Success,
    cttCodecScalar_Zero,
    cttCodecScalar_ScalarLargerThanCurveOrder,
} ctt_codec_scalar_status;

static const char* ctt_codec_scalar_status_to_string(ctt_codec_scalar_status status) {
  static const char* const statuses[] = {
    "cttCodecScalar_Success",
    "cttCodecScalar_Zero",
    "cttCodecScalar_ScalarLargerThanCurveOrder",
  };
  size_t length = sizeof statuses / sizeof *statuses;
  if (0 <= status && status < length) {
    return statuses[status];
  }
  return "cttCodecScalar_InvalidStatusCode";
}

typedef enum __attribute__((__packed__)) {
    cttCodecEcc_Success,
    cttCodecEcc_InvalidEncoding,
    cttCodecEcc_CoordinateGreaterThanOrEqualModulus,
    cttCodecEcc_PointNotOnCurve,
    cttCodecEcc_PointNotInSubgroup,
    cttCodecEcc_PointAtInfinity,
} ctt_codec_ecc_status;

static const char* ctt_codec_ecc_status_to_string(ctt_codec_ecc_status status) {
  static const char* const statuses[] = {
    "cttCodecEcc_Success",
    "cttCodecEcc_InvalidEncoding",
    "cttCodecEcc_CoordinateGreaterThanOrEqualModulus",
    "cttCodecEcc_PointNotOnCurve",
    "cttCodecEcc_PointNotInSubgroup",
    "cttCodecEcc_PointAtInfinity",
  };
  size_t length = sizeof statuses / sizeof *statuses;
  if (0 <= status && status < length) {
    return statuses[status];
  }
  return "cttCodecEcc_InvalidStatusCode";
}

#ifdef __cplusplus
}
#endif

#endif // __CTT_H_SERIALIZATION__