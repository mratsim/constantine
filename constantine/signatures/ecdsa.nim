# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/hashes,
  constantine/named/algebras,
  constantine/math/io/[io_bigints, io_fields, io_ec],
  constantine/math/elliptic/[ec_shortweierstrass_affine, ec_shortweierstrass_jacobian, ec_scalar_mul, ec_multi_scalar_mul],
  constantine/math/[arithmetic, ec_shortweierstrass],
  constantine/platforms/[abstractions, views],
  constantine/serialization/codecs, # for fromHex and (in the future) base64 encoding
  constantine/mac/mac_hmac, # for deterministic nonce generation via RFC 6979
  constantine/named/zoo_generators, # for generator
  constantine/csprngs/sysrand,
  constantine/signatures/common_signature_ops # for `derivePubkey`

import std / macros # for `update` convenience helper

export common_signature_ops

type
  ## Decides the type of sampler we use for the nonce. By default
  ## a simple uniform random sampler. Alternatively a deterministic
  ## sampler based on message hash and private key.
  NonceSampler* = enum
    nsRandom, ## pure uniform random sampling
    nsRfc6979 ## deterministic according to RFC 6979

  ## Helper type for ASN.1 DER signatures to avoid allocation.
  ## Has a `data` buffer of 72 bytes (maximum possible size for
  ## a signature for `secp256k1`) and `len` of actually used data.
  ## `data[0 ..< len]` is the actual signature.
  DERSignature*[N: static int] = object
    data*: array[N, byte] # Max size: 6 bytes overhead + 33 bytes each for r,s
    len*: int # Actual length used

template DERSigSize*(Name: static Algebra): int =
  6 + 2 * (Fr[Name].bits.ceilDiv_vartime(sizeof(pointer)) + 1)

proc toBytes[Name: static Algebra; N: static int](res: var array[N, byte], x: FF[Name]) =
  discard res.marshal(x.toBig(), bigEndian)

proc toDER*[Name: static Algebra; N: static int](derSig: var DERSignature[N], r, s: Fr[Name]) =
  ## Converts signature (r,s) to DER format without allocation.
  ## Max size is 72 bytes (for Secp256k1 or any curve with 32 byte scalars in `Fr`):
  ## 6 bytes overhead + up to 32+1 bytes each for r,s.
  ## 6 byte 'overhead' for:
  ## - `0x30` byte SEQUENCE designator
  ## - total length of the array
  ## - integer type designator `0x02` (before `r` and `s`)
  ## - length of `r` and `s`
  ##
  ## Implementation follows ideas of Bitcoin's secp256k1 implementation:
  ## https://github.com/bitcoin-core/secp256k1/blob/f79f46c70386c693ff4e7aef0b9e7923ba284e56/src/ecdsa_impl.h#L171-L193

  const WordSize = sizeof(BaseType)
  const N = Fr[Name].bits.ceilDiv_vartime(WordSize) # 32 for `secp256k1`

  template toByteArray(x: Fr[Name]): untyped =
    ## Convert to a 33 byte array. Leading zero byte required if
    ## first real byte (idx 1) highest bit set (> 0x80).
    var a: array[N+1, byte]
    discard toOpenArray[byte](a, 1, N).marshal(x.toBig(), bigEndian)
    a

  # 1. Prepare the data & determine required sizes

  # Convert r,s to big-endian bytes
  var rBytes = r.toByteArray()
  var sBytes = s.toByteArray()
  var rLen = N + 1
  var sLen = N + 1

  # Skip leading zeros but ensure high bit constraint
  var rPos = 0
  while rLen > 1 and rBytes[rPos] == 0 and (rBytes[rPos+1] < 0x80.byte):
    dec rLen
    inc rPos
  var sPos = 0
  while sLen > 1 and sBytes[sPos] == 0 and (sBytes[sPos+1] < 0x80.byte):
    dec sLen
    inc sPos

  # Set total length
  derSig.len = 6 + rLen + sLen


  # 2. Write the actual data
  var pos = 0
  template setInc(val: byte): untyped =
    # Set `val` at `pos` and increase `pos`
    derSig.data[pos] = val
    inc pos

  # Write DER structure, global
  setInc 0x30                   # sequence
  setInc (4 + rLen + sLen).byte # total length

  # `r` prefix
  setInc 0x02                   # integer
  setInc rLen.byte              # length of `r`
  # Write `r` bytes in valid region
  derSig.data.rawCopy(pos, rBytes, rPos, rLen)
  inc pos, rLen

  # `s` prefix
  setInc 0x02                   # integer
  setInc sLen.byte              # length of `s`
  # Write `s` bytes in valid region
  derSig.data.rawCopy(pos, sBytes, sPos, sLen)
  inc pos, sLen

  assert derSig.len == pos

