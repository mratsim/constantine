# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../math/polynomials/fft,
  ../math/[arithmetic, extension_fields, ec_shortweierstrass],
  ../math/config/curves,
  ../math/elliptic/[ec_scalar_mul_vartime, ec_shortweierstrass_batch_ops],
  ../math/io/io_fields,
  ../math/constants/zoo_generators,
  ../platforms/abstractions,
  ../serialization/endians,
  std/streams

# This tool generates the same testing setups that are used in Ethereum consensus-spec
# in a Constantine-specific format specified in README.md

# Trusted setup source:
#
# - Minimal preset: https://github.com/ethereum/consensus-specs/blob/v1.3.0/presets/minimal/trusted_setups/testing_trusted_setups.json
# - Mainnet preset: https://github.com/ethereum/consensus-specs/blob/v1.3.0/presets/mainnet/trusted_setups/testing_trusted_setups.json
#
# The upstream trusted setups are stored in `./tests/protocol_ethereum_deneb_kzg`
#
# The upstream testing setup generator is:
# - dump_kzg_trusted_setup_files
#   https://github.com/ethereum/consensus-specs/blob/v1.3.0/tests/core/pyspec/eth2spec/utils/kzg.py#L96-L123
# Called with
# - python3 ./gen_kzg_trusted_setups.py --secret=1337 --g1-length=4 --g2-length=65
#   python3 ./gen_kzg_trusted_setups.py --secret=1337 --g1-length=4096 --g2-length=65
#   https://github.com/ethereum/consensus-specs/blob/v1.3.0/Makefile#L209-L210

# Roots of unity
# ------------------------------------------------------------
#
# Computation:
#   Reference: https://crypto.stanford.edu/pbc/notes/numbertheory/gen.html
#
#   1. Find a primitive root of the finite field of modulus q
#      i.e. root^k != 1 for all k < q-1 so powers of root generate the field.
#
#   sagemath: GF(r).multiplicative_generator()
#
#   2. primitive_root⁽ᵐᵒᵈᵘˡᵘˢ⁻¹⁾/⁽²^ⁱ⁾ for i in [0, 32)
#
#   sagemath: [primitive_root^((r-1)//(1 << i)) for i in range(32)]
#
# Usage:
#   The roots of unity ω allow usage of polynomials in evaluation form (Lagrange basis)
#   see ω https://dankradfeist.de/ethereum/2021/06/18/pcs-multiproofs.html
#
# Where does the 32 come from?
#   Recall the definition of the BLS12-381 curve:
#   sagemath:
#     x = -(2^63 + 2^62 + 2^60 + 2^57 + 2^48 + 2^16)
#     order = x^4 - x^2 + 1
#
#   and check the 2-adicity
#     factor(order-1)
#     => 2^32 * 3 * 11 * 19 * 10177 * 125527 * 859267 * 906349^2 * 2508409 * 2529403 * 52437899 * 254760293^2
#
#   BLS12-381 was chosen for its high 2-adicity, as 2^32 is a factor of its order-1

