# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/named/algebras,
  constantine/math/[arithmetic, extension_fields],
  constantine/math/elliptic/[ec_shortweierstrass_affine, ec_shortweierstrass_jacobian, ec_shortweierstrass_batch_ops, ec_multi_scalar_mul_precomp],
  constantine/math/polynomials/[polynomials, fft_fields, fft_ec],
  constantine/math/io/io_fields,
  constantine/platforms/[allocs, bithacks, fileio, views, abstractions],
  constantine/serialization/[codecs, codecs_status_codes, codecs_bls12_381],
  constantine/commitments/kzg_multiproofs

# Ensure all exceptions are converted to error codes
{.push raises: [], checks: off.}

# C API prefix
# -------------------
import ../zoo_exports

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

const ctt_eth_kzg4844_fr_pow2_roots_of_unity = [
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

template getRootOfUnityForSize(size: static int): Fr[BLS12_381] =
  ## size MUST be a power of 2
  bind ctt_eth_kzg4844_fr_pow2_roots_of_unity
  const scale = log2_vartime(uint32 size)
  ctt_eth_kzg4844_fr_pow2_roots_of_unity[scale]

func computeRootsOfUnity(dst: var openArray[Fr[BLS12_381]], generatorRootOfUnity: Fr[BLS12_381]) =
  dst[0].setOne()
  var cur = generatorRootOfUnity
  for i in 1 ..< dst.len:
    dst[i] = cur
    cur *= generatorRootOfUnity

# Trusted setup
# ------------------------------------------------------------

const FIELD_ELEMENTS_PER_BLOB* = 4096
const FIELD_ELEMENTS_PER_EXT_BLOB* = 2 * FIELD_ELEMENTS_PER_BLOB
const KZG_SETUP_G2_LENGTH = 65

# EIP-7594 PeerDAS constants
# https://eips.ethereum.org/EIPS/eip-7594
# https://github.com/ethereum/consensus-specs/blob/v1.7.0-alpha.3/specs/fulu/polynomial-commitments-sampling.md
const FIELD_ELEMENTS_PER_CELL* = 64
const CELLS_PER_BLOB* = FIELD_ELEMENTS_PER_BLOB div FIELD_ELEMENTS_PER_CELL
const CELLS_PER_EXT_BLOB* = FIELD_ELEMENTS_PER_EXT_BLOB div FIELD_ELEMENTS_PER_CELL
const BYTES_PER_CELL* = FIELD_ELEMENTS_PER_CELL * 32

type
  PolyphaseKind* = enum
    kNoPrecompute
    kPrecompute

type
  PolyphaseSpectrumBank* = object
    rawPoints* {.align: 64.}: array[CELLS_PER_EXT_BLOB, array[FIELD_ELEMENTS_PER_CELL, EC_ShortW_Aff[Fp[BLS12_381], G1]]]
    case kind*: PolyphaseKind
    of kNoPrecompute:
      discard
    of kPrecompute:
      precompPoints* {.align: 64.}: array[CELLS_PER_EXT_BLOB, PrecomputedMSM[EC_ShortW_Jac[Fp[BLS12_381], G1], FIELD_ELEMENTS_PER_CELL]]

# On the number of 𝔾2 points:
#   - In the Deneb specs, https://github.com/ethereum/consensus-specs/blob/v1.3.0/specs/deneb/polynomial-commitments.md
#     only KZG_SETUP_G2[1] is used.
#   - In SONIC, section 6.2, https://eprint.iacr.org/2019/099.pdf
#     H and [α]H, the generator of 𝔾2 and its scalar multiplication by a random secret from trusted setup, are needed.
#   - In Marlin, section 2.5, https://eprint.iacr.org/2019/1047.pdf
#     H and [β]H, the generator of 𝔾2 and its scalar multiplication by a random secret from trusted setup, are needed.
#   - In Plonk, section 3.1, https://eprint.iacr.org/2019/953
#     [1]₂ and [x]₂, i.e. [1] scalar multiplied by the generator of 𝔾2 and [x] scalar multiplied by the generator of 𝔾2, x a random secret from trusted setup, are needed.
#   - In Vitalik's Plonk article, section Polynomial commitments, https://vitalik.ca/general/2019/09/22/plonk.html#polynomial-commitments
#     [s]G₂, i.e a random secret [s] scalar multiplied by the generator of 𝔾2, is needed
#
#   The extra 63 points are expected to be used for sharding https://github.com/ethereum/consensus-specs/blob/v1.3.0/specs/_features/sharding/polynomial-commitments.md
#   for KZG multiproofs for 64 shards: https://dankradfeist.de/ethereum/2021/06/18/pcs-multiproofs.html
#
# Note:
#   The batched proofs (different polynomials) used in Deneb specs
#   are different from multiproofs

type
  EthereumKZGContext* = object
    ## KZG commitment context

    # It can be very confusing to follow:
    # - natural order, bit-reversed permuted, reversed
    # - monomial/coefficient, and evaluation/lagrange form
    # - powers of tau / srs for commitments, roots of unity for FFT
    # - domain / bit-reverse permuted roots of unity for polynomial evaluation
    #   vs natural order roots of unity (in FFT descriptor) for FFT

    # Trusted setup, see https://vitalik.ca/general/2022/03/14/trustedsetup.html

    srs_lagrange_brp_g1*{.align: 64.}: PolynomialEval[FIELD_ELEMENTS_PER_BLOB, EC_ShortW_Aff[Fp[BLS12_381], G1], kBitReversed]
    # Part of the Structured Reference String (SRS) holding the 𝔾1 points
    # Stored in bit-reversed evaluation / Lagrange form
    #
    # This is used in EIP-4844 for committing to polynomials and producing an opening proof at
    # a random value (chosen via Fiat-Shamir heuristic)
    #
    # Referring to the 𝔾1 generator as G, in monomial basis / coefficient form we would store:
    #   [G, [τ]G, [τ²]G, ... [τ⁴⁰⁹⁶]G]
    # with τ a random secret derived from a multi-party computation ceremony
    # with at least one honest random secret contributor (also called KZG ceremony or powers-of-tau ceremony)
    #
    # In EIP-4844 we operate only on the evaluation form of polynomials over 𝔾1 (i.e. the Lagrange basis)
    # i.e. for agreed upon [ω⁰, ω¹, ..., ω⁴⁰⁹⁶]
    # we store [f(ω⁰), f(ω¹), ..., f(ω⁴⁰⁹⁶)]
    #
    # https://en.wikipedia.org/wiki/Lagrange_polynomial#Barycentric_form
    #
    # Conversion can be done with a discrete Fourier transform. In EIP-4844 we operate only on the evaluation form of polynomials over 𝔾1 (i.e. the Lagrange basis)

    srs_monomial_g1*{.align: 64.}: PolynomialCoef[FIELD_ELEMENTS_PER_BLOB, EC_ShortW_Aff[Fp[BLS12_381], G1]]
    # Part of the Structured Reference String (SRS) holding the 𝔾1 points
    # Stores the powers of tau
    #   [G, [τ]G, [τ²]G, ... [τ⁴⁰⁹⁶]G]
    # in coefficient / monomial form
    #
    # This is used in EIP-7594 to produce KZG multiproofs

    srs_monomial_g2*{.align: 64.}: PolynomialCoef[KZG_SETUP_G2_LENGTH, EC_ShortW_Aff[Fp2[BLS12_381], G2]]
    # Part of the SRS holding the 𝔾2 points
    #
    # Referring to the 𝔾2 generator as H, we store
    #   [H, [τ]H, [τ²]H, ..., [τ⁶⁴]H]
    # with τ a random secret derived from a multi-party computation ceremony
    # with at least one honest random secret contributor (also called KZG ceremony or powers-of-tau ceremony)
    #
    # This is used to verify commitments.
    # For most schemes (Marlin, Plonk, Sonic, Ethereum's Deneb), only [τ]H is needed
    # but Ethereum's sharding will need 64 (65 with the generator H)

    domain_brp*{.align: 64.}: PolyEvalRootsDomain[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381], kBitReversed]
    # The domain field holds the roots of unity of the polynomial evaluation domain.
    # Important: for Ethereum, roots of unity are used in bit-reversed order

    ecfft_desc_ext*{.align: 64.}: ECFFT_Descriptor[EC_ShortW_Jac[Fp[BLS12_381], G1]]
    fft_desc_ext*{.align: 64.}: FrFFT_Descriptor[Fr[BLS12_381]]
    # FFT descriptors are precomputed
    # They hold rootsOfUnity stored in natural order.
    #
    # The extended domain roots are stored in fft_desc_ext.rootsOfUnity
    # and can be accessed when needed (e.g., in recover functions).

    polyphaseSpectrumBank*{.align: 64.}: PolyphaseSpectrumBank
    # Precomputed data for FK20 KZG multiproofs.
    # kPrecompute variant holds PrecomputedMSM tables (one per output position),
    # each table for MSM of size 64 (FIELD_ELEMENTS_PER_CELL).
    # Default: t=64, b=12.
    # Size: ~4.33 MiB per table × 128 tables ≈ 554 MB total
    #
    # This combines
    # - FK23: https://eprint.iacr.org/2023/033
    #   for the base algorithm for KZG multiproofs via coset proofs
    # - Herold-Hagopian precomputed MSMs
    #   initially designed for Verkle Tries
    #   - https://hackmd.io/WfIjm0icSmSoqy2cfqenhQ
    #   - https://hackmd.io/@jsign/vkt-another-iteration-of-vkt-msms

  TrustedSetupStatus* = enum
    tsSuccess
    tsMissingOrInaccessibleFile
    tsInvalidFile

  TrustedSetupFormat* = enum
    kReferenceCKzg4844

