# https://github.com/ethereum/research/blob/master/kzg_data_availability/kzg_proofs.py

import
  constantine/named/algebras,
  constantine/math/[arithmetic, primitives, extension_fields],
  constantine/math/elliptic/[
    ec_scalar_mul,
    ec_shortweierstrass_affine,
    ec_shortweierstrass_projective,
  ],
  constantine/math/io/[io_fields, io_ec],
  constantine/math/pairings/[
    pairings_bls12,
    miller_loops
  ],
  # Research
  ./polynomials,
  ./fft_fr

type
  G1 = EC_ShortW_Prj[Fp[BLS12_381], G1]
  G2 = EC_ShortW_Prj[Fp2[BLS12_381], G2]

  KZGDescriptor = object
    fftDesc: FFTDescriptor[Fr[BLS12_381]]
    # [b.multiply(b.G1, pow(s, i, MODULUS)) for i in range(WIDTH+1)]
    secretG1: seq[G1]
    extendedSecretG1: seq[G1]
    # [b.multiply(b.G2, pow(s, i, MODULUS)) for i in range(WIDTH+1)]
    secretG2: seq[G2]

var Generator1: EC_ShortW_Aff[Fp[BLS12_381], G1]
doAssert Generator1.fromHex(
  "0x17f1d3a73197d7942695638c4fa9ac0fc3688c4f9774b905a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb",
  "0x08b3f481e3aaa0f1a09e30ed741d8ae4fcf5e095d5d00af600db18cb2c04b3edd03cc744a2888ae40caa232946c5e7e1"
)

var Generator2: EC_ShortW_Aff[Fp2[BLS12_381], G2]
doAssert Generator2.fromHex(
  "0x024aa2b2f08f0a91260805272dc51051c6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8",
  "0x13e02b6052719f607dacd3a088274f65596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e",
  "0x0ce5d527727d6e118cc9cdc6da2e351aadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801",
  "0x0606c4a02ea734cc32acd2b02bc28b99cb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be"
)

func init(
       T: type KZGDescriptor,
       fftDesc: FFTDescriptor[Fr[BLS12_381]],
       secretG1: seq[G1], secretG2: seq[G2]
      ): T =
  result.fftDesc = fftDesc
  result.secretG1 = secretG1
  result.secretG2 = secretG2

func commitToPoly(kzg: KZGDescriptor, r: var G1, poly: openarray[Fr[BLS12_381]]) =
  ## KZG commitment to polynomial in coefficient form
  r.linear_combination(kzg.secretG1, poly)

proc checkProofSingle(
       kzg: KZGDescriptor,
       commitment: G1,
       proof: G1,
       x, y: Fr[BLS12_381]
     ): bool =
  ## Check a proof for a Kate commitment for an evaluation f(x) = y
  var xG2, g2: G2
  g2.fromAffine(Generator2)
  xG2 = g2
  xG2.scalarMul(x)

  var s_minus_x: G2 # s is a secret coefficient from the trusted setup (? to be confirmed)
  s_minus_x.diff(kzg.secretG2[1], xG2)

  var yG1: G1
  yG1.fromAffine(Generator1)
  yG1.scalarMul(y)

  var commitment_minus_y: G1
  commitment_minus_y.diff(commitment, yG1)

  # Verify that e(commitment - [y]G1, Generator2) == e(proof, s - [x]G2)
  return pair_verify(commitment_minus_y, g2, proof, s_minus_x)
