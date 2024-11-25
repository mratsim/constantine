/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
#ifndef __CTT_H_ETHEREUM_VERKLE_IPA__
#define __CTT_H_ETHEREUM_VERKLE_IPA__

#include "constantine/core/datatypes.h"
#include "constantine/core/serialization.h"
#include "constantine/hashes/sha256.h"
#include "constantine/curves/banderwagon.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum __attribute__((__packed__)) {
    cttEthVerkleIpa_Success,
    cttEthVerkleIpa_VerificationFailure,
    cttEthVerkleIpa_InputsLengthsMismatch,
    cttEthVerkleIpa_ScalarZero,
    cttEthVerkleIpa_ScalarLargerThanCurveOrder,
    cttEthVerkleIpa_EccInvalidEncoding,
    cttEthVerkleIpa_EccCoordinateGreaterThanOrEqualModulus,
    cttEthVerkleIpa_EccPointNotOnCurve,
    cttEthVerkleIpa_EccPointNotInSubGroup
} ctt_eth_verkle_ipa_status;

static const char* ctt_evm_status_to_string(ctt_eth_verkle_ipa_status status) {
  static const char* const statuses[] = {
      "cttEthVerkleIpa_Success",
      "cttEthVerkleIpa_VerificationFailure",
      "cttEthVerkleIpa_InputsLengthsMismatch",
      "cttEthVerkleIpa_ScalarZero",
      "cttEthVerkleIpa_ScalarLargerThanCurveOrder",
      "cttEthVerkleIpa_EccInvalidEncoding",
      "cttEthVerkleIpa_EccCoordinateGreaterThanOrEqualModulus",
      "cttEthVerkleIpa_EccPointNotOnCurve",
      "cttEthVerkleIpa_EccPointNotInSubGroup"
  };
  size_t length = sizeof statuses / sizeof *statuses;
  if (0 <= status && status < length) {
    return statuses[status];
  }
  return "cttEthVerkleIpa_InvalidStatusCode";
}

//types


#ifdef __cplusplus
}
#endif

#endif // __CTT_H_ETHEREUM_VERKLE_IPA__
