# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/unittest,
  constantine/mac/mac_hmac,
  constantine/hashes,
  constantine/serialization/codecs

type TestVector = object
  key: seq[byte]
  data: seq[byte]
  digest: array[32, byte]
  truncatedLen: int

proc doTest(key, data, digest: string) =
  var tv: TestVector

  doAssert (key.len and 1) == 0, "An hex string must be of even length"
  doAssert (data.len and 1) == 0, "An hex string must be of even length"
  doAssert (digest.len and 1) == 0, "An hex string must be of even length"
  doAssert digest.len <= 64, "HMAC-SHA256 hex string must be at most length 64 (32 bytes)"

  tv.key.newSeq(key.len div 2)
  tv.key.paddedFromHex(key, bigEndian)

  tv.data.newSeq(data.len div 2)
  tv.data.paddedFromHex(data, bigEndian)

  tv.truncatedLen = digest.len div 2
  tv.digest.paddedFromHex(digest, bigEndian)

  var output{.noInit.}: array[32, byte]

  HMAC[sha256].mac(output, tv.data, tv.key)
  doAssert tv.digest.toOpenArray(tv.digest.len-tv.truncatedLen, tv.digest.len-1) == output.toOpenArray(0, tv.truncatedLen-1)


suite "[Message Authentication Code] HMAC-SHA256":
  test "Test vector 1 - RFC4231":
    doTest(
      key = "0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b",
      data = "4869205468657265",
      digest = "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
    )
  test "Test vector 2 - RFC4231":
    doTest(
      key = "4a656665",
      data = "7768617420646f2079612077616e7420666f72206e6f7468696e673f",
      digest = "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
    )
  test "Test vector 3 - RFC4231":
    doTest(
      key = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      data = "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
      digest = "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe"
    )
  test "Test vector 4 - RFC4231":
    doTest(
      key = "0102030405060708090a0b0c0d0e0f10111213141516171819",
      data = "cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd",
      digest = "82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b"
    )
  test "Test vector 5 - RFC4231":
    doTest(
      key = "0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c",
      data = "546573742057697468205472756e636174696f6e",
      digest = "a3b6167473100ee06e0c796c2955552b"
    )
  test "Test vector 6 - RFC4231":
    doTest(
      key = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaa",
      data = "54657374205573696e67204c61726765" &
             "72205468616e20426c6f636b2d53697a" &
             "65204b6579202d2048617368204b6579" &
             "204669727374",
      digest = "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"
    )
  test "Test vector 7 - RFC4231":
    doTest(
      key = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaa",
      data = "54686973206973206120746573742075" &
             "73696e672061206c6172676572207468" &
             "616e20626c6f636b2d73697a65206b65" &
             "7920616e642061206c61726765722074" &
             "68616e20626c6f636b2d73697a652064" &
             "6174612e20546865206b6579206e6565" &
             "647320746f2062652068617368656420" &
             "6265666f7265206265696e6720757365" &
             "642062792074686520484d414320616c" &
             "676f726974686d2e",
      digest = "9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2"
    )
