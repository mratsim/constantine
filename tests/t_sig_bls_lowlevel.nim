# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[os, times],
  # Internals
  ../constantine/backend/config/common,
  ../constantine/backend/[
    arithmetic, primitives,
    towers, ec_shortweierstrass,
    hashes
  ],
  ../constantine/backend/elliptic/ec_scalar_mul,
  ../constantine/backend/io/[io_fields, io_towers, io_ec],
  ../constantine/backend/config/curves,
  ../constantine/backend/curves/zoo_subgroups,
  ../constantine/backend/hash_to_curve/hash_to_curve,
  ../constantine/backend/pairing/pairing_bls12,
  # Test utilities
  ../helpers/prng_unsafe

# Testing implementation of BLS signature scheme
# with low-level primitives
# ----------------------------------------------

var rng: RngState
let timeseed = uint32(toUnix(getTime()) and (1'i64 shl 32 - 1)) # unixTime mod 2^32
seed(rng, timeseed)
echo "\n------------------------------------------------------\n"
echo "test_sig_bls xoshiro512** seed: ", timeseed

# Generators
# -------------------------------------------------------------
# https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-pairing-friendly-curves-10#section-4.2.1
#
const BLS12_381_G1_generator_x = Fp[BLS12_381].fromHex(
  "0x17f1d3a73197d7942695638c4fa9ac0fc3688c4f9774b905a14e3a3f171bac58" &
  "6c55e83ff97a1aeffb3af00adb22c6bb"
)

const BLS12_381_G1_generator_y = Fp[BLS12_381].fromHex(
  "0x08b3f481e3aaa0f1a09e30ed741d8ae4fcf5e095d5d00af600db18cb2c04b3ed" &
  "d03cc744a2888ae40caa232946c5e7e1"
)

const BLS12_381_G2_generator_x = Fp2[BLS12_381].fromHex(
  "0x024aa2b2f08f0a91260805272dc51051c6e47ad4fa403b02b4510b647ae3d177" &
  "0bac0326a805bbefd48056c8c121bdb8",
  "0x13e02b6052719f607dacd3a088274f65596bd0d09920b61ab5da61bbdc7f5049" &
  "334cf11213945d57e5ac7d055d042b7e"
)

const BLS12_381_G2_generator_y = Fp2[BLS12_381].fromHex(
  "0x0ce5d527727d6e118cc9cdc6da2e351aadfd9baa8cbdd3a76d429a695160d12c" &
  "923ac9cc3baca289e193548608b82801",
  "0x0606c4a02ea734cc32acd2b02bc28b99cb3e287e85a763af267492ab572e99ab" &
  "3f370d275cec1da1aaa9075ff05f79be"
)

const BLS12_381_G1_generator = ECP_ShortW_Aff[Fp[BLS12_381], G1](
  x: BLS12_381_G1_generator_x, y: BLS12_381_G1_generator_y
)
const BLS12_381_G2_generator = ECP_ShortW_Aff[Fp2[BLS12_381], G2](
  x: BLS12_381_G2_generator_x, y: BLS12_381_G2_generator_y
)

# We test using the pubkey on G1, signature on G2 scheme.
# with SHA256 hash and proof-of-possession. (Ethereum 2 config).
const DomainSepTag = "BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_"

func genSecretKey(rng: var RngState, seckey: var Fr[BLS12_381]) =
  # Don't do this at home!
  seckey = rng.random_unsafe(Fr[BLS12_381])
  while seckey.isZero().bool:
    seckey = rng.random_unsafe(Fr[BLS12_381])

func publicKeyG1(
       pubkey: var ECP_ShortW_Aff[Fp[BLS12_381], G1],
       seckey: Fr[BLS12_381]
     ) =
  var t: ECP_ShortW_Prj[Fp[BLS12_381], G1]
  t.fromAffine(BLS12_381_G1_generator)
  t.scalarMul(seckey.toBig())
  pubkey.affine(t)
  doAssert not bool pubkey.isInf()

func signG2[T: byte|char](
       signature: var ECP_ShortW_Aff[Fp2[BLS12_381], G2],
       message: openarray[T],
       secretKey: Fr[BLS12_381]
     ) =
  doAssert not bool secretKey.isZero()
  var t: ECP_ShortW_Prj[Fp2[BLS12_381], G2]
  hashToCurve(
    H = sha256, k = 128,
    output = t,
    augmentation = "",
    message = message,
    domainSepTag = DomainSepTag
  )
  t.scalarMul(secretKey.toBig())
  signature.affine(t)
  doAssert not bool signature.isInf()

func verifyG2[T: byte|char](
       pubkey: ECP_ShortW_Aff[Fp[BLS12_381], G1],
       message: openarray[T],
       signature: ECP_ShortW_Aff[Fp2[BLS12_381], G2]
     ): SecretBool =
  doAssert not pubkey.isInf.bool
  doAssert not signature.isInf.bool

  var Q {.noinit.}: typeof(signature)
  var Qprj {.noInit.}: ECP_ShortW_Prj[Fp2[BLS12_381], G2]
  hashToCurve(
    H = sha256, k = 128,
    output = Qprj,
    augmentation = "",
    message = message,
    domainSepTag = DomainSepTag
  )
  Q.affine(Qprj)

  var e0{.noInit.}, e1{.noInit.}: Fp12[BLS12_381]
  e0.pairing_bls12(pubkey, Q)
  e1.pairing_bls12(BLS12_381_G1_generator, signature)

  return e0 == e1

func verifyG2_multi[T: byte|char](
       pubkey: ECP_ShortW_Aff[Fp[BLS12_381], G1],
       message: openarray[T],
       signature: ECP_ShortW_Aff[Fp2[BLS12_381], G2]
     ): SecretBool =
  doAssert not pubkey.isInf.bool
  doAssert not signature.isInf.bool

  var Qprj {.noInit.}: ECP_ShortW_Prj[Fp2[BLS12_381], G2]
  hashToCurve(
    H = sha256, k = 128,
    output = Qprj,
    augmentation = "",
    message = message,
    domainSepTag = DomainSepTag
  )

  var G2s: array[2, ECP_ShortW_Aff[Fp2[BLS12_381], G2]]
  var G1s: array[2, ECP_ShortW_Aff[Fp[BLS12_381], G1]]

  G1s[0] = pubkey
  G2s[0].affine(Qprj)

  G1s[1].neg(BLS12_381_G1_generator)
  G2s[1] = signature

  var e: Fp12[BLS12_381]
  e.pairing_bls12(G1s, G2s)

  return e.isOne()

proc bls_signature_test(rng: var RngState, i: int) =
  var
    seckey: Fr[BLS12_381]
    pubkey: ECP_ShortW_Aff[Fp[BLS12_381], G1]
    message = rng.random_byte_seq(length = i)
    signature: ECP_ShortW_Aff[Fp2[BLS12_381], G2]

  rng.genSecretKey(seckey)
  pubkey.publicKeyG1(seckey)
  signature.signG2(message, seckey)

  let okSingle = pubkey.verifyG2(message, signature)
  doAssert bool okSingle

  let okMulti = pubkey.verifyG2_multi(message, signature)
  doAssert bool okMulti

for i in 0 ..< 500:
  rng.bls_signature_test(i)
  stdout.write('.')
  stdout.flushFile()
stdout.write('\n')

echo "SUCCESS - BLS Signature scheme on BLS12_381, pubkey on G1, signatures on G2"
