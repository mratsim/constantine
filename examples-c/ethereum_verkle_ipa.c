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

#include <constantine.h>

int main(){
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
  ctt_sha256_hash(message, (const byte*)"Mr F was here", 13, /* clear_memory = */ 0);
  ctt_eth_bls_sign(&sig, &seckey, message, 32);

  // Verify that a signature is valid for a message under the provided public key
  bls_status = ctt_eth_bls_verify(&pubkey, message, 32, &sig);
  if (bls_status != cttEthBls_Success) {
    printf("Signature verification failure: status %d - %s\n", bls_status, ctt_eth_bls_status_to_string(bls_status));
    exit(1);
  }
  printf("Example BLS signature/verification protocol completed successfully\n");


  // ------------------------------
  // Batch verification
  // ------------------------------

  // try to use batch verify; We just reuse the data from above 3 times
  const ctt_eth_bls_pubkey pkeys[3] = { pubkey, pubkey, pubkey };
  ctt_span messages[3] = { // already hashed message, reuse 3 times
      { message, 32 },
      { message, 32 },
      { message, 32 }
  };
  const ctt_eth_bls_signature sigs[3] = { sig, sig, sig };

  // Use constantine's `sysrand` to fill the secure random bytes
  byte srb[32];
  if(!ctt_csprng_sysrand(srb, 32)){
      printf("Failed to fill `srb` using `sysrand`\n");
      exit(1);
  }

  bls_status = ctt_eth_bls_batch_verify(pkeys, messages, sigs, 3, srb);
  if (bls_status != cttEthBls_Success) {
    printf("Batch verification failure: status %d - %s\n", bls_status, ctt_eth_bls_status_to_string(bls_status));
    exit(1);
  }

  printf("Example BLS batch verification completed successfully\n");

  // ------------------------------
  // Batch verification, parallel
  // ------------------------------

  // and now try to use a threadpool and do the same in parallel

  struct ctt_threadpool* tp = ctt_threadpool_new(4);
  printf("Constantine: Threadpool init successful.\n");
  bls_status = ctt_eth_bls_batch_verify_parallel(tp, pkeys, messages, sigs, 3, srb);
  if (bls_status != cttEthBls_Success) {
    printf("Batch verification failure: status %d - %s\n", bls_status, ctt_eth_bls_status_to_string(bls_status));
    exit(1);
  }
  printf("Example parallel BLS batch verification completed successfully\n");

  ctt_threadpool_shutdown(tp);
  printf("Constantine: Threadpool shutdown successful.\n");



  return 0;
}
