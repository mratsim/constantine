import
  ../hashes/h_sha256,
  ../named/algebras,
  ../math/io/[io_bigints, io_fields, io_ec],
  ../math/elliptic/[ec_shortweierstrass_affine, ec_shortweierstrass_jacobian, ec_scalar_mul],
  ../math/arithmetic,
  ../platforms/abstractions,
  ../serialization/codecs, # for fromHex and (in the future) base64 encoding
  ../mac/mac_hmac, # for deterministic nonce generation via RFC 6979
  ../named/zoo_generators, # for generator
  ../csprngs/sysrand

import std / macros # for `update` convenience helper

type
  ## Decides the type of sampler we use for the nonce. By default
  ## a simple uniform random sampler. Alternatively a deterministic
  ## sampler based on message hash and private key.
  NonceSampler* = enum
    nsRandom, ## pure uniform random sampling
    nsRfc6979 ## deterministic according to RFC 6979

# For easier readibility, define the curve and generator
# as globals in this file
const C* = Secp256k1
const G = Secp256k1.getGenerator("G1")

proc hashMessage(message: string): array[32, byte] =
  # Hash a given message
  var h {.noinit.}: sha256
  h.init()
  h.update(message)
  h.finish(result)

proc toBytes(x: Fr[C] | Fp[C]): array[32, byte] =
  let bi = x.toBig()
  discard result.marshal(bi, bigEndian)

proc toDER*(r, s: Fr[C]): seq[byte] =
  ## Converts the given signature `(r, s)` into a signature in
  ## ASN.1 DER encoding following SEC1.
  ##
  ## Note that the implementation is not written for efficiency
  ## and should be viewed as a convenience tool for the time being.
  # Convert signature to DER format
  result = @[byte(0x30)]  # sequence marker

  # Convert r and s to big-endian bytes
  var rBytes = @(r.toBytes())
  var sBytes = @(s.toBytes())

  # Add padding if needed (if high bit is set)
  if (rBytes[0] and 0x80) != 0:
    rBytes = @[byte(0)] & rBytes
  if (sBytes[0] and 0x80) != 0:
    sBytes = @[byte(0)] & sBytes

  # Add integer markers and lengths
  let rEncoded = @[byte(0x02), byte(rBytes.len)] & rBytes
  let sEncoded = @[byte(0x02), byte(sBytes.len)] & sBytes

  # Total length
  let totalLen = rEncoded.len + sEncoded.len
  result.add(byte(totalLen))

  # Add r and s encodings
  result.add(rEncoded)
  result.add(sEncoded)

func fromDigest(dst: var Fr[C], src: array[32, byte]): bool {.discardable.} =
  ## Convert a SHA256 digest to an element in the scalar field `Fr[Secp256k1]`.
  ## The proc returns a boolean indicating whether the data in `src` is
  ## smaller than the field modulus. It is discardable, because in some
  ## use cases this is fine (e.g. constructing a field element from a hash),
  ## but invalid in the nonce generation following RFC6979.
  var scalar {.noInit.}: BigInt[256]
  scalar.unmarshal(src, bigEndian)
  # `true` if smaller than modulus
  result = bool(scalar < Fr[C].getModulus())
  dst.fromBig(scalar)

proc randomFieldElement[FF](): FF =
  ## random element in ~Fp[T]/Fr[T]~
  let m = FF.getModulus()
  var b: matchingBigInt(FF.Name)

  while b.isZero().bool or (b > m).bool:
    ## XXX: raise / what else to do if `sysrand` call fails?
    doAssert b.limbs.sysrand()

  result.fromBig(b)

proc arrayWith[N: static int](val: byte): array[N, byte] =
  for i in 0 ..< N:
    result[i] = val

macro update[T](hmac: var HMAC[T], args: varargs[untyped]): untyped =
  ## Mini helper to allow HMAC to act on multiple arguments in succession
  result = newStmtList()
  for arg in args:
    result.add quote do:
      `hmac`.update(`arg`)

template round(hmac, input, output: typed, args: varargs[untyped]): untyped =
  ## Perform a full 'round' of HMAC. Pre-shared secret is `input`, the
  ## result will be stored in `output`. All `args` are fed into the HMAC
  ## in the order they are given.
  hmac.init(input)
  hmac.update(args)
  hmac.finish(output)