proc load_ckzg4844(ctx: ptr EthereumKZGContext, f: File, t: int = 64, b: int = 12): TrustedSetupStatus =
  ## Read a trusted setup in the reference library c-kzg-4844 format
  # Format is the following (c-kzg-4844 with Monomial G1 for FK20):
  # <nG1: number of G1 points>
  # <nG2: number of G2 points>
  # <Hex encoding of compressed G1 point (Lagrange): 0>
  # ...
  # <Hex encoding of compressed G1 point (Lagrange): nG1 - 1>
  # <Hex encoding of compressed G2 point (Monomial): 0>
  # ...
  # <Hex encoding of compressed G2 point (Monomial): nG2 - 1>
  # <Hex encoding of compressed G1 point (Monomial): 0>
  # ...
  # <Hex encoding of compressed G1 point (Monomial): nG1 - 1>
  #
  # Each line is terminated by new line/line feed (binary byte 10)
  #
  # The compressed encoding of BLS12-381 points requires the first bit
  # to be set, hence there is no omitted leading zeros to deal with:
  # - a G1 point always takes  96 hex characters + 1 newline
  # - a G2 point always takes 192 hex characters + 1 newline

  const g1Bytes = 48
  const g2Bytes = 96

  # fscanf and \r, \n (CRLF, end-of-line) peculiarities.
  # We open files in binary mode, to ensure same treatment on Windows and Unix.
  # However `git clone` (or other tools) might auto-convert to CRLF on Windows,
  # so the parser needs to be able to parse both \n and \r\n line endings.
  #
  # We harden all use with a width parameter to prevent:
  # - undefined behavior on int overflow
  # - buffer overflow on lines being too long.

  # fscanf for up to 4 digits. fscanf ignores whitespaces and \r when parsing an int
  const parseInt32 = "%4u\n"
  # fscanf for up to 96 chars, up until EOL, reporting number read, with EOL skipping
  const readHexG1 = "%96[^\r\n]%n%*[\r\n]"
  # fscanf for up to 192 chars, up until EOL, reporting number read, with EOL skipping
  const readHexG2 = "%192[^\r\n]%n%*[\r\n]"

  block:
    var num_matches: cint
    var n: cuint

    # G1 points metadata
    num_matches = f.c_fscanf(parseInt32, n.addr)
    if num_matches != 1 or n != FIELD_ELEMENTS_PER_BLOB:
      return tsInvalidFile

    # G2 points metadata
    num_matches = f.c_fscanf(parseInt32, n.addr)
    if num_matches != 1 or n != KZG_SETUP_G2_LENGTH:
      return tsInvalidFile

  block:
    # G1 points - 96 characters + newline
    # These are the Lagrange form (bit-reversed evaluation) points
    # Original ceremony files:
    # - https://github.com/ethereum/kzg-ceremony-verifier/blob/master/output_setups/trusted_setup_4096.json
    # - https://github.com/ethereum/c-kzg-4844/blob/v2.1.7/src/trusted_setup.txt
    # On disk, G1 points are stored in natural order and will need bit-reversal
    var bufG1Hex {.noInit.}: array[2*g1Bytes+1, char] # On MacOS, an extra byte seems to be needed for fscanf or AddressSanitizer complains
    var bufG1bytes {.noInit.}: array[g1Bytes, byte]
    var charsRead: cint
    for i in 0 ..< FIELD_ELEMENTS_PER_BLOB:
      let num_matches = f.c_fscanf(readHexG1, bufG1Hex.addr, charsRead.addr)
      if num_matches != 1 or charsRead != 2*g1Bytes:
        return tsInvalidFile
      bufG1bytes.fromHex(bufG1Hex.toOpenArray(0, 2*g1Bytes-1))
      let status = ctx.srs_lagrange_brp_g1.evals[i].deserialize_g1_compressed(bufG1bytes)
      if status != cttCodecEcc_Success:
        c_printf("[Constantine Trusted Setup] Invalid G1 point on line %d: CttCodecEccStatus code %d\n", cint(2+i), status)
        return tsInvalidFile

  block:
    # G2 points - 192 characters + newline
    var bufG2Hex {.noInit.}: array[2*g2Bytes+1, char] # On MacOS, an extra byte seems to be needed for fscanf or AddressSanitizer complains
    var bufG2bytes {.noInit.}: array[g2Bytes, byte]
    var charsRead: cint
    for i in 0 ..< KZG_SETUP_G2_LENGTH:
      let num_matches = f.c_fscanf(readHexG2, bufG2Hex.addr, charsRead.addr)
      if num_matches != 1 or charsRead != 2*g2Bytes:
        return tsInvalidFile
      bufG2bytes.fromHex(bufG2Hex.toOpenArray(0, 2*g2Bytes-1))
      let status = ctx.srs_monomial_g2.coefs[i].deserialize_g2_compressed(bufG2bytes)
      if status != cttCodecEcc_Success:
        c_printf("[Constantine Trusted Setup] Invalid G2 point on line %d: CttCodecEccStatus code %d\n", cint(2+FIELD_ELEMENTS_PER_BLOB+i), status)
        return tsInvalidFile

  block:
    # G1 points (Monomial form) - 96 characters + newline
    # These are needed for FK20 multiproof computation (EIP-7594)
    var bufG1Hex {.noInit.}: array[2*g1Bytes+1, char]
    var bufG1bytes {.noInit.}: array[g1Bytes, byte]
    var charsRead: cint
    for i in 0 ..< FIELD_ELEMENTS_PER_BLOB:
      let num_matches = f.c_fscanf(readHexG1, bufG1Hex.addr, charsRead.addr)
      if num_matches != 1 or charsRead != 2*g1Bytes:
        return tsInvalidFile
      bufG1bytes.fromHex(bufG1Hex.toOpenArray(0, 2*g1Bytes-1))
      let status = ctx.srs_monomial_g1.coefs[i].deserialize_g1_compressed(bufG1bytes)
      if status != cttCodecEcc_Success:
        c_printf("[Constantine Trusted Setup] Invalid G1 Monomial point on line %d: CttCodecEccStatus code %d\n", cint(2+FIELD_ELEMENTS_PER_BLOB+KZG_SETUP_G2_LENGTH+i), status)
        return tsInvalidFile

  block:
    # Initialize FFT descriptors
    ctx.ecfft_desc_ext = ECFFT_Descriptor[EC_ShortW_Jac[Fp[BLS12_381], G1]].new(
      order = FIELD_ELEMENTS_PER_EXT_BLOB,
      generatorRootOfUnity = getRootOfUnityForSize(FIELD_ELEMENTS_PER_EXT_BLOB)
    )

    # Domain: FIELD_ELEMENTS_PER_EXT_BLOB (8192) roots of unity
    ctx.fft_desc_ext = FrFFT_Descriptor[Fr[BLS12_381]].new(
      order = FIELD_ELEMENTS_PER_EXT_BLOB,
      generatorRootOfUnity = getRootOfUnityForSize(FIELD_ELEMENTS_PER_EXT_BLOB)
    )

  block:
    # Compute polyphase decomposition (offset-major) as affine points.
    type BLS12_381_G1_Aff = EC_ShortW_Aff[Fp[BLS12_381], G1]
    let tmp = allocHeapAligned(array[FIELD_ELEMENTS_PER_CELL, array[CELLS_PER_EXT_BLOB, BLS12_381_G1_Aff]], 64)
    defer: freeHeapAligned(tmp)
    computePolyphaseDecompositionFourier(tmp[], ctx.srs_monomial_g1, ctx.ecfft_desc_ext)

    # Build raw affine points for kNoPrecompute variant (position-major).
    for pos in 0 ..< CELLS_PER_EXT_BLOB:
      for offset in 0 ..< FIELD_ELEMENTS_PER_CELL:
        ctx.polyphaseSpectrumBank.rawPoints[pos][offset] = tmp[offset][pos]

    # Build PrecomputedMSM tables if t > 0 and b > 0.
    if t > 0 and b > 0:
      ctx.polyphaseSpectrumBank.kind = kPrecompute
      for pos in 0 ..< CELLS_PER_EXT_BLOB:
        var points {.noInit.}: array[FIELD_ELEMENTS_PER_CELL, BLS12_381_G1_Aff]
        for offset in 0 ..< FIELD_ELEMENTS_PER_CELL:
          points[offset] = tmp[offset][pos]
        ctx.polyphaseSpectrumBank.precompPoints[pos].init(points, t = t, b = b)
    else:
      ctx.polyphaseSpectrumBank.kind = kNoPrecompute
  block:
    # Powers of tau: [G, [τ]G, [τ²]G, ... [τ⁴⁰⁹⁶]G]

    # Bit-reverse the Lagrange form points (for EIP-4844 commitments)
    ctx.srs_lagrange_brp_g1.evals.bit_reversal_permutation()

    # G1 Monomial points are already loaded from the trusted setup file

  block:
    # Initialize domain (bit-reversed roots of unity for polynomial evaluation)
    # Domain: FIELD_ELEMENTS_PER_BLOB (4096) roots of unity (bit-reversed)
    ctx.domain_brp.rootsOfUnity.computeRootsOfUnity(generatorRootOfunity = getRootOfUnityForSize(FIELD_ELEMENTS_PER_BLOB))
    ctx.domain_brp.rootsOfUnity.bit_reversal_permutation()
    ctx.domain_brp.invMaxDegree.fromUint(ctx.domain_brp.rootsOfUnity.len.uint64)
    ctx.domain_brp.invMaxDegree.inv_vartime()

  return tsSuccess


