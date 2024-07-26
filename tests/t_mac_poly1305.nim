# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/unittest,
  constantine/mac/mac_poly1305

suite "[Message Authentication Code] Poly1305":
  test "Test vector 1 - RFC8439":
    let ikm = [
      byte 0x85, 0xd6, 0xbe, 0x78, 0x57, 0x55, 0x6d, 0x33,
           0x7f, 0x44, 0x52, 0xfe, 0x42, 0xd5, 0x06, 0xa8,
           0x01, 0x03, 0x80, 0x8a, 0xfb, 0x0d, 0xb2, 0xfd,
           0x4a, 0xbf, 0xf6, 0xaf, 0x41, 0x49, 0xf5, 0x1b
    ]
    let message = "Cryptographic Forum Research Group"

    let expectedTag = [
      byte 0xa8, 0x06, 0x1d, 0xc1, 0x30, 0x51, 0x36, 0xc6,
           0xc2, 0x2b, 0x8b, 0xaf, 0x0c, 0x01, 0x27, 0xa9
    ]

    var tag: array[16, byte]
    poly1305.mac(tag, message, ikm)

    doAssert tag == expectedTag
