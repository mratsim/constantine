# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
    ../math/[ec_shortweierstrass, extension_fields],
    ../math/io/io_bigints,
    ../math/elliptic/ec_scalar_mul_vartime,
    ../math/pairings/[pairings_generic, miller_accumulators],
    ../math/constants/zoo_generators,
    ../math/config/curves,
    ../hash_to_curve/[hash_to_curve, h2c_hash_to_field],
    ../hashes,
    ../platforms/views

# ############################################################
#
#                   BLS Signatures
#
# ############################################################

# This module implements generic BLS signatures
# https://www.ietf.org/archive/id/draft-irtf-cfrg-bls-signature-05.html
# https://github.com/cfrg/draft-irtf-cfrg-bls-signature
#
# We use generic shortnames SecKey, PubKey, Sig
# so tat the algorithms fit whether Pubkey and Sig are on G1 or G2
# Actual protocols should expose publicly the full names SecretKey, PublicKey and Signature

{.push raises: [].} # No exceptions allowed in core cryptographic operations
{.push checks: off.} # No defects due to array bound checking or signed integer overflow allowed

func derivePubkey*[Pubkey, SecKey](pubkey: var Pubkey, seckey: SecKey) =
  ## Generates the public key associated with the input secret key.
  ##
  ## The secret key MUST be in range (0, curve order)
  ## 0 is INVALID
  const Group = Pubkey.G
  type Field = Pubkey.F
  const EC = Field.C

  var pk {.noInit.}: ECP_ShortW_Jac[Field, Group]
  pk.fromAffine(EC.getGenerator($Group))
  pk.scalarMul(seckey)
  pubkey.affine(pk)

func coreSign*[Sig, SecKey](
    signature: var Sig,
    secretKey: SecKey,
    message: openArray[byte],
    H: type CryptoHash,
    k: static int,
    augmentation: openArray[byte],
    domainSepTag: openArray[byte]) {.genCharAPI.} =
  ## Computes a signature for the message from the specified secret key.
  ##
  ## Output:
  ## - `signature` is overwritten with `message` signed with `secretKey`
  ##
  ## Inputs:
  ## - `Hash` a cryptographic hash function.
  ##   - `Hash` MAY be a Merkle-Damgaard hash function like SHA-2
  ##   - `Hash` MAY be a sponge-based hash function like SHA-3 or BLAKE2
  ##   - Otherwise, H MUST be a hash function that has been proved
  ##    indifferentiable from a random oracle [MRH04] under a reasonable
  ##    cryptographic assumption.
  ## - k the security parameter of the suite in bits (for example 128)
  ## - `output`, an elliptic curve point that will be overwritten.
  ## - `augmentation`, an optional augmentation to the message. This will be prepended,
  ##   prior to hashing.
  ##   This is used for building the "message augmentation" variant of BLS signatures
  ##   https://www.ietf.org/archive/id/draft-irtf-cfrg-bls-signature-05.html#section-3.2
  ##   which requires `CoreSign(SK, PK || message)`
  ##   and `CoreVerify(PK, PK || message, signature)`
  ## - `message` is the message to hash
  ## - `domainSepTag` is the protocol domain separation tag (DST).

  type ECP_Jac = ECP_ShortW_Jac[Sig.F, Sig.G]

  var sig {.noInit.}: ECP_Jac
  H.hashToCurve(k, sig, augmentation, message, domainSepTag)
  sig.scalarMul(secretKey)

  signature.affine(sig)