const ctt_eth_kzg_fr_pow2_roots_of_unity = [
  # primitive_root⁽ᵐᵒᵈᵘˡᵘˢ⁻¹⁾/⁽²^ⁱ⁾ for i in [0, 32)
  # The primitive root chosen is 7
  Fr[BLS12_381].fromHex"0x1",
  Fr[BLS12_381].fromHex"0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000000",
  Fr[BLS12_381].fromHex"0x8d51ccce760304d0ec030002760300000001000000000000",
  Fr[BLS12_381].fromHex"0x345766f603fa66e78c0625cd70d77ce2b38b21c28713b7007228fd3397743f7a",
  Fr[BLS12_381].fromHex"0x20b1ce9140267af9dd1c0af834cec32c17beb312f20b6f7653ea61d87742bcce",
  Fr[BLS12_381].fromHex"0x50e0903a157988bab4bcd40e22f55448bf6e88fb4c38fb8a360c60997369df4e",
  Fr[BLS12_381].fromHex"0x45af6345ec055e4d14a1e27164d8fdbd2d967f4be2f951558140d032f0a9ee53",
  Fr[BLS12_381].fromHex"0x6898111413588742b7c68b4d7fdd60d098d0caac87f5713c5130c2c1660125be",
  Fr[BLS12_381].fromHex"0x4f9b4098e2e9f12e6b368121ac0cf4ad0a0865a899e8deff4935bd2f817f694b",
  Fr[BLS12_381].fromHex"0x95166525526a65439feec240d80689fd697168a3a6000fe4541b8ff2ee0434e",
  Fr[BLS12_381].fromHex"0x325db5c3debf77a18f4de02c0f776af3ea437f9626fc085e3c28d666a5c2d854",
  Fr[BLS12_381].fromHex"0x6d031f1b5c49c83409f1ca610a08f16655ea6811be9c622d4a838b5d59cd79e5",
  Fr[BLS12_381].fromHex"0x564c0a11a0f704f4fc3e8acfe0f8245f0ad1347b378fbf96e206da11a5d36306",
  Fr[BLS12_381].fromHex"0x485d512737b1da3d2ccddea2972e89ed146b58bc434906ac6fdd00bfc78c8967",
  Fr[BLS12_381].fromHex"0x56624634b500a166dc86b01c0d477fa6ae4622f6a9152435034d2ff22a5ad9e1",
  Fr[BLS12_381].fromHex"0x3291357ee558b50d483405417a0cbe39c8d5f51db3f32699fbd047e11279bb6e",
  Fr[BLS12_381].fromHex"0x2155379d12180caa88f39a78f1aeb57867a665ae1fcadc91d7118f85cd96b8ad",
  Fr[BLS12_381].fromHex"0x224262332d8acbf4473a2eef772c33d6cd7f2bd6d0711b7d08692405f3b70f10",
  Fr[BLS12_381].fromHex"0x2d3056a530794f01652f717ae1c34bb0bb97a3bf30ce40fd6f421a7d8ef674fb",
  Fr[BLS12_381].fromHex"0x520e587a724a6955df625e80d0adef90ad8e16e84419c750194e8c62ecb38d9d",
  Fr[BLS12_381].fromHex"0x3e1c54bcb947035a57a6e07cb98de4a2f69e02d265e09d9fece7e0e39898d4b",
  Fr[BLS12_381].fromHex"0x47c8b5817018af4fc70d0874b0691d4e46b3105f04db5844cd3979122d3ea03a",
  Fr[BLS12_381].fromHex"0xabe6a5e5abcaa32f2d38f10fbb8d1bbe08fec7c86389beec6e7a6ffb08e3363",
  Fr[BLS12_381].fromHex"0x73560252aa0655b25121af06a3b51e3cc631ffb2585a72db5616c57de0ec9eae",
  Fr[BLS12_381].fromHex"0x291cf6d68823e6876e0bcd91ee76273072cf6a8029b7d7bc92cf4deb77bd779c",
  Fr[BLS12_381].fromHex"0x19fe632fd3287390454dc1edc61a1a3c0ba12bb3da64ca5ce32ef844e11a51e",
  Fr[BLS12_381].fromHex"0xa0a77a3b1980c0d116168bffbedc11d02c8118402867ddc531a11a0d2d75182",
  Fr[BLS12_381].fromHex"0x23397a9300f8f98bece8ea224f31d25db94f1101b1d7a628e2d0a7869f0319ed",
  Fr[BLS12_381].fromHex"0x52dd465e2f09425699e276b571905a7d6558e9e3f6ac7b41d7b688830a4f2089",
  Fr[BLS12_381].fromHex"0xc83ea7744bf1bee8da40c1ef2bb459884d37b826214abc6474650359d8e211b",
  Fr[BLS12_381].fromHex"0x2c6d4e4511657e1e1339a815da8b398fed3a181fabb30adc694341f608c9dd56",
  Fr[BLS12_381].fromHex"0x4b5371495990693fad1715b02e5713b5f070bb00e28a193d63e7cb4906ffc93f"
]

func newTrustedSetupImpl(
       EC: typedesc, secret: auto, length: int): seq[EC] =

  result.setLen(length)

  var P {.noInit.}: EC
  P.fromAffine(EC.F.C.getGenerator($EC.G))
  result[0] = P
  for i in 1 ..< length:
    P.scalarMul_minHammingWeight_windowed_vartime(secret, window = 5)
    result[i] = P

func newTrustedSetupMonomial(EC: typedesc, secret: auto, length: int): seq[EC] =
  let ts = newTrustedSetupImpl(projective(EC), secret, length)
  result.setLen(length)
  batchAffine(result.asUnchecked(), ts.asUnchecked(), length)

func getLagrange[EC](fftDesc: ECFFT_Descriptor[EC], monomial: seq[EC]): seq[EC] =
  ## Get a polynomial in lagrange basis from a polynomial in monomial form.
  ## The polynomial is also bit-reversal permuted.

  result.setLen(monomial.len)
  let status = fftDesc.ifft_vartime(result, monomial)
  doAssert status == FFTS_Success, "Ethereum testing trusted setup failure during Lagrange form: " & $status

  result.bit_reversal_permutation()

func newTrustedSetupLagrange[EC](fftDesc: ECFFT_Descriptor[EC], secret: auto, length: int): auto =
  let ts = newTrustedSetupImpl(EC, secret, length)
  let ts2 = fftDesc.getLagrange(ts)

  let tsAffine = newSeq[affine(EC)](length)
  batchAffine(tsAffine.asUnchecked(), ts2.asUnchecked(), length)
  return tsAffine

proc padNUL64(f: FileStream) =
  ## Pad NUL bytes until we reach a 64-byte boundary
  let pos = f.getPosition()
  let posMod64 = pos and 63

  let pad = default(array[63, byte])
  if posMod64 != 0:
    f.writeData(pad[0].unsafeAddr, 64-posMod64)

