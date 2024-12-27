##[
This is a helper program to generate ECDSA signatures using OpenSSL as a
set of test vectors for our implementation.

We generate test vectors following these cases:
- same message, different nonces -> different signature
- random message, random nonces

Further, generate signatures using Constantine, which we verify
with OpenSSL.
]##

import
  constantine/csprngs/sysrand,
  constantine/ecdsa_secp256k1,
  constantine/named/algebras,
  constantine/math/io/[io_bigints, io_fields, io_ec],
  constantine/serialization/codecs,
  constantine/math/arithmetic/finite_fields,
  constantine/platforms/abstractions

import ./openssl_wrapper

import
  std / [os, strutils, strformat, unittest]

proc generateMessage(len: int): string =
  ## Returns a randomly generated message of `len` bytes as a
  ## string of hex bytes.
  let len = min(1024, len) # maximum length, to fit into our array
  var buf: array[1024, byte]
  doAssert sysrand(buf)
  # Convert raw bytes to hex
  result = buf.toOpenArray[:byte](0, len - 1).toHex()

proc toHex(s: string): string =
  result = s.toOpenArrayByte(0, s.len-1).toHex()

proc toBytes[Name: static Algebra; N: static int](res: var array[N, byte], x: FF[Name]) =
  discard res.marshal(x.toBig(), bigEndian)

proc signAndVerify(num: int, msg = "", nonceSampler = nsRandom) =
  ## Generates `num` signatures and verify them against OpenSSL.
  ##
  ## If `msg` is given, use a fixed message. Otherwise will generate a message with
  ## a length up to 1024 bytes.
  for i in 0 ..< num:
    let msg = if msg.len > 0: msg else: generateMessage(64) # 64 byte long messages
    let privKey = generatePrivateKey()
    let pubKey = getPublicKey(privKey)

    # Get bytes of private key & initialize an OpenSSL key
    var skBytes: array[32, byte]
    skBytes.toBytes(privKey)
    var osSecKey: EVP_PKEY
    osSecKey.initPrivateKeyOpenSSL(skBytes)

    # Sign the message using OpenSSL
    var osSig: array[72, byte]
    osSig.signMessageOpenSSL(msg.toOpenArrayByte(0, msg.len-1), osSecKey)
    # Destructure the DER encoded signature into two arrays
    var rOSL: array[32, byte]
    var sOSL: array[32, byte]
    # And turn into hex strings
    check fromRawDER(rOSL, sOSL, osSig)
    let (r, s) = (rOSL.toHex(), sOSL.toHex())

    # sanity check here that our data is actually good. Sign
    # and verify with CTT & verify just parsed OpenSSL sig
    let (rCTT, sCTT) = msg.signMessage(privKey)
    check verifySignature(msg, (r: rCTT, s: sCTT), pubKey)
    check verifySignature(msg, (r: Fr[C].fromHex(r), s: Fr[C].fromHex(s)), pubKey)

proc signRfc6979(msg: string, num = 10) =
  ## Signs the given message with a randomly generated private key `num` times
  ## using deterministic nonce generation and verifies the signature comes out
  ## identical each time.

  var derSig: DERSignature[DERSigSize(Secp256k1)]

  let privKey = generatePrivateKey()
  let (r, s) = msg.signMessage(privKey, nonceSampler = nsRfc6979)
  for i in 0 ..< num:
    let (r2, s2) = msg.signMessage(privKey, nonceSampler = nsRfc6979)
    check bool(r == r2)
    check bool(s == s2)


suite "ECDSA over secp256k1":
  test "Verify OpenSSL generated signatures from a fixed message (different nonces)":
    signAndVerify(100, "Hello, Constantine!") # fixed message

  test "Verify OpenSSL generated signatures for different messages":
    signAndVerify(100) # randomly generated message

  test "Verify deterministic nonce generation via RFC6979 yields deterministic signatures":
    signRfc6979("Hello, Constantine!")
    signRfc6979("Foobar is 42")

#
