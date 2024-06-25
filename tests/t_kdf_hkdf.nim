# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/serialization/codecs,
  constantine/[hashes, mac/mac_hmac, kdf/kdf_hkdf]

proc hexToBytes(s: string): seq[byte] =
  if s.len > 0:
    var skip = 0
    if s.len >= 2:
      skip = 2*(
        int(s[0] == '0') and
        (int(s[1] == 'x') or int(s[1] == 'X'))
      )
    result.setLen((s.len - skip) div 2)
    result.paddedFromHex(s, bigEndian)

template test(id, constants: untyped) =
  proc `test _ id`() =
    # We create a proc to avoid allocating too much globals.
    constants

    let
      bikm = hexToBytes(IKM)
      bsalt = hexToBytes(salt)
      binfo = hexToBytes(info)
      bprk = hexToBytes(PRK)
      bokm = hexToBytes(OKM)

    var output = newSeq[byte](L)
    var ctx: HKDF[HashType]
    var prk: array[HashType.digestSize, byte]

    # let salt = if bsalt.len == 0: nil
    #            else: bsalt[0].unsafeAddr
    # let ikm = if bikm.len == 0: nil
    #           else: bikm[0].unsafeAddr
    # let info = if binfo.len == 0: nil
    #            else: binfo[0].unsafeAddr
    let
      salt = bsalt
      ikm = bikm
      info = binfo

    hkdfExtract(ctx, prk, salt, ikm)
    hkdfExpand(ctx, output, prk, info)

    doAssert @(prk) == bprk, "\nComputed     0x" & toHex(prk) &
                                  "\nbut expected " & PRK & '\n'
    doAssert output == bokm, "\nComputed     0x" & toHex(output) &
                              "\nbut expected " & OKM & '\n'
    echo "HKDF Test ", astToStr(id), " - SUCCESS"

  `test _ id`()

test 1: # Basic test case with SHA-256
  type HashType = sha256
  const
    IKM  = "0x0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"
    salt = "0x000102030405060708090a0b0c"
    info = "0xf0f1f2f3f4f5f6f7f8f9"
    L    = 42

    PRK  = "0x077709362c2e32df0ddc3f0dc47bba63" &
            "90b6c73bb50f9c3122ec844ad7c2b3e5"
    OKM  = "0x3cb25f25faacd57a90434f64d0362f2a" &
            "2d2d0a90cf1a5a4c5db02d56ecc4c5bf" &
            "34007208d5b887185865"

test 2: # Test with SHA-256 and longer inputs/outputs
  type HashType = sha256
  const
    IKM  =  "0x000102030405060708090a0b0c0d0e0f" &
            "101112131415161718191a1b1c1d1e1f" &
            "202122232425262728292a2b2c2d2e2f" &
            "303132333435363738393a3b3c3d3e3f" &
            "404142434445464748494a4b4c4d4e4f"
    salt =  "0x606162636465666768696a6b6c6d6e6f" &
            "707172737475767778797a7b7c7d7e7f" &
            "808182838485868788898a8b8c8d8e8f" &
            "909192939495969798999a9b9c9d9e9f" &
            "a0a1a2a3a4a5a6a7a8a9aaabacadaeaf"
    info =  "0xb0b1b2b3b4b5b6b7b8b9babbbcbdbebf" &
            "c0c1c2c3c4c5c6c7c8c9cacbcccdcecf" &
            "d0d1d2d3d4d5d6d7d8d9dadbdcdddedf" &
            "e0e1e2e3e4e5e6e7e8e9eaebecedeeef" &
            "f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff"
    L    = 82

    PRK  =  "0x06a6b88c5853361a06104c9ceb35b45c" &
            "ef760014904671014a193f40c15fc244"
    OKM  =  "0xb11e398dc80327a1c8e7f78c596a4934" &
            "4f012eda2d4efad8a050cc4c19afa97c" &
            "59045a99cac7827271cb41c65e590e09" &
            "da3275600c2f09b8367793a9aca3db71" &
            "cc30c58179ec3e87c14c01d5c1f3434f" &
            "1d87"

test 3: # Test with SHA-256 and zero-length salt/info
  type HashType = sha256
  const
    IKM  = "0x0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"
    salt = ""
    info = ""
    L    = 42

    PRK  = "0x19ef24a32c717b167f33a91d6f648bdf" &
            "96596776afdb6377ac434c1c293ccb04"
    OKM  = "0x8da4e775a563c18f715f802a063c5a31" &
            "b8a11f5c5ee1879ec3454e5f3c738d2d" &
            "9d201395faa4b61a96c8"
