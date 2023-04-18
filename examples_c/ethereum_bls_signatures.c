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

  ctt_eth_bls_status status;

  // Declare an example insecure non-cryptographically random non-secret key. DO NOT USE IN PRODUCTION.
  byte raw_seckey[32] = "Security pb becomes key mgmt pb!";
  ctt_eth_bls_seckey seckey;

  status = ctt_eth_bls_deserialize_seckey(&seckey, raw_seckey);
  if (status != cttBLS_Success) {
    printf("Secret key deserialization failure: status %d - %s\n", status, ctt_eth_bls_status_to_string(status));
    exit(1);
  }

  // Derive the matching public key
  ctt_eth_bls_pubkey pubkey;

  status = ctt_eth_bls_derive_pubkey(&pubkey, &seckey);
  if (status != cttBLS_Success) {
    printf("Public key derivation failure: status %d - %s\n", status, ctt_eth_bls_status_to_string(status));
    exit(1);
  }

  // Sign a message
  byte message[32];
  ctt_eth_bls_signature sig;

  ctt_eth_bls_sha256_hash(message, "Mr F was here", 13, /* clear_memory = */ 0);

  status = ctt_eth_bls_sign(&sig, &seckey, message, 32);
  if (status != cttBLS_Success) {
    printf("Message signing failure: status %d - %s\n", status, ctt_eth_bls_status_to_string(status));
    exit(1);
  }

  // Verify that a signature is valid for a message under the provided public key
  status = ctt_eth_bls_verify(&pubkey, message, 32, &sig);
  if (status != cttBLS_Success) {
    printf("Signature verification failure: status %d - %s\n", status, ctt_eth_bls_status_to_string(status));
    exit(1);
  }

  printf("Example BLS signature/verification protocol completed successfully\n");
  return 0;
}