func coreVerify*[Pubkey, Sig](
    pubkey: Pubkey,
    message: openarray[byte],
    signature: Sig,
    H: type CryptoHash,
    k: static int,
    augmentation: openarray[byte],
    domainSepTag: openarray[byte]): bool {.genCharAPI.} =
  ## Check that a signature is valid
  ## for a message under the provided public key
  ## This assumes that the PublicKey and Signatures
  ## have been pre-checked for non-infinity and being in the correct subgroup
  ## (likely on deserialization)
  var Q {.noInit.}: ECP_ShortW_Aff[Sig.F, Sig.G]
  var negG {.noInit.}: ECP_ShortW_Aff[Pubkey.F, Pubkey.G]

  negG.neg(Pubkey.F.C.getGenerator($Pubkey.G))
  H.hashToCurve(k, Q, augmentation, message, domainSepTag)

  when Sig.F.C.getEmbeddingDegree() == 12:
    var gt {.noInit.}: Fp12[Sig.F.C]
  else:
    {.error: "Not implemented: signature on k=" & $Sig.F.C.getEmbeddingDegree() & " for curve " & $$Sig.F.C.}

  # e(PK, H(msg))*e(sig, -G) == 1
  when Sig.G == G2:
    pairing(gt, [pubkey, negG], [Q, signature])
  else:
    pairing(gt, [Q, signature], [pubkey, negG])

  return gt.isOne().bool()

# ############################################################
#
#          Aggregate and Batched Signature Verification
#                        Accumulators
#
# ############################################################
#
# Terminology:
#
# - fastAggregateVerify:
#   Verify the aggregate of multiple signatures on the same message by multiple pubkeys
#
# - aggregateVerify:
#   Verify the aggregated signature of multiple (pubkey, message) pairs
#
# - batchVerify:
#   Verify that all (pubkey, message, signature) triplets are valid

# Aggregate Signatures
# ------------------------------------------------------------

type
  BLSAggregateSigAccumulator*[H: CryptoHash, FF1, FF2; Fpk: ExtensionField; k: static int] = object
    ## An accumulator for Aggregate BLS signature verification.
    ## Note:
    ##   This is susceptible to "splitting-zero" attacks
    ##   - https://eprint.iacr.org/2021/323.pdf
    ##   - https://eprint.iacr.org/2021/377.pdf
    ## To avoid splitting zeros and rogue keys attack:
    ## 1. Public keys signing the same message MUST be aggregated and checked for 0 before calling BLSAggregateSigAccumulator.update()
    ## 2. Augmentation or Proof of possessions must used for each public keys.

    # An accumulator for the Miller loops
    millerAccum: MillerAccumulator[FF1, FF2, Fpk]

    domainSepTag{.align: 64.}: array[255, byte] # Alignment to enable SIMD
    dst_len: uint8

func init*(ctx: var BLSAggregateSigAccumulator, domainSepTag: openArray[byte]) {.genCharAPI.} =
  ## Initializes a BLS Aggregate Signature accumulator context.

  type H = BLSAggregateSigAccumulator.H

  ctx.millerAccum.init()

  if domainSepTag.len > 255:
    var t {.noInit.}: array[H.digestSize(), byte]
    H.shortDomainSepTag(output = t, domainSepTag)
    rawCopy(ctx.domainSepTag, dStart = 0, t, sStart = 0, H.digestSize())
    ctx.dst_len = uint8 H.digestSize()
  else:
    rawCopy(ctx.domainSepTag, dStart = 0, domainSepTag, sStart = 0, domainSepTag.len)
    ctx.dst_len = uint8 domainSepTag.len
  for i in ctx.dst_len ..< ctx.domainSepTag.len:
    ctx.domainSepTag[i] = byte 0

