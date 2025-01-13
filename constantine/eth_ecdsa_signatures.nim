# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/zoo_exports,
  constantine/signatures/ecdsa,
  constantine/hashes,
  constantine/named/algebras,
  constantine/math/elliptic/[ec_shortweierstrass_affine],
  constantine/math/[arithmetic, ec_shortweierstrass],
  constantine/platforms/[abstractions, views]

export NonceSampler

const prefix_ffi = "ctt_eth_ecdsa"
type
  SecretKey* {.byref, exportc: prefix_ffi & "seckey".} = object
    ## A Secp256k1 secret key
    raw: Fr[Secp256k1]

  PublicKey* {.byref, exportc: prefix_ffi & "pubkey".} = object
    ## A Secp256k1 public key for ECDSA signatures
    raw: EC_ShortW_Aff[Fp[Secp256k1], G1]

  Signature* {.byref, exportc: prefix_ffi & "signature".} = object
    ## A Secp256k1 signature for ECDSA signatures
    r: Fr[Secp256k1]
    s: Fr[Secp256k1]

func pubkey_is_zero*(pubkey: PublicKey): bool {.libPrefix: prefix_ffi.} =
  ## Returns true if input is 0
  bool(pubkey.raw.isNeutral())

func pubkeys_are_equal*(a, b: PublicKey): bool {.libPrefix: prefix_ffi.} =
  ## Returns true if inputs are equal
  bool(a.raw == b.raw)

func signatures_are_equal*(a, b: Signature): bool {.libPrefix: prefix_ffi.} =
  ## Returns true if inputs are equal
  bool(a.r == b.r and a.s == b.s)

proc sign*(sig: var Signature,
           secretKey: SecretKey,
           message: openArray[byte],
           nonceSampler: NonceSampler = nsRandom) {.libPrefix: prefix_ffi, genCharAPI.} =
  ## Sign `message` using `secretKey` and store the signature in `sig`. The nonce
  ## will either be randomly sampled `nsRandom` or deterministically calculated according
  ## to RFC6979 (`nsRfc6979`)
  sig.coreSign(secretKey.raw, message, keccak256, nonceSampler)

proc verify*(
    publicKey: PublicKey,
    message: openArray[byte],
    signature: Signature
): bool {.libPrefix: prefix_ffi, genCharAPI.} =
  ## Verify `signature` using `publicKey` for `message`.
  result = publicKey.raw.coreVerify(message, signature, keccak256)

func derive_pubkey*(public_key: var PublicKey, secret_key: SecretKey) {.libPrefix: prefix_ffi.} =
  ## Derive the public key matching with a secret key
  ##
  ## The secret_key MUST be validated
  public_key.raw.derivePubkey(secret_key.raw)

proc recoverPubkey*(
    publicKey: var PublicKey,
    message: openArray[byte],
    signature: Signature,
    evenY: bool
) {.libPrefix: prefix_ffi, genCharAPI.} =
  ## Verify `signature` using `publicKey` for `message`.
  ##
  ## `evenY == true` returns the public key corresponding to the
  ## even `y` coordinate of the `R` point.
  publicKey.raw.recoverPubkey(signature, message, evenY, keccak256)

proc recoverPubkeyFromDigest*(
    publicKey: var PublicKey,
    msgHash: Fr[Secp256k1],
    signature: Signature,
    evenY: bool
) {.libPrefix: prefix_ffi.} =
  ## Verify `signature` using `publicKey` for the given message digest
  ## given as a scalar in the field `Fr[Secp256k1]`.
  ##
  ## `evenY == true` returns the public key corresponding to the
  ## even `y` coordinate of the `R` point.
  ##
  ## As this overload works directly with a message hash as a scalar,
  ## it requires no hash function. Internally, it also calls the
  ## `verify` implementation, which already takes a scalar and thus
  ## requires no hash function there either.
  publicKey.raw.recoverPubkeyImpl_vartime(signature, msgHash, evenY)
