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