func update*[Pubkey: ECP_ShortW_Aff](
       ctx: var BLSAggregateSigAccumulator,
       pubkey: Pubkey,
       message: openArray[byte]): bool {.genCharAPI.} =
  ## Add a (public key, message) pair
  ## to a BLS aggregate signature accumulator
  ##
  ## Assumes that the public key has been group checked
  ##
  ## Returns false if pubkey is the infinity point

  const k = BLSAggregateSigAccumulator.k
  type H = BLSAggregateSigAccumulator.H

  when Pubkey.G == G1:
    # Pubkey on G1, H(message) and Signature on G2
    type FF2 = BLSAggregateSigAccumulator.FF2
    var hmsgG2_aff {.noInit.}: ECP_ShortW_Aff[FF2, G2]
    H.hashToCurve(
      k, output = hmsgG2_aff,
      augmentation = "", message,
      ctx.domainSepTag.toOpenArray(0, ctx.dst_len.int - 1))

    return ctx.millerAccum.update(pubkey, hmsgG2_aff)

  else:
    # Pubkey on G2, H(message) and Signature on G1
    type FF1 = BLSAggregateSigAccumulator.FF1
    var hmsgG1_aff {.noInit.}: ECP_ShortW_Aff[FF1, G1]
    H.hashToCurve(
      k, output = hmsgG1_aff,
      augmentation = "", message,
      ctx.domainSepTag.toOpenArray(0, ctx.dst_len.int - 1))

    return ctx.millerAccum.update(hmsgG1_aff, pubkey)

func update*[Pubkey: ECP_ShortW_Aff](
       ctx: var BLSAggregateSigAccumulator,
       pubkey: Pubkey,
       message: View[byte]): bool {.inline.} =
  ctx.update(pubkey, message.toOpenArray())

func merge*(ctxDst: var BLSAggregateSigAccumulator, ctxSrc: BLSAggregateSigAccumulator): bool =
  ## Merge 2 BLS signature accumulators: ctxDst <- ctxDst + ctxSrc
  ##
  ## Returns false if they have inconsistent DomainSeparationTag and true otherwise.
  if ctxDst.dst_len != ctxSrc.dst_len:
    return false
  if not equalMem(ctxDst.domainSepTag.addr, ctxSrc.domainSepTag.addr, ctxDst.domainSepTag.len):
    return false

  ctxDst.millerAccum.merge(ctxSrc.millerAccum)
  return true

func finalVerify*[F, G](ctx: var BLSAggregateSigAccumulator, aggregateSignature: ECP_ShortW_Aff[F, G]): bool =
  ## Finish batch and/or aggregate signature verification and returns the final result.
  ##
  ## Returns false if nothing was accumulated
  ## Rteturns false on verification failure

  type FF1 = BLSAggregateSigAccumulator.FF1
  type FF2 = BLSAggregateSigAccumulator.FF2
  type Fpk = BLSAggregateSigAccumulator.Fpk

  when G == G2:
    type PubKey = ECP_ShortW_Aff[FF1, G1]
  else:
    type PubKey = ECP_ShortW_Aff[FF2, G2]

  var negG {.noInit.}: Pubkey
  negG.neg(Pubkey.F.C.getGenerator($Pubkey.G))

  when G == G2:
    if not ctx.millerAccum.update(negG, aggregateSignature):
      return false
  else:
    if not ctx.millerAccum.update(aggregateSignature, negG):
      return false

  var gt {.noinit.}: Fpk
  ctx.millerAccum.finish(gt)
  gt.finalExp()
  return gt.isOne().bool

# Batch Signatures
# ------------------------------------------------------------