proc load_from_file(ctx: var ptr EthereumKZGContext, filepath: cstring, format: TrustedSetupFormat, t: int = 64, b: int = 12): TrustedSetupStatus =
  ## Load from a trusted setup file.

  ctx = alloc0HeapAligned(EthereumKZGContext, alignment = 64)

  var f: File
  let ok = f.open(filepath, kRead)
  if not ok:
    return tsMissingOrInaccessibleFile

  assert format == kReferenceCKzg4844, "Only c-kzg-4844 .txt format is supported"

  let status = ctx.load_ckzg4844(f, t, b)
  fileio.close(f)
  return status


proc new*(ctx: var ptr EthereumKZGContext, filepath: cstring, format: TrustedSetupFormat): TrustedSetupStatus {.exportc: "ctt_eth_kzg_context_new".} =
  return ctx.load_from_file(filepath, format, t = 0, b = 0)

proc new_with_precompute*(ctx: var ptr EthereumKZGContext, filepath: cstring, format: TrustedSetupFormat, t, b: int): TrustedSetupStatus {.exportc: "ctt_eth_kzg_context_new_with_precompute".} =
  return ctx.load_from_file(filepath, format, t = t, b = b)

proc delete*(ctx: ptr EthereumKZGContext) {.exportc: "ctt_eth_kzg_context_delete".} =
  if not ctx.isNil:
    case ctx.polyphaseSpectrumBank.kind
    of kNoPrecompute: discard
    of kPrecompute:
      for i in 0 ..< CELLS_PER_EXT_BLOB:
        `=destroy`(ctx.polyphaseSpectrumBank.precompPoints[i])
    `=destroy`(ctx.ecfft_desc_ext)
    `=destroy`(ctx.fft_desc_ext)
    freeHeapAligned(ctx)