proc nonceRfc6979(msgHash, privateKey: Fr[C]): Fr[C] =
  ## Generate deterministic nonce according to RFC 6979.
  ##
  ## Spec:
  ## https://datatracker.ietf.org/doc/html/rfc6979#section-3.2
  # Step a: `h1 = H(m)` hash message (already done, input is hash), convert to array of bytes
  let msgHashBytes = msgHash.toBytes()
  # Piece of step d: Conversion of the private key to a byte array.
  # No need for `bits2octets`, because the private key is already a valid
  # scalar in the field `Fr[C]` and thus < p-1 (`bits2octets` converts
  # `r` bytes to a BigInt, reduces modulo prime order `p` and converts to
  # a byte array).
  let privKeyBytes = privateKey.toBytes()

  # Initial values
  # Step b: `V = 0x01 0x01 0x01 ... 0x01`
  var v = arrayWith[32](byte 0x01)
  # Step c: `K = 0x00 0x00 0x00 ... 0x00`
  var k = arrayWith[32](byte 0x00)

  # Create HMAC contexts
  var hmac {.noinit.}: HMAC[sha256]

  # Step d: `K = HMAC_K(V || 0x00 || int2octets(x) || bits2octets(h1))`
  hmac.round(k, k, v, [byte 0x00], privKeyBytes, msgHashBytes)
  # Step e: `V = HMAC_K(V)`
  hmac.round(k, v, v)
  # Step f: `K = HMAC_K(V || 0x01 || int2octets(x) || bits2octets(h1))`
  hmac.round(k, k, v, [byte 0x01], privKeyBytes, msgHashBytes)
  # Step g: `V = HMAC_K(V)`
  hmac.round(k, v, v)
  # Step h: Loop until valid nonce found
  while true:
    # Step h.1 (init T to zero) and h.2:
    # `V = HMAC_K(V)`
    # `T = T || V`
    # We do not need to accumulate a `T`, because we use SHA256 as a hash
    # function (256 bits) and Secp256k1 as a curve (also 256 big int).
    hmac.round(k, v, v) # v becomes T

    # Step h.3: `k = bits2int(T)`
    var candidate: Fr[C]
    # `fromDigest` returns `false` if the array is larger than the field modulus,
    # important for uniform sampling in valid range `[1, q-1]`!
    let smaller = candidate.fromDigest(v)

    if not bool(candidate.isZero()) and smaller:
      return candidate

    # Step h.3 failure state:
    # `K = HMAC_K(V || 0x00)`
    # `V = HMAC_K(V)`
    # Try again if invalid
    hmac.round(k, k, v, [byte 0x00])
    hmac.round(k, v, v)

proc generateNonce(kind: NonceSampler, msgHash, privateKey: Fr[C]): Fr[C] =
  case kind
  of nsRandom: randomFieldElement[Fr[C]]()
  of nsRfc6979: nonceRfc6979(msgHash, privateKey)

proc signMessage*(message: string, privateKey: Fr[C],
                  nonceSampler: NonceSampler = nsRandom): tuple[r, s: Fr[C]] =
  ## Sign a given `message` using the `privateKey`.
  ##
  ## By default we use a purely random nonce (uniform random number),
  ## but passing `nonceSampler = nsRfc6979` uses RFC 6979 to compute
  ## a deterministic nonce (and thus deterministic signature) given
  ## the message and private key as base.
  # 1. hash the message in big endian order
  let h = hashMessage(message)
  var message_hash: Fr[C]
  message_hash.fromDigest(h)

  # loop until we found a valid (non zero) signature
  while true:
    # Generate random nonce
    var k = generateNonce(nonceSampler, message_hash, privateKey)

    # Calculate r (x-coordinate of kG)
    # `r = k·G (mod n)`
    let r_point = k * G
    # get x coordinate of the point `r` *in affine coordinates*
    let rx = r_point.getAffine().x # element of Fp
    ## XXX: smarter way for this?
    let r = Fr[C].fromBig(rx.toBig())

    if bool(r.isZero()):
      continue # try again

    # Calculate s
    # `s = (k⁻¹ · (h + r · p)) (mod n)`
    # with `h`: message hash as `Fr[C]` (if we didn't use SHA256 w/ 32 byte output
    # we'd need to truncate to N bits for N being bits in modulo `n`)
    k.inv()
    var s = (k * (message_hash + r * privateKey))
    # get inversion of `s` for 'lower-s normalization'
    var sneg = s # inversion of `s`
    sneg.neg()   # q - s
    # conditionally assign result based on BigInt comparison
    let mask = s.toBig() > sneg.toBig() # if true, `s` is in upper half, need `sneg`
    ccopy(s, sneg, mask)

    if bool(s.isZero()):
      continue # try again

    return (r: r, s: s)

proc verifySignature*(
    message: string,
    signature: tuple[r, s: Fr[C]],
    publicKey: EC_ShortW_Aff[Fp[C], G1]
): bool =
  ## Verify a given `signature` for a `message` using the given `publicKey`.
  # 1. Hash the message (same as in signing)
  let h = hashMessage(message)
  var e: Fr[C]
  e.fromDigest(h)

  # 2. Compute w = s⁻¹
  var w = signature.s
  w.inv() # w = s⁻¹

  # 3. Compute u₁ = ew and u₂ = rw
  let u1 = e * w
  let u2 = signature.r * w

  # 4. Compute u₁G + u₂Q
  let point1 = u1 * G
  let point2 = u2 * publicKey
  let R = point1 + point2

  # 5. Get x coordinate and convert to Fr (like in signing)
  let x = R.getAffine().x
  let r_computed = Fr[C].fromBig(x.toBig())

  # 6. Verify r_computed equals provided r
  result = bool(r_computed == signature.r)

