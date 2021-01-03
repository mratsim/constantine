# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../constantine/hashes,
  ../constantine/hash_to_curve/hash_to_field,
  # Third-party
  stew/byteutils

# Test vectors for expandMessageXMD
# ----------------------------------------------------------------------

template testExpandMessageXMD(id, constants: untyped) =
  # Section "Expand test vectors {#expand-testvectors}"
  # https://tools.ietf.org/html/draft-irtf-cfrg-hash-to-curve-09#appendix-I.1
  proc `testExpandMessageXMD_sha256 _ id`() =
    # We create a proc to avoid allocating to much globals/
    constants

    var uniform_bytes: array[len_in_bytes, byte]
    sha256.expandMessageXMD(
      uniform_bytes,
      augmentation = "",
      msg,
      "QUUX-V01-CS02-with-expander"
    )

    doAssert uniform_bytes == expectedBytes, ( "\n" &
      "Expected " & toHex(expectedBytes) & "\n" &
      "Computed " & toHex(uniform_bytes)
    )

    echo "Success sha256.expandMessageXMD ", astToStr(id)

  `testExpandMessageXMD_sha256 _ id`()

testExpandMessageXMD(1):
  let msg = ""
  const expected = "f659819a6473c1835b25ea59e3d38914c98b374f0970b7e4c92181df928fca88"
  const len_in_bytes = expected.len div 2
  const expectedBytes = hexToByteArray[len_in_bytes](expected)

testExpandMessageXMD(2):
  let msg = "abc"
  const expected = "1c38f7c211ef233367b2420d04798fa4698080a8901021a795a1151775fe4da7"
  const len_in_bytes = expected.len div 2
  const expectedBytes = hexToByteArray[len_in_bytes](expected)

testExpandMessageXMD(3):
  let msg = "abcdef0123456789"
  const expected = "8f7e7b66791f0da0dbb5ec7c22ec637f79758c0a48170bfb7c4611bd304ece89"
  const len_in_bytes = expected.len div 2
  const expectedBytes = hexToByteArray[len_in_bytes](expected)

testExpandMessageXMD(4):
  let msg = "q128_qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq" &
            "qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq" &
            "qqqqqqqqqqqqqqqqqqqqqqqqq"
  const expected = "72d5aa5ec810370d1f0013c0df2f1d65699494ee2a39f72e1716b1b964e1c642"
  const len_in_bytes = expected.len div 2
  const expectedBytes = hexToByteArray[len_in_bytes](expected)

testExpandMessageXMD(5):
  let msg = "a512_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  const expected = "3b8e704fc48336aca4c2a12195b720882f2162a4b7b13a9c350db46f429b771b"
  const len_in_bytes = expected.len div 2
  const expectedBytes = hexToByteArray[len_in_bytes](expected)

testExpandMessageXMD(6):
  let msg = ""
  const expected = "8bcffd1a3cae24cf9cd7ab85628fd111bb17e3739d3b53f8" &
                    "9580d217aa79526f1708354a76a402d3569d6a9d19ef3de4d0b991" &
                    "e4f54b9f20dcde9b95a66824cbdf6c1a963a1913d43fd7ac443a02" &
                    "fc5d9d8d77e2071b86ab114a9f34150954a7531da568a1ea8c7608" &
                    "61c0cde2005afc2c114042ee7b5848f5303f0611cf297f"
  const len_in_bytes = expected.len div 2
  const expectedBytes = hexToByteArray[len_in_bytes](expected)

testExpandMessageXMD(7):
  let msg = "abc"
  const expected = "fe994ec51bdaa821598047b3121c149b364b178606d5e72b" &
                    "fbb713933acc29c186f316baecf7ea22212f2496ef3f785a27e84a" &
                    "40d8b299cec56032763eceeff4c61bd1fe65ed81decafff4a31d01" &
                    "98619c0aa0c6c51fca15520789925e813dcfd318b542f879944127" &
                    "1f4db9ee3b8092a7a2e8d5b75b73e28fb1ab6b4573c192"
  const len_in_bytes = expected.len div 2
  const expectedBytes = hexToByteArray[len_in_bytes](expected)

testExpandMessageXMD(8):
  let msg = "abcdef0123456789"
  const expected = "c9ec7941811b1e19ce98e21db28d22259354d4d0643e3011" &
                    "75e2f474e030d32694e9dd5520dde93f3600d8edad94e5c3649030" &
                    "88a7228cc9eff685d7eaac50d5a5a8229d083b51de4ccc3733917f" &
                    "4b9535a819b445814890b7029b5de805bf62b33a4dc7e24acdf2c9" &
                    "24e9fe50d55a6b832c8c84c7f82474b34e48c6d43867be"
  const len_in_bytes = expected.len div 2
  const expectedBytes = hexToByteArray[len_in_bytes](expected)

testExpandMessageXMD(9):
  let msg = "q128_qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq" &
            "qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq" &
            "qqqqqqqqqqqqqqqqqqqqqqqqq"
  const expected = "48e256ddba722053ba462b2b93351fc966026e6d6db49318" &
                    "9798181c5f3feea377b5a6f1d8368d7453faef715f9aecb078cd40" &
                    "2cbd548c0e179c4ed1e4c7e5b048e0a39d31817b5b24f50db58bb3" &
                    "720fe96ba53db947842120a068816ac05c159bb5266c63658b4f00" &
                    "0cbf87b1209a225def8ef1dca917bcda79a1e42acd8069"
  const len_in_bytes = expected.len div 2
  const expectedBytes = hexToByteArray[len_in_bytes](expected)

testExpandMessageXMD(10):
  let msg = "a512_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  const expected = "396962db47f749ec3b5042ce2452b619607f27fd3939ece2" &
                    "746a7614fb83a1d097f554df3927b084e55de92c7871430d6b95c2" &
                    "a13896d8a33bc48587b1f66d21b128a1a8240d5b0c26dfe795a1a8" &
                    "42a0807bb148b77c2ef82ed4b6c9f7fcb732e7f94466c8b51e52bf" &
                    "378fba044a31f5cb44583a892f5969dcd73b3fa128816e"
  const len_in_bytes = expected.len div 2
  const expectedBytes = hexToByteArray[len_in_bytes](expected)