func fromDigest[Name: static Algebra; N: static int](
    dst: var Fr[Name], src: array[N, byte],
    truncateInput: static bool): bool {.discardable.} =
  ## Convert a hash function digest to an element in the scalar field `Fr[Name]`.
  ## The proc returns a boolean indicating whether the data in `src` is
  ## smaller than the field modulus. It is discardable, because in some
  ## use cases this is fine (e.g. constructing a field element from a hash),
  ## but invalid in the nonce generation following RFC6979.
  ##
  ## The `truncateInput` argument handles how `src` arrays larger than the BigInt
  ## underlying `Fr[Name]` are handled. If it is `false` we will simply throw
  ## an assertion error on `unmarshal` (used in RFC6979 nonce generation where
  ## the array size cannot be larger than `Fr[Name]`). If it is `true`, we truncate
  ## the digest array to the left most bits of up to the number of bits underlying
  ## the BigInt of `Fr[Name]` following SEC1v2 [0] (page 45, 5.1-5.4).
  ##
  ## [0]: https://www.secg.org/sec1-v2.pdf
  var scalar {.noInit.}: matchingOrderBigInt(Name)
  when truncateInput: # for signature & verification
    # If the `src` array is larger than the BigInt underlying `Fr[Name]`, need
    # to truncate the `src`.
    const WordSize = sizeof(BaseType)
    const FrBytes = Fr[Name].bits.ceildiv_vartime(WordSize)
    # effectively: `scalar ~ array[0 ..< scalar.len]`
    scalar.unmarshal(toOpenArray[byte](src, 0, FrBytes-1), bigEndian)
    # Now still need to right shift potential individual bits.
    # e.g. 381 bit BigInt fits into 384 bit (48 bytes), so need to
    # right shift 3 bits to truncate correctly.
    const toShift = FrBytes * WordSize - Fr[Name].bits
    when toShift > 0:
      scalar.shiftRight(toShift)
  else: # for RFC 6979 nonce sampling. If larger than modulus, sample again
    scalar.unmarshal(src, bigEndian)
  scalar.unmarshal(src, bigEndian)
  # `true` if smaller than modulus
  result = bool(scalar < Fr[Name].getModulus())
  dst.fromBig(scalar)

proc randomFieldElement[FF](): FF =
  ## random element in ~Fp[T]/Fr[T]~
  let m = FF.getModulus()
  var b: matchingBigInt(FF.Name)

  while b.isZero().bool or (b > m).bool:
    ## XXX: raise / what else to do if `sysrand` call fails?
    doAssert b.limbs.sysrand()

  result.fromBig(b)

proc arrayWith[N: static int](res: var array[N, byte], val: byte) =
  for i in 0 ..< N:
    res[i] = val

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

proc nonceRfc6979[Name: static Algebra](
    msgHash, privateKey: Fr[Name],
    H: type CryptoHash): Fr[Name] {.noinit.} =
  ## Generate deterministic nonce according to RFC 6979.
  ##
  ## Spec:
  ## https://datatracker.ietf.org/doc/html/rfc6979#section-3.2

  const WordSize = sizeof(BaseType)
  const N = Fr[Name].bits.ceilDiv_vartime(WordSize)

  # Step a: `h1 = H(m)` hash message (already done, input is hash), convert to array of bytes
  var msgHashBytes {.noinit.}: array[N, byte]
  msgHashBytes.toBytes(msgHash)
  # Piece of step d: Conversion of the private key to a byte array.
  # No need for `bits2octets`, because the private key is already a valid
  # scalar in the field `Fr[C]` and thus < p-1 (`bits2octets` converts
  # `r` bytes to a BigInt, reduces modulo prime order `p` and converts to
  # a byte array).
  var privKeyBytes {.noinit.}: array[N, byte]
  privKeyBytes.toBytes(privateKey)

  # Initial values
  # Step b: `V = 0x01 0x01 0x01 ... 0x01`
  var v: array[N, byte]; v.arrayWith(byte 0x01)
  # Step c: `K = 0x00 0x00 0x00 ... 0x00`
  var k: array[N, byte]; k.arrayWith(byte 0x00)

  # Create HMAC contexts
  var hmac {.noinit.}: HMAC[H]

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
    var candidate {.noinit.}: Fr[Name]
    # `fromDigest` returns `false` if the array is larger than the field modulus,
    # important for uniform sampling in valid range `[1, q-1]`!
    let smaller = candidate.fromDigest(v, truncateInput = false) # do not truncate!

    if not bool(candidate.isZero()) and smaller:
      return candidate

    # Step h.3 failure state:
    # `K = HMAC_K(V || 0x00)`
    # `V = HMAC_K(V)`
    # Try again if invalid
    hmac.round(k, k, v, [byte 0x00])
    hmac.round(k, v, v)

proc generateNonce[Name: static Algebra](
    kind: NonceSampler, msgHash, privateKey: Fr[Name],
    H: type CryptoHash): Fr[Name] {.noinit.} =
  case kind
  of nsRandom: randomFieldElement[Fr[Name]]()
  of nsRfc6979: nonceRfc6979(msgHash, privateKey, H)

