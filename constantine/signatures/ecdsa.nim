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
  constantine/signatures/ecc_sig_ops # for `derivePubkey`

import std / macros # for `update` convenience helper

export ecc_sig_ops

type
  ## Decides the type of sampler we use for the nonce. By default
  ## a simple uniform random sampler. Alternatively a deterministic
  ## sampler based on message hash and private key.
  NonceSampler* = enum
    nsRandom, ## pure uniform random sampling
    nsRfc6979 ## deterministic according to RFC 6979

proc toBytes[Name: static Algebra; N: static int](res: var array[N, byte], x: FF[Name]) =
  discard res.marshal(x.toBig(), bigEndian)

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
    const OctetWidth = 8
    const FrBytes = Fr[Name].bits.ceildiv_vartime(OctetWidth)
    # effectively: `scalar ~ array[0 ..< scalar.len]`
    scalar.unmarshal(toOpenArray[byte](src, 0, FrBytes-1), bigEndian)
    # Now still need to right shift potential individual bits.
    # e.g. 381 bit BigInt fits into 384 bit (48 bytes), so need to
    # right shift 3 bits to truncate correctly.
    const toShift = FrBytes * OctetWidth - Fr[Name].bits
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

proc byteArrayWith(N: static int, val: byte): array[N, byte] {.noinit, inline.} =
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

proc nonceRfc6979[Name: static Algebra](
    msgHash, privateKey: Fr[Name],
    H: type CryptoHash): Fr[Name] {.noinit.} =
  ## Generate deterministic nonce according to RFC 6979.
  ##
  ## Spec:
  ## https://datatracker.ietf.org/doc/html/rfc6979#section-3.2

  const OctetWidth = 8
  const N = Fr[Name].bits.ceilDiv_vartime(OctetWidth)

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
  var v = byteArrayWith(N, byte 0x01)
  # Step c: `K = 0x00 0x00 0x00 ... 0x00`
  var k = byteArrayWith(N, byte 0x00)

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
  msgHash: Fr[Name],
  H: type CryptoHash,
  nonceSampler: NonceSampler = nsRandom) =
  ## Sign a given `message` using the `secretKey`.
  ##
  ## By default we use a purely random nonce (uniform random number),
  ## but passing `nonceSampler = nsRfc6979` uses RFC 6979 to compute
  ## a deterministic nonce (and thus deterministic signature) given
  ## the message and private key as base.
  # Generator of the curve
  const G = Name.getGenerator($G1)

  # loop until we found a valid (non zero) signature
  while true:
    # Generate random nonce
    var k = generateNonce(nonceSampler, msgHash, secretKey, H)

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
    s += msgHash         # `msgHash + r * secretKey`
    k.inv()              # `k := k⁻¹`
    s *= k               # `k⁻¹ * (msgHash + r * secretKey)`
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
  # 1. hash the message in big endian order
  var dgst {.noinit.}: array[H.digestSize, byte]
  H.hash(dgst, message)
  var msgHash: Fr[SecKey.Name]
  # if `dgst` uses more bits than scalar in `Fr`, truncate
  msgHash.fromDigest(dgst, truncateInput = true)
  # 2. sign
  signature.signImpl(secretKey, msgHash, H, nonceSampler)

proc verifyImpl[Name: static Algebra; Sig](
    publicKey: EC_ShortW_Aff[Fp[Name], G1],
    signature: Sig,
    msgHash: Fr[Name]
): bool =
  ## Verify a given `signature` for a `message` using the given `publicKey`.
  # 1. Compute w = s⁻¹
  var w = signature.s
  w.inv() # w = s⁻¹

  # 2. Compute u₁ = ew and u₂ = rw
  var
    u1 {.noinit.}: Fr[Name]
    u2 {.noinit.}: Fr[Name]
  u1.prod(msgHash, w)
  u2.prod(signature.r, w)

  # 3. Compute u₁G + u₂Q
  var
    point1 {.noinit.}: EC_ShortW_Jac[Fp[Name], G1]
    point2 {.noinit.}: EC_ShortW_Jac[Fp[Name], G1]
  # Generator of the curve
  const G = publicKey.F.Name.getGenerator($publicKey.G)
  point1.scalarMul(u1, G)
  point2.scalarMul(u2, publicKey)
  var R {.noinit.}: EC_ShortW_Jac[Fp[Name], G1]
  R.sum(point1, point2)

  # 4. Get x coordinate (in `Fp`) and convert to `Fr` (like in signing)
  let x = R.getAffine().x
  let r_computed = Fr[Name].fromBig(x.toBig())

  # 5. Verify r_computed equals provided r
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
  # 1. Hash the message (same as in signing)
  var dgst {.noinit.}: array[H.digestSize, byte]
  H.hash(dgst, message)
  var msgHash {.noinit.}: Fr[pubkey.F.Name]
  msgHash.fromDigest(dgst, truncateInput = true)
  # 2. verify
  result = pubKey.verifyImpl(signature, msgHash)

