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

proc toNormalizedHex(s: string): string =
  ## Takes a string of raw bytes, removes additional empty bytes
  ## (length of 33 bytes) or adds bytes (length < 32 bytes) and
  ## then converts them to a hex string.
  var s = s
  if s.len == 33:
    doAssert s[0] == '\0', "No, got: " & $s[0]
    s = s[1 ..< s.len]
  let toAdd = 32 - s.len
  if toAdd < 0:
    raiseAssert "Invalid input of length: " & $s.len & ": " & s
  let prefix = repeat('\0', toAdd)
  s = prefix & s
  doAssert s.len == 32
  result = s.toOpenArrayByte(0, s.len-1).toHex()

proc parseSignature(derSig: string): tuple[r, s: string] =
  ## Parses a signature given in raw ASN.1 DER (SEC1)
  ## raw bytes to the individual `r` and `s` elements.
  ## The elements `r` and `s` are returned as hex strings.
  ##
  ## Note: the `r` or `s` values are 33 bytes long, if the leading
  ## bit is `1` to clarify that the number is positive (a prefix
  ## `0` byte is added). In our case we just parse 32 or 33 bytes,
  ## because we don't care about a leading zero byte.
  doAssert derSig[0] == '\48' # SEQUENCE
  ## XXX: replace by maximum length 70! Can be anything larger than 2 really (1 for r and s)
  doAssert derSig[1] in {'\67', '\68', '\69', '\70'} # 68-70 bytes long (depending on 0, 1, 2 zero prefixes)
  doAssert derSig[2] == '\02' # INTEGER tag
  let lenX = ord(derSig[3])
  doAssert lenX <= 33, "Found length: " & $lenX  # Length of integer, 32 or 33 bytes
  let toX = 4 + lenX
  let r = derSig[4 ..< toX]
  doAssert derSig[toX] == '\02' # INTEGER tag
  let lenY = ord(derSig[toX + 1])
  doAssert lenY <= 33, "Found length: " & $lenX  # Length of integer, 32 or 33 bytes
  let toY = toX + 2 + lenY
  let s = derSig[toX + 2 ..< toY]
  doAssert toY == derSig.len
  # Convert raw byte strings to hex strings.
  result = (r: r.toNormalizedHex(), s: s.toNormalizedHex())

proc generateSignatures(num: int, msg = ""): seq[TestVector] =
  ## Generates `num` signatures.
  result = newSeq[TestVector](num)
  let dir = getTempDir()
  # temp filename for private key PEM file
  let privKeyFile = dir / "private_key.pem"
  let sigFile = dir / "message.sig"
  for i in 0 ..< num:
    let msg = if msg.len > 0: msg else: generateMessage(64) # 64 byte long messages
    let privKey = generatePrivateKey()
    let pubKey = getPublicKey(privKey)

    # convert private key to a PEM file and write as temp
    writeFile(privKeyFile, toPemFile(privKey))

    discard toPemFile(pubKey)

    # NOTE: We treat the *hex string* as the message, not the raw bytes,
    # including the `0x` prefix!
    let cmd = &"echo -n '{msg}' | openssl dgst -sha256 -sign {privKeyFile} -out {sigFile}"
    let (res, error) = execCmdEx(cmd)

    # extract raw signature
    let (r, s) = sigFile.readFile.parseSignature
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
#writeFile("testVectors/ecdsa_openssl_signatures_random.json", (% vecs1).pretty())
#writeFile("testVectors/ecdsa_openssl_signatures_fixed_msg.json", (% vecs2).pretty())
