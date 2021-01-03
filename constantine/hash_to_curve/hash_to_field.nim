# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ../hashes,
  ../io/endians

import stew/byteutils # debug

# ############################################################
#
#                Hash to Finite Fields
#
# ############################################################

# No exceptions allowed in core cryptographic operations
{.push raises: [].}

# Helpers
# ----------------------------------------------------------------
func ceilDiv(a, b: uint): uint =
  ## ceil division
  ## ceil(a / b)
  (a + b - 1) div b

proc copyFrom[N](output: var openarray[byte], bi: array[N, byte], cur: var uint) =
  var b_index = 0'u
  while b_index < bi.len.uint and cur < output.len.uint:
    output[cur] = bi[b_index]
    inc cur
    inc b_index

template strxor(b_i: var array, b0: array): untyped =
  for i in 0 ..< b_i.len:
    b_i[i] = b_i[i] xor b0[i]
# ----------------------------------------------------------------

func shortDomainSepTag[DigestSize: static int, B: byte|char](
       H: type CryptoHash,
       output: var array[DigestSize, byte],
       oversizedDST: openarray[B]) =
  ## Compute a short Domain Separation Tag
  ## from a domain separation tag larger than 255 bits
  ##
  ## https://tools.ietf.org/html/draft-irtf-cfrg-hash-to-curve-09#section-5.4.3
  static: doAssert DigestSize == H.type.digestSize
  var ctx {.noInit.}: H
  ctx.init()
  ctx.update"H2C-OVERSIZE-DST-"
  ctx.update oversizedDST
  ctx.finish(output)

func expandMessageXMD*[B1, B2, B3: byte|char](
       H: type CryptoHash,
       output: var openarray[byte],
       augmentation: openarray[B1],
       message: openarray[B2],
       domainSepTag: openarray[B3]
     ) =
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
  ##   https://tools.ietf.org/html/draft-irtf-cfrg-bls-signature-04#section-3.2
  ##   which requires `CoreSign(SK, PK || message)`
  ##   and `CoreVerify(PK, PK || message, signature)`
  ## - `message` is the message to hash
  ## - `domainSepTag` is the protocol domain separation tag.
  ##   If a domainSepTag larger than 255-bit is required,
  ##   it is recommended to cache the reduce

  # TODO oversized DST support

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

  assert output.len mod 8 == 0

  let ell = ceilDiv(output.len.uint, DigestSize.uint)
  const zPad = default(array[BlockSize, byte])
  let l_i_b_str = output.len.uint16.toBytesBE()

  var b0 {.noinit, align: DigestSize.}: array[DigestSize, byte]
  func ctZpad(): Hash =
    # Compile-time precompute
    # TODO upstream: `toOpenArray` throws "cannot generate code for: mSlice"
    result.init()
    result.update zPad
  var ctx = ctZpad() # static(ctZpad())
  ctx.update augmentation
  ctx.update message
  ctx.update l_i_b_str
  ctx.update [byte 0]
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