proc getPrivateKey*(): Fr[C] =
  ## Generate a new private key using a cryptographic random number generator.
  result = randomFieldElement[Fr[C]]()

proc toPemPrivateKey(privateKey: Fr[C]): seq[byte] =
  # Start with SEQUENCE
  result = @[byte(0x30)]

  # Version (always 1)
  let version = @[byte(0x02), byte(1), byte(1)]

  # Private key as octet string
  let privKeyBytes = privateKey.toBytes()
  let privKeyEncoded = @[byte(0x04), byte(privKeyBytes.len)] & @privKeyBytes

  # Parameters (secp256k1 OID: 1.3.132.0.10)
  let parameters = @[byte(0xA0), byte(7), byte(6), byte(5),
                     byte(0x2B), byte(0x81), byte(0x04), byte(0x00), byte(0x0A)]

  # Combine all parts
  let contents = version & privKeyEncoded & parameters
  result.add(byte(contents.len))
  result.add(contents)

proc toPemPublicKey(publicKey: EC_ShortW_Aff[Fp[C], G1]): seq[byte] =
  # Start with SEQUENCE
  result = @[byte(0x30)]

  # Algorithm identifier
  let algoId = @[
    byte(0x30), byte(0x10),                    # SEQUENCE
    byte(0x06), byte(0x07),                    # OID for EC
    byte(0x2A), byte(0x86), byte(0x48),        # 1.2.840.10045.2.1
    byte(0xCE), byte(0x3D), byte(0x02), byte(0x01),
    byte(0x06), byte(0x05),                    # OID for secp256k1
    byte(0x2B), byte(0x81), byte(0x04), byte(0x00), byte(0x0A) # 1.3.132.0.10
  ]

  # Public key as bit string
  let pubKeyBytes = @[
    byte(0x00),  # DER BIT STRING: number of unused bits (always 0 for keys)
    byte(0x04)   # SEC1: uncompressed point format marker
  ] & @(publicKey.x.toBytes()) & @(publicKey.y.toBytes()) # x & y coordinates

  let pubKeyEncoded = @[byte(0x03), byte(pubKeyBytes.len)] & pubKeyBytes

  # Combine all parts
  let contents = algoId & pubKeyEncoded
  result.add(byte(contents.len))
  result.add(contents)

## NOTE:
## The below procs / code is currently "unsuited" for Constantine in the sense that
## it currently still contains stdlib dependencies. Most of those are trivial, with the
## exception of a base64 encoder.
## Having a ANS1.DER encoder (and maybe decoder in the future) for SEC1 private and
## public keys would be nice to have in CTT, I think (at least for the curves that
## we support for the related operations; secp256k1 at the moment).

## XXX: Might also need to replace this by header / tail approach to avoid
## stdlib `%`!
import std / [strutils, base64, math]
const PrivateKeyTmpl = """-----BEGIN EC PRIVATE KEY-----
$#
-----END EC PRIVATE KEY-----
"""
const PublicKeyTmpl = """-----BEGIN PUBLIC KEY-----
$#
-----END PUBLIC KEY-----
"""

proc wrap(s: string, maxLineWidth = 64): string =
  ## Wrap the given string at `maxLineWidth` over multiple lines
  let lines = s.len.ceilDiv maxLineWidth
  result = newStringOfCap(s.len + lines)
  for i in 0 ..< lines:
    let frm = i * maxLineWidth
    let to = min(s.len, (i+1) * maxLineWidth)
    result.add s[frm ..< to]
    if i < lines-1:
      result.add "\n"

proc toPemFile*(publicKey: EC_ShortW_Aff[Fp[C], G1]): string =
  ## Convert a given private key to data in PEM format following SEC1
  # 1. Convert public key to ASN.1 DER
  let derB = publicKey.toPemPublicKey()
  # 2. Encode bytes in base64
  let der64 = derB.encode().wrap()
  # 3. Wrap in begin/end public key template
  result = PublicKeyTmpl % [der64]

proc toPemFile*(privateKey: Fr[C]): string =
  ## XXX: For now using `std/base64` but will need to write base64 encoder
  ## & add tests for CTT base64 decoder!
  ## Convert a given private key to data in PEM format following SEC1
  # 1. Convert private key to ASN.1 DER encoding
  let derB = toPemPrivateKey(privateKey)
  # 2. Encode bytes in base64
  let der64 = derB.encode().wrap()
  # 3. Wrap in begin/end private key template
  result = PrivateKeyTmpl % [der64]