type
  BLSBatchSigAccumulator*[H: CryptoHash, FF1, FF2; Fpk: ExtensionField; SigAccum: ECP_ShortW_Jac, k: static int] = object
    ## An accumulator for Batched BLS signature verification

    # An accumulator for the Miller loops
    millerAccum: MillerAccumulator[FF1, FF2, Fpk]

    # An accumulator for signatures:
    # signature verification is in the form
    # with PK a public key, H(𝔪) the hash of a message to sign, sig the signature
    #
    # e(PK, H(𝔪)).e(generator, sig) == 1
    #
    # For aggregate or batch verification
    # e(PK₀, H(𝔪₀)).e(-generator, sig₀).e(PK, H(𝔪₁)).e(-generator, sig₁) == 1
    #
    # Due to bilinearity of pairings:
    # e(PK₀, H(𝔪₀)).e(PK₁, H(𝔪₁)).e(-generator, sig₀+sig₁) == 1
    #
    # Hence we can divide cost of aggregate and batch verification by 2 if we aggregate signatures
    aggSig: SigAccum
    aggSigOnce: bool

    domainSepTag{.align: 64.}: array[255, byte] # Alignment to enable SIMD
    dst_len: uint8

    # This field holds a secure blinding scalar,
    # it does not use secret data but it is necessary
    # to have data not in the control of an attacker
    # to prevent forging valid aggregated signatures
    # from 2 invalid individual signatures using
    # the bilinearity property of pairings.
    # https://ethresear.ch/t/fast-verification-of-multiple-bls-signatures/5407/14
    #
    # Assuming blinding muls cost 60% of a pairing (worst case with 255-bit blinding)
    # verifying 3 signatures would have a base cost of 300
    # Batched single threaded the cost would be
    # 60*3 (blinding 255-bit) + 50 (Miller) + 50 (final exp) = 280
    #
    # With 64-bit blinding and ~20% overhead
    # (not 15% because no endomorphism acceleration with 64-bit)
    # 20*3 (blinding 64-bit) + 50 (Miller) + 50 (final exp) = 160
    #
    # If split on 2 cores, the critical path is
    # 20*2 (blinding 64-bit) + 50 (Miller) + 50 (final exp) = 140
    #
    # If split on 3 cores, the critical path is
    # 20*1 (blinding 64-bit) + 50 (Miller) + 50 (final exp) = 120
    secureBlinding{.align: 32.}: array[32, byte]

func hash[DigestSize: static int](
      H: type CryptoHash, digest: var array[DigestSize, byte], input0: openArray[byte], input1: openArray[byte]) =

  static: doAssert DigestSize == H.digestSize()

  var h{.noInit.}: H
  h.init()
  h.update(input0)
  h.update(input1)
  h.finish(digest)

func init*(
       ctx: var BLSBatchSigAccumulator, domainSepTag: openArray[byte],
       secureRandomBytes: array[32, byte], accumSepTag: openArray[byte]) {.genCharAPI.} =
  ## Initializes a Batch BLS Signature accumulator context.
  ##
  ## This requires cryptographically secure random bytes
  ## to defend against forged signatures that would not
  ## verify individually but would verify while aggregated
  ## https://ethresear.ch/t/fast-verification-of-multiple-bls-signatures/5407/14
  ##
  ## An optional accumulator separation tag can be added
  ## so that from a single source of randomness
  ## each accumulatpr is seeded with a different state.
  ## This is useful in multithreaded context.

  type H = BLSBatchSigAccumulator.H

  ctx.millerAccum.init()
  ctx.aggSigOnce = false

  if domainSepTag.len > 255:
    var t {.noInit.}: array[H.digestSize(), byte]
    H.shortDomainSepTag(output = t, domainSepTag)
    rawCopy(ctx.domainSepTag, dStart = 0, t, sStart = 0, H.digestSize())
    ctx.dst_len = uint8 H.digestSize()
  else:
    rawCopy(ctx.domainSepTag, dStart = 0, domainSepTag, sStart = 0, domainSepTag.len)
    ctx.dst_len = uint8 domainSepTag.len
  for i in ctx.dst_len ..< ctx.domainSepTag.len:
    ctx.domainSepTag[i] = byte 0

  H.hash(ctx.secureBlinding, secureRandomBytes, accumSepTag)

