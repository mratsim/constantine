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
  #constantine/signatures/ecdsa,
  constantine/ecdsa_secp256k1,
  constantine/named/algebras,
  constantine/math/io/[io_bigints, io_fields, io_ec],
  constantine/serialization/codecs

import
  std / [os, osproc, strutils, strformat, json]

type
  TestVector = object
    message: string # A hex string, which is fed as-is into OpenSSL, not the raw bytes incl 0x prefix
    privateKey: string
    publicKeyX: string
    publicKeyY: string
    r: string
    s: string

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

import ./openssl_wrapper
import constantine/math/arithmetic/finite_fields

proc toBytes[Name: static Algebra; N: static int](res: var array[N, byte], x: FF[Name]) =
  discard res.marshal(x.toBig(), bigEndian)

proc generateSignatures(num: int, msg = ""): seq[TestVector] =
  ## Generates `num` signatures.
  result = newSeq[TestVector](num)
  let dir = getTempDir()
  # temp filename for private key PEM file
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
    doAssert fromRawDER(rOSL, sOSL, osSig), "Deconstructing DER signature from OpenSSL failed: " & $osSig
    let (r, s) = (rOSL.toHex(), sOSL.toHex())

    let vec = TestVector(message: msg,
                         privateKey: privKey.toHex(),
                         publicKeyX: pubKey.x.toHex(),
                         publicKeyY: pubKey.y.toHex(),
                         r: r,
                         s: s)
    result[i] = vec

    # sanity check here that our data is actually good. Sign
    # and verify with CTT & verify just parsed OpenSSL sig
    let (rCTT, sCTT) = msg.signMessage(privKey)
    doAssert verifySignature(msg, (r: rCTT, s: sCTT), pubKey)
    doAssert verifySignature(msg, (r: Fr[C].fromHex(r), s: Fr[C].fromHex(s)), pubKey)

    #let rOS = Fr[C].fromHex(r)
    #let sOS = Fr[C].fromHex(s)
    #echo "SEQ based: ", toDERSeq(rOS, sOS)
    #var ds: DERSignature; toDER(ds, rOS, sOS)
    #echo "ARR based: ", @(ds.data)
    #
    #doAssert toDERSeq(rOS, sOS) == @(ds.data)[0 ..< ds.len]



# 1. generate 100 signatures with random messages, private keys and random nonces
let vecs1 = generateSignatures(100)
# 2. generate 10 signatures for the same message
let vecs2 = generateSignatures(10, "Hello, Constantine!")
#
writeFile("testVectors/ecdsa_openssl_signatures_random.json", (% vecs1).pretty())
writeFile("testVectors/ecdsa_openssl_signatures_fixed_msg.json", (% vecs2).pretty())