proc recoverPubkeyImpl_vartime*[Name: static Algebra; Sig](
    recovered: var EC_ShortW_Aff[Fp[Name], G1],
    signature: Sig,
    msgHash: Fr[Name],
    evenY: bool) =
  ## Attempts to recover an associated public key to the given `signature` and
  ## hash of a message `msgHash`.
  ##
  ## Note that as the signature is only dependent on the `x` coordinate of the
  ## curve point `R`, two public keys verify the signature. The one with even
  ## and the one with odd `y` coordinate (one even & one odd due to curve prime
  ## order).
  ##
  ## `evenY` decides whether we recover the public key associated with the even
  ## `y` coordinate of `R` or the odd one. Both verify the (message, signature)
  ## pair.
  ##
  ## If the signature is invalid, `recovered` will be set to the neutral element.
  type
    ECAff = EC_ShortW_Aff[Fp[Name], G1]
    ECJac = EC_ShortW_Jac[Fp[Name], G1]
  # 1. Set to neutral so if we don't find a valid signature, return neutral
  recovered.setNeutral()
  const G = Name.getGenerator($G1)

  let rInit = signature.r.toBig() # initial `r`
  var x1 = Fp[Name].fromBig(signature.r.toBig()) # as coordinate in Fp
  let M = Fp[Name].fromBig(Fr[Name].getModulus())

  # Due to the conversion of the `x` coordinate in `Fp` of the point `R` in the signing process
  # to a scalar in `Fr`, we potentially reduce it modulo the subgroup order (if `x > M` with
  # `M` the subgroup order).
  # As we don't know if this is the case, we need to loop until we either find a valid signature,
  # adding `M` each iteration or until we roll over again, in which case the signature is invalid.
  # NOTE: For secp256k1 this is _extremely_ unlikely, because prime of the curve `p` and subgroup
  # order `M` are so close!
  var validSig = false
  while (not validSig) and bool(x1.toBig() <= rInit):
    # 1. Get base `R` point
    var R {.noinit.}: EC_ShortW_Aff[Fp[Name], G1]
    let valid = R.trySetFromCoordX(x1) # from `r = x1`
    if not bool(valid):
      x1 += M # add modulus of `Fr`. As long as we don't overflow in `Fp` we try again
      continue # try next `i` in `x1 = r + i·M`

    let isEven = R.y.toBig().isEven()
    # 2. only negate `y ↦ -y` if current and target even-ness disagree
    R.y.cneg(isEven xor SecretBool evenY)

    # 3. perform recovery calculation, `Q = -m·r⁻¹ * G + s·r⁻¹ * R`
    # Note: Calculate with `r⁻¹` included in each coefficient to avoid 3rd `scalarMul`.
    var rInv = signature.r
    rInv.inv() # `r⁻¹`

    var u1 {.noinit.}, u2 {.noinit.}: Fr[Name]
    u1.prod(msgHash, rInv)     # `u₁ = m·r⁻¹`
    u1.neg()                   # `u₁ = -m·r⁻¹`
    u2.prod(signature.s, rInv) # `u₂ = s·r⁻¹`

    var Q {.noinit.}: ECJac # the potential public key
    var point1 {.noinit.}, point2 {.noinit.}: ECJac
    point1.scalarMul(u1, G)    # `p₁ = u₁ * G`
    point2.scalarMul(u2, R)    # `p₂ = u₂ * R`
    Q.sum(point1, point2)      # `Q = p₁ + p₂`

    # 4. Verify signature with this point
    validSig = Q.getAffine().verifyImpl(signature, msgHash)

    # 5. If valid copy to `recovered`, else keep neutral point
    recovered.ccopy(Q.getAffine(), SecretBool validSig) # Copy `Q` if valid
    # 6. try next `i` in `x1 = r + i·M`
    x1 += M

proc recoverPubkey*[Pubkey; Sig](
    recovered: var Pubkey,
    signature: Sig,
    message: openArray[byte],
    evenY: bool,
    H: type CryptoHash) =
  ## Attempts to recover an associated public key to the given `signature` and
  ## hash of a message `msgHash`.
  ##
  ## Note that as the signature is only dependent on the `x` coordinate of the
  ## curve point `R`, two public keys verify the signature. The one with even
  ## and the one with odd `y` coordinate (one even & one odd due to curve prime
  ## order).
  ##
  ## `evenY` decides whether we recover the public key associated with the even
  ## `y` coordinate of `R` or the odd one. Both verify the (message, signature)
  ## pair.
  ##
  ## If the signature is invalid, `recovered` will be set to the neutral element.
  # 1. Hash the message (same as in signing)
  var dgst {.noinit.}: array[H.digestSize, byte]
  H.hash(dgst, message)
  var msgHash {.noinit.}: Fr[recovered.F.Name]
  msgHash.fromDigest(dgst, truncateInput = true)
  # 2. recover
  recovered.recoverPubkeyImpl_vartime(signature, msgHash, evenY)