func update*[Pubkey, Sig: ECP_ShortW_Aff](
       ctx: var BLSBatchSigAccumulator,
       pubkey: Pubkey,
       message: openArray[byte],
       signature: Sig): bool {.genCharAPI.} =
  ## Add a (public key, message, signature) triplet
  ## to a BLS signature accumulator
  ##
  ## Assumes that the public key and signature
  ## have been group checked
  ##
  ## Returns false if pubkey or signatures are the infinity points

  # The derivation of a secure scalar
  # MUST not output 0.
  # HKDF mod R for EIP2333 is suitable.
  # We can also consider using something
  # hardware-accelerated like AES.
  #
  # However the curve order r = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001
  # is 255 bits and 255-bit scalar mul on G2
  # costs 43% of a pairing and on G1 20%,
  # and we need to multiply both the signature
  # and the public key or message.
  # This blinding scheme would have a lot overhead
  # for single threaded.
  #
  # As we don't protect secret data here
  # and only want extra data not in possession of the attacker
  # we only use a 1..<2^64 random blinding factor.
  # We assume that the attacker cannot resubmit 2^64 times
  # forged public keys and signatures.
  #
  # Discussion https://ethresear.ch/t/fast-verification-of-multiple-bls-signatures/5407
  # See also
  # - Faster batch forgery identification
  #   Daniel J. Bernstein, Jeroen Doumen, Tanja Lange, and Jan-Jaap Oosterwijk, 2012
  #   https://eprint.iacr.org/2012/549

  # We only use the first 8 bytes for blinding
  # but use the full 32 bytes to derive new random scalar

  const k = BLSBatchSigAccumulator.k
  type H = BLSBatchSigAccumulator.H

  while true: # Ensure we don't multiply by 0 for blinding
    H.hash(ctx.secureBlinding, ctx.secureBlinding)

    var accum = byte 0
    for i in 0 ..< 8:
      accum = accum or ctx.secureBlinding[i]
    if accum != byte 0:
      break

  when Pubkey.G == G1:
    # Pubkey on G1, H(message) and Signature on G2
    var pkG1_jac {.noInit.}: ECP_ShortW_Jac[Pubkey.F, Pubkey.G]
    var sigG2_jac {.noInit.}: ECP_ShortW_Jac[Sig.F, Sig.G]

    pkG1_jac.fromAffine(pubkey)
    sigG2_jac.fromAffine(signature)

    var randFactor{.noInit.}: BigInt[64]
    randFactor.unmarshal(ctx.secureBlinding.toOpenArray(0, 7), bigEndian)
    pkG1_jac.scalarMul_vartime(randFactor)
    sigG2_jac.scalarMul_vartime(randFactor)

    if ctx.aggSigOnce == false:
      ctx.aggSig = sigG2_jac
      ctx.aggSigOnce = true
    else:
      ctx.aggSig += sigG2_jac

    type FF1 = BLSBatchSigAccumulator.FF1
    var pkG1_aff {.noInit.}: ECP_ShortW_Aff[FF1, G1]
    pkG1_aff.affine(pkG1_jac)

    type FF2 = BLSBatchSigAccumulator.FF2
    var hmsgG2_aff {.noInit.}: ECP_ShortW_Aff[FF2, G2]
    H.hashToCurve(
      k, output = hmsgG2_aff,
      augmentation = "", message,
      ctx.domainSepTag.toOpenArray(0, ctx.dst_len.int - 1))

    return ctx.millerAccum.update(pkG1_aff, hmsgG2_aff)

  else:
    # Pubkey on G2, H(message) and Signature on G1
    var hmsgG1_jac {.noInit.}: ECP_ShortW_Jac[Sig.F, Sig.G]
    var sigG1_jac {.noInit.}: ECP_ShortW_Jac[Sig.F, Sig.G]

    H.hashToCurve(
      k, output = hmsgG1_jac,
      augmentation = "", message,
      ctx.domainSepTag.toOpenArray(0, ctx.dst_len.int - 1))

    sigG1_jac.fromAffine(signature)

    var randFactor{.noInit.}: BigInt[64]
    randFactor.unmarshal(ctx.secureBlinding.toOpenArray(0, 7), bigEndian)
    hmsgG1_jac.scalarMul_vartime(randFactor)
    sigG1_jac.scalarMul_vartime(randFactor)

    if ctx.aggSigOnce == false:
      ctx.aggSig = sigG1_jac
      ctx.aggSigOnce = true
    else:
      ctx.aggSig += sigG1_jac

    type FF1 = BLSBatchSigAccumulator.FF1
    var hmsgG1_aff {.noInit.}: ECP_ShortW_Aff[FF1, G1]
    hmsgG1_aff.affine(hmsgG1_jac)
    return ctx.millerAccum.update(hmsgG1_aff, pubkey)