proc signImpl[Name: static Algebra; Sig](
  sig: var Sig,
  secretKey: Fr[Name],
  message: openArray[byte],
  H: type CryptoHash,
  nonceSampler: NonceSampler = nsRandom) =
  ## Sign a given `message` using the `secretKey`.
  ##
  ## By default we use a purely random nonce (uniform random number),
  ## but passing `nonceSampler = nsRfc6979` uses RFC 6979 to compute
  ## a deterministic nonce (and thus deterministic signature) given
  ## the message and private key as base.
  # 1. hash the message in big endian order
  var dgst {.noinit.}: array[H.digestSize, byte]
  H.hash(dgst, message)
  var message_hash: Fr[Name]
  # if `dgst` uses more bytes than
  message_hash.fromDigest(dgst, truncateInput = true)

  # Generator of the curve
  const G = Name.getGenerator($G1)

  # loop until we found a valid (non zero) signature
  while true:
    # Generate random nonce
    var k = generateNonce(nonceSampler, message_hash, secretKey, H)

    var R {.noinit.}: EC_ShortW_Jac[Fp[Name], G1]
    # Calculate r (x-coordinate of kG)
    # `r = k·G (mod n)`
    R.scalarMul(k, G)
    # get x coordinate of the point `r` *in affine coordinates*
    let rx = R.getAffine().x
    let r = Fr[Name].fromBig(rx.toBig()) # convert to `Fr`

    if bool(r.isZero()):
      continue # try again

    # Calculate s
    # `s = (k⁻¹ · (h + r · p)) (mod n)`
    # with `h`: message hash as `Fr[C]` (if we didn't use SHA256 w/ 32 byte output
    # we'd need to truncate to N bits for N being bits in modulo `n`)
    var s {.noinit.}: Fr[Name]
    s.prod(r, secretKey) # `r * secretKey`
    s += message_hash     # `message_hash + r * secretKey`
    k.inv()               # `k := k⁻¹`
    s *= k                # `k⁻¹ * (message_hash + r * secretKey)`
    # get inversion of `s` for 'lower-s normalization'
    var sneg = s # inversion of `s`
    sneg.neg()   # q - s
    # conditionally assign result based on BigInt comparison
    let mask = s.toBig() > sneg.toBig() # if true, `s` is in upper half, need `sneg`
    ccopy(s, sneg, mask)

    if bool(s.isZero()):
      continue # try again

    # Set output and return
    sig.r = r
    sig.s = s
    return

proc coreSign*[Sig, SecKey](
    signature: var Sig,
    secretKey: SecKey,
    message: openArray[byte],
    H: type CryptoHash,
    nonceSampler: NonceSampler = nsRandom) {.genCharAPI.} =
  ## Computes a signature for the message from the specified secret key.
  ##
  ## Output:
  ## - `signature` is overwritten with `message` signed with `secretKey`
  ##
  ## Inputs:
  ## - `Hash` a cryptographic hash function.
  ##   - `Hash` MAY be `sha256`
  ##   - `Hash` MAY be `keccak`
  ##   - Otherwise, H MUST be a hash function that has been proved
  ##    indifferentiable from a random oracle [MRH04] under a reasonable
  ##    cryptographic assumption.
  ## - `message` is the message to hash
  signature.signImpl(secretKey, message, H, nonceSampler)

proc verifyImpl[Name: static Algebra; Sig](
    publicKey: EC_ShortW_Aff[Fp[Name], G1],
    signature: Sig, # tuple[r, s: Fr[Name]],
    message: openArray[byte],
    H: type CryptoHash,
): bool =
  ## Verify a given `signature` for a `message` using the given `publicKey`.
  # 1. Hash the message (same as in signing)
  var dgst {.noinit.}: array[H.digestSize, byte]
  H.hash(dgst, message)
  var e {.noinit.}: Fr[Name]
  e.fromDigest(dgst, truncateInput = true)

  # 2. Compute w = s⁻¹
  var w = signature.s
  w.inv() # w = s⁻¹

  # 3. Compute u₁ = ew and u₂ = rw
  var
    u1 {.noinit.}: Fr[Name]
    u2 {.noinit.}: Fr[Name]
  u1.prod(e, w)
  u2.prod(signature.r, w)

  # 4. Compute u₁G + u₂Q
  var
    point1 {.noinit.}: EC_ShortW_Jac[Fp[Name], G1]
    point2 {.noinit.}: EC_ShortW_Jac[Fp[Name], G1]
  # Generator of the curve
  const G = publicKey.F.Name.getGenerator($publicKey.G)
  point1.scalarMul(u1, G)
  point2.scalarMul(u2, publicKey)
  var R {.noinit.}: EC_ShortW_Jac[Fp[Name], G1]
  R.sum(point1, point2)

  # 5. Get x coordinate (in `Fp`) and convert to `Fr` (like in signing)
  let x = R.getAffine().x
  let r_computed = Fr[Name].fromBig(x.toBig())

  # 6. Verify r_computed equals provided r
  result = bool(r_computed == signature.r)

func coreVerify*[Pubkey, Sig](
    pubkey: Pubkey,
    message: openarray[byte],
    signature: Sig,
    H: type CryptoHash): bool {.genCharAPI.} =
  ## Check that a signature is valid
  ## for a message under the provided public key
  ## This assumes that the PublicKey and Signatures
  ## have been pre-checked for non-infinity and being in the correct subgroup
  ## (likely on deserialization)
  result = pubKey.verifyImpl(signature, message, H)
