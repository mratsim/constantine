/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

#include <constantine_ethereum_bls_signatures.h>

int main(){

  // Initialize the runtime. For Constantine, it populates the CPU runtime detection dispatch.
  ctt_eth_bls_init_NimMain();

  // Protocol and deserialization statuses
  ctt_eth_bls_status      bls_status;
  ctt_codec_scalar_status scalar_status;
  ctt_codec_ecc_status    ecc_status;

  // Declare an example insecure non-cryptographically random non-secret key. DO NOT USE IN PRODUCTION.
  byte raw_seckey[32] = "Security pb becomes key mgmt pb!";
  ctt_eth_bls_seckey seckey;

  scalar_status = ctt_eth_bls_deserialize_seckey(&seckey, raw_seckey);
  if (scalar_status != cttCodecScalar_Success) {
    printf(
      "Secret key deserialization failure: status %d - %s\n",
      scalar_status,
      ctt_codec_scalar_status_to_string(scalar_status)
    );
    exit(1);
  }

  // Derive the matching public key
  ctt_eth_bls_pubkey pubkey;
  ctt_eth_bls_derive_pubkey(&pubkey, &seckey);

  // Sign a message
  byte message[32];
  ctt_eth_bls_signature sig;
  ctt_eth_bls_sha256_hash(message, "Mr F was here", 13, /* clear_memory = */ 0);
  ctt_eth_bls_sign(&sig, &seckey, message, 32);

  // Verify that a signature is valid for a message under the provided public key
  bls_status = ctt_eth_bls_verify(&pubkey, message, 32, &sig);
  if (bls_status != cttBLS_Success) {
    printf("Signature verification failure: status %d - %s\n", bls_status, ctt_eth_bls_status_to_string(bls_status));
    exit(1);
  }

  printf("Example BLS signature/verification protocol completed successfully\n");
  return 0;
}