func update*[Pubkey, Sig: ECP_ShortW_Aff](
       ctx: var BLSBatchSigAccumulator,
       pubkey: Pubkey,
       message: View[byte],
       signature: Sig): bool {.inline.} =
  ctx.update(pubkey, message, signature)

func handover*(ctx: var BLSBatchSigAccumulator) {.inline.} =
  ## Prepare accumulator for cheaper merging.
  ##
  ## In a multi-threaded context, multiple accumulators can be created and process subsets of the batch in parallel.
  ## Accumulators can then be merged:
  ##    merger_accumulator += mergee_accumulator
  ## Merging will involve an expensive reduction operation when an accumulation threshold of 8 is reached.
  ## However merging two reduced accumulators is 136x cheaper.
  ##
  ## `Handover` forces this reduction on local threads to limit the burden on the merger thread.
  ctx.millerAccum.handover()

func merge*(ctxDst: var BLSBatchSigAccumulator, ctxSrc: BLSBatchSigAccumulator): bool =
  ## Merge 2 BLS signature accumulators: ctxDst <- ctxDst + ctxSrc
  ##
  ## Returns false if they have inconsistent DomainSeparationTag and true otherwise.
  if ctxDst.dst_len != ctxSrc.dst_len:
    return false
  if not equalMem(ctxDst.domainSepTag.addr, ctxSrc.domainSepTag.unsafeAddr, ctxDst.domainSepTag.len):
    return false

  ctxDst.millerAccum.merge(ctxSrc.millerAccum)

  if ctxDst.aggSigOnce and ctxSrc.aggSigOnce:
    ctxDst.aggSig += ctxSrc.aggSig
  elif ctxSrc.aggSigOnce:
    ctxDst.aggSig = ctxSrc.aggSig
    ctxDst.aggSigOnce = true

  BLSBatchSigAccumulator.H.hash(ctxDst.secureBlinding, ctxDst.secureBlinding, ctxSrc.secureBlinding)
  return true

func finalVerify*(ctx: var BLSBatchSigAccumulator): bool =
  ## Finish batch and/or aggregate signature verification and returns the final result.
  ##
  ## Returns false if nothing was accumulated
  ## Rteturns false on verification failure

  if not ctx.aggSigOnce:
    return false

  type FF1 = BLSBatchSigAccumulator.FF1
  type FF2 = BLSBatchSigAccumulator.FF2
  type Fpk = BLSBatchSigAccumulator.Fpk

  when BLSBatchSigAccumulator.SigAccum.G == G2:
    type PubKey = ECP_ShortW_Aff[FF1, G1]
  else:
    type PubKey = ECP_ShortW_Aff[FF2, G2]

  var negG {.noInit.}: Pubkey
  negG.neg(Pubkey.F.C.getGenerator($Pubkey.G))

  var aggSig {.noInit.}: ctx.aggSig.typeof().affine()
  aggSig.affine(ctx.aggSig)

  when BLSBatchSigAccumulator.SigAccum.G == G2:
    if not ctx.millerAccum.update(negG, aggSig):
      return false
  else:
    if not ctx.millerAccum.update(aggSig, negG):
      return false

  var gt {.noinit.}: Fpk
  ctx.millerAccum.finish(gt)
  gt.finalExp()
  return gt.isOne().bool

# ############################################################
#
#          Aggregate and Batched Signature Verification
#                      end-to-end
#
# ############################################################

