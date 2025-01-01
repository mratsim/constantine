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
  constantine/named/algebras,
  constantine/math/io/[io_bigints, io_fields, io_ec],
  constantine/serialization/[codecs, codecs_ecdsa, codecs_ecdsa_secp256k1],
  constantine/math/arithmetic/[bigints, finite_fields],
  constantine/platforms/abstractions,
  constantine/ecdsa_secp256k1

when not defined(windows):
  # Windows (at least in GH actions CI) does not provide, among others `BN_new`
  # so we disable this test for Windows for the time being.
  import ../openssl_wrapper

import
  std / [os, osproc, strutils, strformat, unittest, importutils]

const C = Secp256k1

proc randomFieldElement[FF](): FF =
  ## random element in ~Fp[T]/Fr[T]~
  let m = FF.getModulus()
  var b: matchingBigInt(FF.Name)

  while b.isZero().bool or (b > m).bool:
    ## XXX: raise / what else to do if `sysrand` call fails?
    doAssert b.limbs.sysrand()

  result.fromBig(b)

proc generatePrivateKey(): SecretKey {.noinit.} =
  ## Generate a new private key using a cryptographic random number generator.
  privateAccess(SecretKey)
  result = SecretKey(raw: randomFieldElement[Fr[C]]())

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

func getPublicKey(secKey: SecretKey): PublicKey {.noinit.} =
  result.derive_pubkey(secKey)

template toOA(x: string): untyped = toOpenArrayByte(x, 0, x.len-1)

when not defined(windows): # see above
  proc signAndVerify(num: int, msg = "", nonceSampler = nsRandom) =
    ## Generates `num` signatures and verify them against OpenSSL.
    ##
    ## If `msg` is given, use a fixed message. Otherwise will generate a message with
    ## a length up to 1024 bytes.
    ##
    ## As a side effect it also verifies our `fromDER` parser and as an additional
    ## sanity check our `toDER` converter.
    for i in 0 ..< num:
      let msg = if msg.len > 0: msg else: generateMessage(64) # 64 byte long messages
      let secKey = generatePrivateKey()
      let pubKey = getPublicKey(secKey)

      # Get bytes of private key & initialize an OpenSSL key
      var skBytes: array[32, byte]
      privateAccess(SecretKey) # access to `raw`
      skBytes.toBytes(secKey.raw)
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
      # Convert to scalar and verify signature
      let (rOslFr, sOslFr) = (Fr[C].fromHex(r), Fr[C].fromHex(s))
      privateAccess(Signature) # make `r`, `s` accessible in scope
      let sigOsl = Signature(r: rOslFr, s: sOslFr)
      check pubKey.verify(toOA msg, sigOsl)
      # Now also sign with CTT and verify
      var sigCTT {.noinit.}: Signature
      sigCTT.sign(secKey, toOA msg)
      check pubKey.verify(toOA msg, sigCTT)

      # Verify that we can generate a DER signature again from the OpenSSL
      # data and it is equivalent to original
      var derSig: DerSignature[DerSigSize(Secp256k1)]
      derSig.toDER(rOslFr, sOslFr)
      check derSig.data == osSig

  proc verifyPemWriter(num: int, msg = "") =
    ## We verify our PEM writers in a bit of a roundabout way.
    ##
    ## TODO: Ideally we would simply write a given raw private and public key
    ## using the C API of OpenSSL and compare writing the same key using
    ## our serialization logic.
    let dir = getTempDir()
    # temp filename for private key PEM file
    let pubKeyFile = dir / "public_key.pem"
    let secKeyFile = dir / "private_key.pem"
    let sigFile = dir / "msg.sig"
    for i in 0 ..< num:
      let msg = if msg.len > 0: msg else: generateMessage(64) # 64 byte long messages
      let secKey = generatePrivateKey()
      let pubKey = getPublicKey(secKey)

      writeFile(secKeyFile, toPem(secKey))
      writeFile(pubKeyFile, toPem(pubKey))

      # Write a PEM file for public and private key using CTT and use it
      # to sign and verify a message.
      # NOTE: I tried using OpenSSL's C API, but couldn't get it to work
      # 1. Sign using the private key and message
      let sign = &"echo -n '{msg}' | openssl dgst -sha256 -sign {secKeyFile} -out {sigFile}"
      let (resS, errS) = execCmdEx(sign)
      check errS == 0

      # 2. Verify using public key
      let verify = &"echo -n '{msg}' | openssl dgst -sha256 -verify {pubKeyFile} -signature {sigFile}"
      let (resV, errV) = execCmdEx(verify)
      check errV == 0

  proc signRfc6979(msg: string, num = 10) =
    ## Signs the given message with a randomly generated private key `num` times
    ## using deterministic nonce generation and verifies the signature comes out
    ## identical each time.
    var derSig: DerSignature[DerSigSize(Secp256k1)]

    let secKey = generatePrivateKey()
    var sig {.noinit.}: Signature
    sig.sign(secKey, toOA msg, nonceSampler = nsRfc6979)
    for i in 0 ..< num:
      var sig2 {.noinit.}: Signature
      sig2.sign(secKey, toOA msg, nonceSampler = nsRfc6979)
      check signatures_are_equal(sig, sig2)

  suite "General ECDSA related tests":
    test "DERSigSize correctly computes maximum size of DER encoded signature":
      # Check that `DerSigSize` correctly computes the maximum DER encoded signature
      # based on the size of the scalar
      check DerSigSize(Secp256k1) == 72 # 256 bit subgroup order -> 32 byte scalars
      check DerSigSize(P256) == 72 # 256 bit subgroup order
      check DerSigSize(Edwards25519) == 72 # 253 bits subgroup order, fits 256 bit BigInt
      check DerSigSize(BLS12_381) == 72 # not commonly used, but larger modulo but *same* subgroup order
      check DerSigSize(P224) == 64 # 224 bit subgroup order -> 28 byte scalars
      check DerSigSize(BW6_761) == 104 # not commonly used, but larger modulo with *larger* subgroup order
                                       # 377 bit subgroup order -> 384 BigInt -> 48 byte scalars

  suite "ECDSA over secp256k1":
    test "Verify OpenSSL generated signatures from a fixed message (different nonces)":
      signAndVerify(100, "Hello, Constantine!") # fixed message

    test "Verify OpenSSL generated signatures for different messages":
      signAndVerify(100) # randomly generated message

    test "Verify deterministic nonce generation via RFC6979 yields deterministic signatures":
      signRfc6979("Hello, Constantine!")
      signRfc6979("Foobar is 42")

    test "Verify PEM file serialization for public and private keys":
      verifyPemWriter(100)
