# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ../platforms/[abstractions, views],
  ../serialization/endians,
  ../hashes,
  ../math/io/[io_bigints, io_fields],
  ../math/config/curves,
  ../math/arithmetic/limbs_montgomery,
  ../math/extension_fields/towers

# ############################################################
#
#                Hash to Finite Fields
#
# ############################################################

# No exceptions allowed in core cryptographic operations
{.push raises: [].}

# Helpers
# ----------------------------------------------------------------
proc copyFrom[M, N: static int](output: var array[M, byte], bi: array[N, byte], cur: var uint) =
  static: doAssert M mod N == 0
  for i in 0'u ..< N:
    output[cur+i] = bi[i]
  cur += N.uint

template strxor(b_i: var array, b0: array): untyped =
  for i in 0 ..< b_i.len:
    b_i[i] = b_i[i] xor b0[i]
# ----------------------------------------------------------------

func shortDomainSepTag*[DigestSize: static int](
       H: type CryptoHash,
       output: var array[DigestSize, byte],
       oversizedDST: openArray[byte]) {.genCharAPI.} =
  ## Compute a short Domain Separation Tag
  ## from a domain separation tag larger than 255 bytes
  ##
  ## https://tools.ietf.org/html/draft-irtf-cfrg-hash-to-curve-14#section-5.4.3
  static: doAssert DigestSize == H.type.digestSize
  var ctx {.noInit.}: H
  ctx.init()
  ctx.update"H2C-OVERSIZE-DST-"
  ctx.update oversizedDST
  ctx.finish(output)

func expandMessageXMD*[len_in_bytes: static int](
       H: type CryptoHash,
       output: var array[len_in_bytes, byte],
       augmentation: openArray[byte],
       message: openArray[byte],
       domainSepTag: openArray[byte]
     ) {.genCharAPI.} =
  ## The expand_message_xmd function produces a uniformly random byte
  ## string using a cryptographic hash function H that outputs "b" bits,
  ## with b >= 2*k and k the target security level (for example 128-bit)
  ##
  ## https://tools.ietf.org/html/draft-irtf-cfrg-hash-to-curve-09#section-5.4.1
  ##
  ## Arguments:
  ## - `Hash` a cryptographic hash function.
  ##   - `Hash` MAY be a Merkle-Damgaard hash function like SHA-2
  ##   - `Hash` MAY be a sponge-based hash function like SHA-3 or BLAKE2
  ##   - Otherwise, H MUST be a hash function that has been proved
  ##    indifferentiable from a random oracle [MRH04] under a reasonable
  ##    cryptographic assumption.
  ## - `output`, a buffer dimensioned the requested length.
  ##   it will be filled with bits indifferentiable from a random oracle.
  ## - `augmentation`, an optional augmentation to the message. This will be prepended,
  ##   prior to hashing.
  ##   This is used for building the "message augmentation" variant of BLS signatures
  ##   https://www.ietf.org/archive/id/draft-irtf-cfrg-bls-signature-05.html#section-3.2
  ##   which requires `CoreSign(SK, PK || message)`
  ##   and `CoreVerify(PK, PK || message, signature)`
  ## - `message` is the message to hash
  ## - `domainSepTag` is the protocol domain separation tag (DST).
  ##   `domainSepTag` MUST be at most 255 bytes.
  ##   The function `shortDomainSepTag` MUST be used to compute an adequate DST
  ##   for an oversized source DST.
  ##   That DST can be cached.
  # Steps:
  # 1.  ell = ceil(len_in_bytes / b_in_bytes)
  # 2.  ABORT if ell > 255
  # 3.  DST_prime = DST || I2OSP(len(DST), 1)
  # 4.  Z_pad = I2OSP(0, r_in_bytes)
  # 5.  l_i_b_str = I2OSP(len_in_bytes, 2)
  # 6.  msg_prime = Z_pad || msg || l_i_b_str || I2OSP(0, 1) || DST_prime
  # 7.  b_0 = H(msg_prime)
  # 8.  b_1 = H(b_0 || I2OSP(1, 1) || DST_prime)
  # 9.  for i in (2, ..., ell):
  # 10.    b_i = H(strxor(b_0, b_(i - 1)) || I2OSP(i, 1) || DST_prime)
  # 11. uniform_bytes = b_1 || ... || b_ell
  # 12. return substr(uniform_bytes, 0, len_in_bytes)
  mixin digestSize
  type Hash = H # Otherwise the VM says "cannot evaluate at compiletime H"
  const DigestSize = Hash.digestSize()
  const BlockSize = Hash.internalBlockSize()

  static:
    doAssert output.len mod 8 == 0  # By spec
    doAssert output.len mod 32 == 0 # Assumed by copy optimization

  let ell = output.len.ceilDiv_vartime(DigestSize)
  var l_i_b_str0 {.noInit.}: array[3, byte]
  l_i_b_str0.dumpRawInt(output.len.uint16, cursor = 0, bigEndian)
  l_i_b_str0[2] = 0

  var b0 {.noinit, align: DigestSize.}: array[DigestSize, byte]
  var ctx {.noInit.}: Hash
  ctx.initZeroPadded()
  ctx.update augmentation
  ctx.update message
  ctx.update l_i_b_str0
  # ctx.update [byte 0] # already appended to l_i_b_str
  ctx.update domainSepTag
  ctx.update [byte domainSepTag.len] # DST_prime
  ctx.finish(b0)

  var cur = 0'u
  var bi {.noinit, align: DigestSize.}: array[DigestSize, byte]
  # b1
  ctx.init()
  ctx.update(b0)
  ctx.update([byte 1])
  ctx.update domainSepTag
  ctx.update [byte domainSepTag.len] # DST_prime
  ctx.finish(bi)
  output.copyFrom(bi, cur)

  for i in 2 .. ell:
    ctx.init()
    strxor(bi, b0)
    ctx.update(bi)
    ctx.update([byte i])
    ctx.update domainSepTag
    ctx.update [byte domainSepTag.len] # DST_prime
    ctx.finish(bi)
    output.copyFrom(bi, cur)
    if cur == output.len.uint:
      return

