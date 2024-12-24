# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/signatures/ecdsa,
  constantine/hashes/h_sha256,
  constantine/named/algebras,
  constantine/math/io/[io_bigints, io_fields, io_ec],
  constantine/math/elliptic/[ec_shortweierstrass_affine, ec_shortweierstrass_jacobian, ec_scalar_mul, ec_multi_scalar_mul],
  constantine/math/[arithmetic, ec_shortweierstrass],
  constantine/platforms/[abstractions, views],
  constantine/serialization/codecs, # for fromHex and (in the future) base64 encoding
  constantine/named/zoo_generators, # for generator
  constantine/csprngs/sysrand

export ecdsa ## XXX: shouldn't be needed once serialization is in submodules

## XXX: Move this as API in `constantine/ecdsa_secp256k1.nim`
# For easier readibility, define the curve and generator
# as globals in this file
const C* = Secp256k1

## XXX: Still need to adjust secp256k1 specific API & tests
proc signMessage*(message: string, secretKey: Fr[C],
                  nonceSampler: NonceSampler = nsRandom): tuple[r, s: Fr[C]] =
  ## WARNING: Convenience for development
  result.coreSign(secretKey, message.toOpenArrayByte(0, message.len-1), sha256, nonceSampler)

proc verifySignature*(
    message: string,
    signature: tuple[r, s: Fr[C]],
    publicKey: EC_ShortW_Aff[Fp[C], G1]
): bool =
  ## WARNING: Convenience for development
  result = publicKey.coreVerify(message.toOpenArrayByte(0, message.len-1), signature, sha256)

proc randomFieldElement[FF](): FF =
  ## random element in ~Fp[T]/Fr[T]~
  let m = FF.getModulus()
  var b: matchingBigInt(FF.Name)

  while b.isZero().bool or (b > m).bool:
    ## XXX: raise / what else to do if `sysrand` call fails?
    doAssert b.limbs.sysrand()

  result.fromBig(b)

proc generatePrivateKey*(): Fr[C] {.noinit.} =
  ## Generate a new private key using a cryptographic random number generator.
  result = randomFieldElement[Fr[C]]()

proc getPublicKey*(secKey: Fr[C]): EC_ShortW_Aff[Fp[C], G1] {.noinit.} =
  result.derivePubkey(secKey)


## XXX: move to serialization submodule

template toOA(x: openArray[byte]): untyped = toOpenArray[byte](x, 0, x.len - 1)

proc toBytes[Name: static Algebra; N: static int](res: var array[N, byte], x: FF[Name]) =
  discard res.marshal(x.toBig(), bigEndian)

proc toPemPrivateKey(res: var array[48, byte], privateKey: Fr[C]) =
  # Start with SEQUENCE
  res.rawCopy(0, toOA [byte(0x30), byte(0x2E)], 0, 2) ## XXX: Calc size

  # Version (always 1)
  res.rawCopy(2, toOA [byte(0x02), 1, 1], 0, 3)


  # Private key as octet string
  var privKeyBytes {.noinit.}: array[32, byte]  ## XXX: array size
  privKeyBytes.toBytes(privateKey)

  res.rawCopy(5, toOA [byte(0x04), byte(privKeyBytes.len)], 0, 2)
  res.rawCopy(7, toOA privKeyBytes, 0, 32) ## XXX: array size

  ## XXX: OID for curve!
  # Parameters (secp256k1 OID: 1.3.132.0.10)
  const Secp256k1Oid = [byte(0xA0), byte(7), byte(6), byte(5),
                        byte(0x2B), byte(0x81), byte(0x04), byte(0x00), byte(0x0A)]
  res.rawCopy(39, toOA Secp256k1Oid, 0, 9)

proc toPemPrivateKey(privateKey: Fr[C]): array[48, byte] =
  result.toPemPrivateKey(privateKey)

proc toPemPublicKey(res: var array[88, byte], publicKey: EC_ShortW_Aff[Fp[C], G1]) = ## XXX: array size
  # Start with SEQUENCE
  res.rawCopy(0, toOA [byte(0x30), byte(0x58)], 0, 2) ## XXX: ADjust total length!

  ## XXX: OID for curve!
  # Algorithm identifier
  const algoId = [
    byte(0x30), byte(0x10),                    # SEQUENCE
    byte(0x06), byte(0x07),                    # OID for EC
    byte(0x2A), byte(0x86), byte(0x48),        # 1.2.840.10045.2.1
    byte(0xCE), byte(0x3D), byte(0x02), byte(0x01),
    byte(0x06), byte(0x05),                    # OID for secp256k1
    byte(0x2B), byte(0x81), byte(0x04), byte(0x00), byte(0x0A) # 1.3.132.0.10
  ]

  res.rawCopy(2, toOA algoId, 0, 18)

  # Public key as bit string
  ## XXX: adjust length
  const encoding = [byte(0x03), byte(0x42)] # 2+32+32 prefix & coordinates
  const prefix = [
    byte(0x00),  # DER BIT STRING: number of unused bits (always 0 for keys)
    byte(0x04)   # SEC1: uncompressed point format marker
  ]

  template toByteArray(x: Fp[C] | Fr[C]): untyped =
    var a: array[32, byte] ## XXX: array size
    a.toBytes(x)
    a

  ## XXX: copy indices & sizes!
  res.rawCopy(20, toOA encoding, 0, 2)
  res.rawCopy(22, toOA prefix, 0, 2)
  res.rawCopy(24, toOA publicKey.x.toByteArray(), 0, 32)
  res.rawCopy(56, toOA publicKey.y.toByteArray(), 0, 32)

proc toPemPublicKey(publicKey: EC_ShortW_Aff[Fp[C], G1]): array[88, byte] =
  result.toPemPublicKey(publicKey)

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
