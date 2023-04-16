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

  // Initialize the runtime. For Constantine, it populates CPU runtime detection dispatch.
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

  // Sign a message
  byte message[13] = "Mr F was here";
  size_t message_len = sizeof(message);
  printf("size: %d\n", message_len);

  ctt_eth_bls_signature sig;


  return 0;
}