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

#include <string.h>
#include <constantine.h>

void hex_to_bytes(const char *hex_string, byte *byte_array, size_t array_size) {
    size_t hex_len = strlen(hex_string);
    if (hex_len % 2 != 0 || hex_len / 2 > array_size) {
        fprintf(stderr, "Error: Hex string length invalid or too large.\n");
        return;
    }
    for (size_t i = 0; i < hex_len / 2; i++) {
        sscanf(&hex_string[2 * i], "%2hhx", &byte_array[i]);
    }
}

// TODO: complete testing
int main(){
  // Protocol and deserialization statuses
  ctt_eth_verkle_ipa_status      ipa_status;

  banderwagon_ec_prj point;
  char *endptr;
  char *endptrX;
  char *endptrY;
  char *endptrZ;
  // point.x = (banderwagon_fp) { .limbs = { strtol("0x0e7e3748db7c5c999a7bcd93d71d671f1f40090423792266f94cb27ca43fce5c", &endptrX, 16) } };
  // point.y = (banderwagon_fp) { .limbs = { strtol("0x563a625521456130dc66f9fd6bda67330c7bb183b7f2223216c1c9536e1c622f", &endptrY, 16) } };
  // point.z = (banderwagon_fp) { .limbs = { strtol("0x01", &endptrZ, 16) } };

  const ctt_eth_verkle_ipa_proof_bytes proof_bytes = { {0} };

  hex_to_bytes("00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002d3e383cf2ca36482707617daf4230f2261cff2abeb98a7d1e139cf386970f7a67cea4e0dcf8c437e5cd9852d95613a255ef625412a3ac7fb1a0d27227a32a7c1292f14b7c189f033c91217f02b34c7832958afc7ae3bb498b29ca08277dc60d1c53bb5f07280c16238a7f99c059cbbdbbc933bef4b74d604721a09b526aac1751a4bdf0df2d303418e7e5642ac4aacc730625514c87a4bcce5369cc4c1e1d2a1ee9125e09db763e7d99fa857928fabeb94ba822d5cf1cc8f5be372683ee7089082c0ca302a243f0124cc25319d069e0c689f03e4cb32e266fffd4b8c9a5e1cb2c708dc7960531ecea4331e376d7f6604228fc0606a08bda95ee3350c8bca83f37b23160af7bae3db95f0c66ed4535fc5397b43dcdc1d09c1e3a0376a6705d916d96cb64feb47d00ebf1ddbad7eaf3b5d8c381d31098c5c8a909793bd6063c2f0450320af78de387938261eba3e984271f31c3f71a55b33631b90505f8209b384aa55feb1c1c72a5e2abce15f24eb18715a309f5517ac3079c64c8ff157d3e35d5bad17b86f9599b1e34f1f4b7c6600a83913261645a0811fba0ad1ed104fe0c", proof_bytes.raw, sizeof(proof_bytes.raw));
  // printf("Converted raw bytes (%zu bytes):\n", strlen("00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002d3e383cf2ca36482707617daf4230f2261cff2abeb98a7d1e139cf386970f7a67cea4e0dcf8c437e5cd9852d95613a255ef625412a3ac7fb1a0d27227a32a7c1292f14b7c189f033c91217f02b34c7832958afc7ae3bb498b29ca08277dc60d1c53bb5f07280c16238a7f99c059cbbdbbc933bef4b74d604721a09b526aac1751a4bdf0df2d303418e7e5642ac4aacc730625514c87a4bcce5369cc4c1e1d2a1ee9125e09db763e7d99fa857928fabeb94ba822d5cf1cc8f5be372683ee7089082c0ca302a243f0124cc25319d069e0c689f03e4cb32e266fffd4b8c9a5e1cb2c708dc7960531ecea4331e376d7f6604228fc0606a08bda95ee3350c8bca83f37b23160af7bae3db95f0c66ed4535fc5397b43dcdc1d09c1e3a0376a6705d916d96cb64feb47d00ebf1ddbad7eaf3b5d8c381d31098c5c8a909793bd6063c2f0450320af78de387938261eba3e984271f31c3f71a55b33631b90505f8209b384aa55feb1c1c72a5e2abce15f24eb18715a309f5517ac3079c64c8ff157d3e35d5bad17b86f9599b1e34f1f4b7c6600a83913261645a0811fba0ad1ed104fe0c") / 2);
  //   for (size_t i = 0; i < strlen("00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002d3e383cf2ca36482707617daf4230f2261cff2abeb98a7d1e139cf386970f7a67cea4e0dcf8c437e5cd9852d95613a255ef625412a3ac7fb1a0d27227a32a7c1292f14b7c189f033c91217f02b34c7832958afc7ae3bb498b29ca08277dc60d1c53bb5f07280c16238a7f99c059cbbdbbc933bef4b74d604721a09b526aac1751a4bdf0df2d303418e7e5642ac4aacc730625514c87a4bcce5369cc4c1e1d2a1ee9125e09db763e7d99fa857928fabeb94ba822d5cf1cc8f5be372683ee7089082c0ca302a243f0124cc25319d069e0c689f03e4cb32e266fffd4b8c9a5e1cb2c708dc7960531ecea4331e376d7f6604228fc0606a08bda95ee3350c8bca83f37b23160af7bae3db95f0c66ed4535fc5397b43dcdc1d09c1e3a0376a6705d916d96cb64feb47d00ebf1ddbad7eaf3b5d8c381d31098c5c8a909793bd6063c2f0450320af78de387938261eba3e984271f31c3f71a55b33631b90505f8209b384aa55feb1c1c72a5e2abce15f24eb18715a309f5517ac3079c64c8ff157d3e35d5bad17b86f9599b1e34f1f4b7c6600a83913261645a0811fba0ad1ed104fe0c") / 2; i++) {
  //       printf("%02X ", proof_bytes.raw[i]);
  //       if ((i + 1) % 16 == 0) {
  //           printf("\n"); // Add a newline for readability after every 16 bytes
  //       }
  //   }
  //   printf("\n");
  ctt_eth_verkle_ipa_proof_aff proof;

  ctt_eth_verkle_ipa_status stat = ctt_eth_verkle_ipa_deserialize_aff(&proof, &proof_bytes);
  printf("ctt_eth_verkle_ipa_deserialize_aff: %d\n", stat);
//   printf("proof.g2_proof.l[0].x.limbs[0]: %lu\n", proof.g2_proof.l[0].x.limbs[0]);
  
  return 0;
}