func aggregate*[T: ECP_ShortW_Aff](r: var T, points: openarray[T]) =
  ## Aggregate pubkeys or signatures
  var accum {.noinit.}: ECP_ShortW_Jac[T.F, T.G]
  accum.sum_reduce_vartime(points)
  r.affine(accum)

func fastAggregateVerify*[Pubkey, Sig](
    pubkeys: openArray[Pubkey],
    message: openArray[byte],
    aggregateSignature: Sig,
    H: type CryptoHash,
    k: static int,
    domainSepTag: openArray[byte]): bool {.genCharAPI.} =
  ## Verify the aggregate of multiple signatures on the same message by multiple pubkeys
  ## Assumes pubkeys and sig have been checked for non-infinity and group-checked.

  if pubkeys.len == 0:
    return false

  var aggPubkey {.noinit.}: Pubkey
  aggPubkey.aggregate(pubkeys)

  if bool(aggPubkey.isInf()):
    return false

  aggPubkey.coreVerify(message, aggregateSignature, H, k, augmentation = "", domainSepTag)

func aggregateVerify*[Msg, Pubkey, Sig](
    pubkeys: openArray[Pubkey],
    messages: openArray[Msg],
    aggregateSignature: Sig,
    H: type CryptoHash,
    k: static int,
    domainSepTag: openarray[byte]): bool {.genCharAPI.} =
  ## Verify the aggregated signature of multiple (pubkey, message) pairs
  ## Assumes pubkeys and the aggregated signature have been checked for non-infinity and group-checked.
  ##
  ## To avoid splitting zeros and rogue keys attack:
  ## 1. Public keys signing the same message MUST be aggregated and checked for 0 before calling BLSAggregateSigAccumulator.update()
  ## 2. Augmentation or Proof of possessions must used for each public keys.

  if pubkeys.len == 0:
    return false

  if pubkeys.len != messages.len:
    return false

  type FF1 = Pubkey.F
  type FF2 = Sig.F
  type FpK = Sig.F.C.getGT()

  var accum {.noinit.}: BLSAggregateSigAccumulator[H, FF1, FF2, Fpk, k]
  accum.init(domainSepTag)

  for i in 0 ..< pubkeys.len:
    if not accum.update(pubkeys[i], messages[i]):
      return false

  return accum.finalVerify(aggregateSignature)

func batchVerify*[Msg, Pubkey, Sig](
    pubkeys: openArray[Pubkey],
    messages: openArray[Msg],
    signatures: openArray[Sig],
    H: type CryptoHash,
    k: static int,
    domainSepTag: openarray[byte],
    secureRandomBytes: array[32, byte]): bool {.genCharAPI.} =
  ## Verify that all (pubkey, message, signature) triplets are valid
  ##
  ## Returns false if there is at least one incorrect signature
  ##
  ## Assumes pubkeys and signatures have been checked for non-infinity and group-checked.
  ##
  ## This requires cryptographically-secure generated random bytes
  ## for scalar blinding
  ## to defend against forged signatures that would not
  ## verify individually but would verify while aggregated.
  ## I.e. we need an input that is not under the attacker control.
  ##
  ## The blinding scheme also assumes that the attacker cannot
  ## resubmit 2^64 times forged (publickey, message, signature) triplets
  ## against the same `secureRandomBytes`

  if pubkeys.len == 0:
    return false

  if pubkeys.len != messages.len or  pubkeys.len != signatures.len:
    return false

  type FF1 = Pubkey.F
  type FF2 = Sig.F
  type FpK = Sig.F.C.getGT()

  var accum {.noinit.}: BLSBatchSigAccumulator[H, FF1, FF2, Fpk, ECP_ShortW_Jac[Sig.F, Sig.G], k]
  accum.init(domainSepTag, secureRandomBytes, accumSepTag = "serial")

  for i in 0 ..< pubkeys.len:
    if not accum.update(pubkeys[i], messages[i], signatures[i]):
      return false

  return accum.finalVerify()
