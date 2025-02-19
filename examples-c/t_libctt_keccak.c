/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at
 * http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at
 * http://www.apache.org/licenses/LICENSE-2.0). at your option. This file may
 * not be copied, modified, or distributed except according to those terms.
 */

#include "constantine/hashes/keccak256.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

#include <constantine.h>

int from_hex(byte *dst, size_t dst_len, const char *hex_src, size_t src_len) {
  // converts the given `hex_src` to a byte buffer. `buffer` must already be
  // allocated to len(hex_src) // 2!
  if (src_len % 2 != 0)
    return -1; // Length must be even
  else if (dst_len * 2 != src_len)
    return -1; // dest length must be half src len

  for (size_t i = 0; i < dst_len; i++) {
    if (sscanf(&hex_src[i * 2], "%2hhx", &dst[i]) != 1) {
      return -(i + 1); // Failed to convert hex to byte
    }
  }
  return 0; // Success
}

int compare_binary(const byte *buf1, size_t len1, const byte *buf2,
                   size_t len2) {
  // compares the two binary buffers with length len1 and len2 byte by byte.
  if (len1 != len2) {
    return -1; // mismatching length
  }
  for (size_t i = 0; i < len1; i++) {
    if (buf1[i] != buf2[i]) {
      return -(i + 1); // found a mismatched byte
    }
  }
  return 0; // success
}

int main() {
  byte result[32] = {0};

  const char input[] = "abc";
  const char expected_str[] =
      "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45";
  byte expected[32];
  from_hex(expected, 32, expected_str, 64);

  // Note: string inputs have an hidden \n that needs to be skipped
  ctt_keccak256_hash(result, input, sizeof(input) - 1, 0);

  int check = compare_binary(result, 32, expected, 32);
  if (check != 0) {
    printf("Unexpected Keccak byte in result: %d\n", check);
    exit(1);
  }
  printf("Keccak success\n");
  exit(0);
}