func redc2x[FF](r: var FF, big2x: BigInt) {.inline.} =
  r.mres.limbs.redc2xMont(
    big2x.limbs,
    FF.fieldMod().limbs,
    FF.getNegInvModWord(),
    FF.getSpareBits()
  )

func mulMont(r: var BigInt, a, b: BigInt, FF: type) {.inline.} =
  r.limbs.mulMont(
    a.limbs, b.limbs,
    FF.fieldMod().limbs,
    FF.getNegInvModWord(),
    FF.getSpareBits()
  )

func hashToField*[Field; count: static int](
       H: type CryptoHash,
       k: static int,
       output: var array[count, Field],
       augmentation: openArray[byte],
       message: openArray[byte],
       domainSepTag: openArray[byte]
     ) {.genCharAPI.} =
  ## Hash to a field or an extension field
  ## https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-11#section-5.3
  ##
  ## Arguments:
  ## - `Hash` a cryptographic hash function.
  ##   - `Hash` MAY be a Merkle-Damgaard hash function like SHA-2
  ##   - `Hash` MAY be a sponge-based hash function like SHA-3 or BLAKE2
  ##   - Otherwise, H MUST be a hash function that has been proved
  ##    indifferentiable from a random oracle [MRH04] under a reasonable
  ##    cryptographic assumption.
  ## - k the security parameter of the suite in bits (for example 128)
  ## - `output`, an array of fields or extension fields.
  ## - `augmentation`, an optional augmentation to the message. This will be prepended,
  ##   prior to hashing.
  ##   This is used for building the "message augmentation" variant of BLS signatures
  ##   https://www.ietf.org/archive/id/draft-irtf-cfrg-bls-signature-05.html#section-3.2
  ##   which requires `CoreSign(SK, PK || message)`
  ##   and `CoreVerify(PK, PK || message, signature)`
  ## - `message` is the message to hash
  ## - `domainSepTag` is the protocol domain separation tag (DST).
  ##   If a domainSepTag larger than 255-bit is required,
  ##   it is recommended to cache the reduced DST.

  const
    L = ceilDiv_vartime(Field.C.getCurveBitwidth() + k, 8)
    m = block:
      when Field is Fp: 1
      elif Field is Fp2: 2
      else: {.error: "Unconfigured".}

    len_in_bytes = count * m * L

  var uniform_bytes{.noInit.}: array[len_in_bytes, byte]
  H.expandMessageXMD(
    uniform_bytes,
    augmentation = augmentation,
    message = message,
    domainSepTag = domainSepTag
  )

  for i in 0 ..< count:
    for j in 0 ..< m:
      let elm_offset = L * (j + i * m)
      template tv: untyped = uniform_bytes.toOpenArray(elm_offset, elm_offset + L-1)

      var big2x {.noInit.}: BigInt[2 * getCurveBitwidth(Field.C)]
      big2x.unmarshal(tv, bigEndian)

      # Reduces modulo p and output in Montgomery domain
      when m == 1:
        output[i].redc2x(big2x)
        output[i].mres.mulMont(
          output[i].mres,
          Fp[Field.C].getR3ModP(),
          Fp[Field.C])

      else:
        output[i].coords[j].redc2x(big2x)
        output[i].coords[j].mres.mulMont(
          output[i].coords[j].mres,
          Fp[Field.C].getR3ModP(),
          Fp[Field.C])