proc genEthereumKzgTestingTrustedSetup(filepath: string, secret: auto, length: int) =
  ## Generate an Ethereum KZG testing trusted setup
  ## in the Trusted Setup Interchange Format
  ## `length` is the length of the SRS 𝔾1
  ## the SRS 𝔾2 is fixed at 65.
  ## SRS 𝔾1 and roots of unity are bit-reversal permuted

  static: doAssert cpuEndian == littleEndian, "Trusted setup creation is only supported on little-endian CPUs at the moment."
  doAssert length.uint.isPowerOf2_vartime(), "Expected power of 2 but found length " & $length

  let f = openFileStream(filepath, fmWrite)
  defer: f.close()

  f.write"∃⋃∈∎" # ∃⋃∈∎ in UTF-8. (magic bytes)

  # v1.0
  f.write 'v'
  f.write uint8 1
  f.write '.'
  f.write uint8 0

  # Protocol
  const proto = "ethereum_deneb_kzg"
  f.write proto
  let padProto = default(array[32 - proto.len, byte]) # zero-init padding
  f.writeData(padProto[0].unsafeAddr, padProto.len)

  # Curve
  const curve = "bls12_381"
  f.write curve
  let padCurve = default(array[15 - curve.len, byte]) # zero-init padding
  f.writeData(padCurve[0].unsafeAddr, padCurve.len)

  # Number of fields
  f.write uint8 3

  block: # Metadata 1 - srs 𝔾1 points - bit-reversal permuted
    var meta: array[32, byte]
    meta[0..<12] = asBytes"srs_lagrange"

    meta[15..<17] = asBytes"g1"
    meta[17..<20] = asBytes"brp"
    meta[20..<24] = toBytes(uint32 sizeof(ECP_ShortW_Aff[Fp[BLS12_381], G1]), littleEndian)
    meta[24..<32] = toBytes(uint64 length, littleEndian)

    f.write meta

  block: # Metadata 2 - srs 𝔾2 points (hardcoded to 65)
    var meta: array[32, byte]
    meta[0..<12] = asBytes"srs_monomial"

    meta[15..<17] = asBytes"g2"
    meta[17..<20] = asBytes"asc"
    meta[20..<24] = toBytes(uint32 sizeof(ECP_ShortW_Aff[Fp2[BLS12_381], G2]), littleEndian)
    meta[24..<32] = toBytes(65'u64, littleEndian)

    f.write meta

  # Projective coordinates are slightly faster than jacobian on 𝔾1
  var fftDesc = ECFFTDescriptor[ECP_ShortW_Prj[Fp[BLS12_381], G1]].new(
    order = length, ctt_eth_kzg_fr_pow2_roots_of_unity[log2_vartime(length.uint)])
  defer: fftDesc.delete()

  block: # Metadata 3 - roots of unity - bit-reversal permuted
    var meta: array[32, byte]
    meta[0..<11] = asBytes"roots_unity"

    meta[15..<17] = asBytes"fr"
    meta[17..<20] = asBytes"brp"
    meta[20..<24] = toBytes(uint32 sizeof(fftDesc.rootsOfUnity[0]), littleEndian)
    meta[24..<32] = toBytes(fftDesc.order.uint64, littleEndian)

    f.write meta

  f.padNUL64()

  block: # Data 1 - srs 𝔾1 points - bit-reversal permuted
    let ts1 = fftDesc.newTrustedSetupLagrange(secret, length)
    # Raw dump requires little-endian
    f.writeData(ts1[0].unsafeAddr, sizeof(ts1[0]) * length)

  f.padNUL64()

  block: # Data 2 - srs 𝔾2 points
    const g2Length = 65
    let ts2 = ECP_ShortW_Aff[Fp2[BLS12_381], G2].newTrustedSetupMonomial(secret, g2Length)
    # Raw dump requires little-endian
    f.writeData(ts2[0].unsafeAddr, sizeof(ts2[0]) * g2Length)

  f.padNUL64()

  bit_reversal_permutation(fftDesc.rootsOfUnity.toOpenArray(0, fftDesc.order-1))
  block: # Data 3 - roots of unity - bit-reversal permuted
    # Raw dump requires little-endian
    # and we convert them all to Montgomery form
    for i in 0 ..< fftDesc.order:
      let t = Fr[BLS12_381].fromBig(fftDesc.rootsOfUnity[i])
      f.writeData(t.unsafeAddr, sizeof(t))

when isMainModule:
  import ../math/io/io_bigints

  let testSecret = BigInt[11].fromUint(1337'u64)
  genEthereumKzgTestingTrustedSetup("trusted_setup_ethereum_kzg_test_minimal.tsif", testSecret, 4)
  genEthereumKzgTestingTrustedSetup("trusted_setup_ethereum_kzg_test_mainnet.tsif", testSecret, 4096)