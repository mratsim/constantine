##[
This test case verifies signatures generated by OpenSSL in the
`generate_signatures.nim` script.
]##

import
  constantine/csprngs/sysrand,
  #constantine/signatures/ecdsa,
  constantine/ecdsa_secp256k1,
  constantine/named/algebras,
  constantine/math/elliptic/[ec_shortweierstrass_affine],
  constantine/math/io/[io_bigints, io_fields, io_ec],
  constantine/serialization/codecs

import
  std / [os, osproc, strformat, json, unittest]

type
  TestVector = object
    message: string # A hex string, which is fed as-is into OpenSSL, not the raw bytes incl 0x prefix
    privateKey: string
    publicKeyX: string
    publicKeyY: string
    r: string
    s: string

  TestVectorCTT = object
    message: string
    privateKey: Fr[C]
    publicKey: EC_ShortW_Aff[Fp[C], G1]
    r: Fr[C]
    s: Fr[C]

proc parseSignatureFile(f: string): seq[TestVector] =
  result = f.readFile.parseJson.to(seq[TestVector])

proc parseTestVector(vec: TestVector): TestVectorCTT =
  result = TestVectorCTT(
    message: vec.message,
    privateKey: Fr[C].fromHex(vec.privateKey),
    publicKey: EC_ShortW_Aff[Fp[C], G1].fromHex(vec.publicKeyX, vec.publicKeyY),
    r: Fr[C].fromHex(vec.r),
    s: Fr[C].fromHex(vec.s))


suite "ECDSA over secp256k1":
  test "Verify OpenSSL generated signatures from a fixed message (different nonces)":
    let vecs = parseSignatureFile("testVectors/ecdsa_openssl_signatures_fixed_msg.json")

    for vec in vecs:
      let vctt = vec.parseTestVector()
      # verify the signature
      check verifySignature(vctt.message, (r: vctt.r, s: vctt.s), vctt.publicKey)

  test "Verify OpenSSL generated signatures for different messages":
    let vecs = parseSignatureFile("testVectors/ecdsa_openssl_signatures_random.json")

    for vec in vecs:
      let vctt = vec.parseTestVector()
      # verify the signature
      check verifySignature(vctt.message, (r: vctt.r, s: vctt.s), vctt.publicKey)
