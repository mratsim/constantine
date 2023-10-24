# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../math/config/curves,
  ../math/[ec_shortweierstrass, arithmetic, extension_fields],
  ../platforms/abstractions,
  ../serialization/endians,
  ../math/constants/zoo_generators,
  ../math/polynomials/polynomials,
  ../math/io/io_fields,

  std/streams # TODO: use the C streams which do not allocate, are exception-free and are guaranteed not to bring unremovable runtime procs.

# Ensure all exceptions are converted to error codes
{.push raises: [], checks: off.}

# Aliases
# ------------------------------------------------------------

# Presets
# ------------------------------------------------------------
const FIELD_ELEMENTS_PER_BLOB* {.intdefine.} = 4096

# Trusted setup
# ------------------------------------------------------------

const KZG_SETUP_G2_LENGTH = 65

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

    # Trusted setup, see https://vitalik.ca/general/2022/03/14/trustedsetup.html

    srs_lagrange_g1*{.align: 64.}: PolynomialEval[FIELD_ELEMENTS_PER_BLOB, ECP_ShortW_Aff[Fp[BLS12_381], G1]]
    # Part of the Structured Reference String (SRS) holding the 𝔾1 points
    # This is used for committing to polynomials and producing an opening proof at
    # a random value (chosen via Fiat-Shamir heuristic)
    #
    # Referring to the 𝔾1 generator as G, in monomial basis / coefficient form we would store:
    #   [G, [τ]G, [τ²]G, ... [τ⁴⁰⁹⁶]G]
    # with τ a random secret derived from a multi-party computation ceremony
    # with at least one honest random secret contributor (also called KZG ceremony or powers-of-tau ceremony)
    #
    # For efficiency we operate only on the evaluation form of polynomials over 𝔾1 (i.e. the Lagrange basis)
    # i.e. for agreed upon [ω⁰, ω¹, ..., ω⁴⁰⁹⁶]
    # we store [f(ω⁰), f(ω¹), ..., f(ω⁴⁰⁹⁶)]
    #
    # https://en.wikipedia.org/wiki/Lagrange_polynomial#Barycentric_form
    #
    # Conversion can be done with a discrete Fourier transform.

    srs_monomial_g2*{.align: 64.}: PolynomialCoef[KZG_SETUP_G2_LENGTH, ECP_ShortW_Aff[Fp2[BLS12_381], G2]]
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

    domain*{.align: 64.}: PolyDomainEval[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381]]

  TrustedSetupStatus* = enum
    tsSuccess
    tsMissingFile
    tsWrongPreset
    tsUnsupportedFileVersion
    tsInvalidFile
    tsLowLevelReadError

proc skipMod64(f: FileStream): TrustedSetupStatus =
  ## Skip to a 64-byte boundary
  try:
    let pos = f.getPosition()
    let posMod64 = pos and 63
    f.setPosition(pos+posMod64)
    return tsSuccess
  except IOError, OSError:
    return tsInvalidFile

proc loadTrustedSetup*(ctx: ptr EthereumKZGContext, filePath: string): TrustedSetupStatus =

  static: doAssert cpuEndian == littleEndian, "Trusted setup creation is only supported on little-endian CPUs at the moment."

  let f = try: openFileStream(filePath, fmRead)
          except IOError, OSError: return tsMissingFile

  defer:
    try:
      f.close()
    except Exception: # For some reason close can raise a bare Exception.
      quit "Unrecoverable error while closing trusted setup file."

  try:
    var buf = newSeqOfCap[byte](32)
    var len = 0

    buf.setLen(12)
    len = f.readData(buf[0].addr, 12)
    if len != 12:
      return tsInvalidFile
    if buf != static(@[byte 0xE2, 0x88, 0x83, 0xE2, 0x8B, 0x83, 0xE2, 0x88, 0x88, 0xE2, 0x88, 0x8E]):
      # ∃⋃∈∎ in UTF-8
      return tsInvalidFile

    if f.readChar() != 'v':
      return tsInvalidFile
    if f.readUint8() != 1:
      return tsUnsupportedFileVersion
    if f.readChar() != '.':
      return tsUnsupportedFileVersion
    if f.readUint8() != 0:
      return tsUnsupportedFileVersion

    buf.setLen(32)
    len = f.readData(buf[0].addr, 32)
    if len != 32:
      return tsInvalidFile
    if buf.toOpenArray(0, 17) != asBytes"ethereum_deneb_kzg":
      return tsWrongPreset
    if buf.toOpenArray(18, 31) != default(array[18..31, byte]):
      debugEcho buf.toOpenArray(18, 31)
      return tsWrongPreset

    buf.setLen(15)
    len = f.readData(buf[0].addr, 15)
    if len != 15:
      return tsInvalidFile
    if buf.toOpenArray(0, 8) != asBytes"bls12_381":
      return tsWrongPreset
    if buf.toOpenArray(9, 14) != default(array[9..14, byte]):
      return tsWrongPreset

    let num_fields = f.readUint8()
    if num_fields != 3:
      return tsWrongPreset

    block: # Read 1st metadata
      buf.setLen(32)
      len = f.readData(buf[0].addr, 32)
      if len != 32:
        return tsInvalidFile
      if buf.toOpenArray(0, 11) != asBytes"srs_lagrange":
        return tsWrongPreset
      if buf.toOpenArray(12, 14) != default(array[12..14, byte]):
        return tsWrongPreset
      if buf.toOpenArray(15, 19) != asBytes"g1brp":
        return tsWrongPreset
      let elemSize = uint32.fromBytes(buf.toOpenArray(20, 23), littleEndian)
      if elemSize != uint32 sizeof(ECP_ShortW_Aff[Fp[BLS12_381], G1]):
        return tsWrongPreset
      let numElems = uint64.fromBytes(buf.toOpenArray(24, 31), littleEndian)
      if numElems != FIELD_ELEMENTS_PER_BLOB:
        return tsWrongPreset

    block: # Read 2nd metadata
      buf.setLen(32)
      len = f.readData(buf[0].addr, 32)
      if len != 32:
        return tsInvalidFile
      if buf.toOpenArray(0, 11) != asBytes"srs_monomial":
        return tsWrongPreset
      if buf.toOpenArray(12, 14) != default(array[12..14, byte]):
        return tsWrongPreset
      if buf.toOpenArray(15, 19) != asBytes"g2asc":
        return tsWrongPreset
      let elemSize = uint32.fromBytes(buf.toOpenArray(20, 23), littleEndian)
      if elemSize != uint32 sizeof(ECP_ShortW_Aff[Fp2[BLS12_381], G2]):
        return tsWrongPreset
      let numElems = uint64.fromBytes(buf.toOpenArray(24, 31), littleEndian)
      if numElems != KZG_SETUP_G2_LENGTH:
        return tsWrongPreset

    block: # Read 3rd metadata
      buf.setLen(32)
      len = f.readData(buf[0].addr, 32)
      if len != 32:
        return tsInvalidFile
      if buf.toOpenArray(0, 10) != asBytes"roots_unity":
        return tsWrongPreset
      if buf.toOpenArray(11, 14) != default(array[11..14, byte]):
        return tsWrongPreset
      if buf.toOpenArray(15, 19) != asBytes"frbrp":
        return tsWrongPreset
      let elemSize = uint32.fromBytes(buf.toOpenArray(20, 23), littleEndian)
      if elemSize != uint32 sizeof(Fr[BLS12_381]):
        return tsWrongPreset
      let numElems = uint64.fromBytes(buf.toOpenArray(24, 31), littleEndian)
      if numElems != FIELD_ELEMENTS_PER_BLOB:
        return tsWrongPreset

    block: # Read 1st data, assume little-endian
      let status64Balign = f.skipMod64()
      if status64Balign != tsSuccess:
        return status64Balign

      len = f.readData(ctx.srs_lagrange_g1.addr, sizeof(ctx.srs_lagrange_g1))
      if len != sizeof(ctx.srs_lagrange_g1):
        return tsInvalidFile

    block: # Read 2nd data, assume little-endian
      let status64Balign = f.skipMod64()
      if status64Balign != tsSuccess:
        return status64Balign

      len = f.readData(ctx.srs_monomial_g2.addr, sizeof(ctx.srs_monomial_g2))
      if len != sizeof(ctx.srs_monomial_g2):
        return tsInvalidFile

    block: # Read 3rd data, assume little-endian
      let status64Balign = f.skipMod64()
      if status64Balign != tsSuccess:
        return status64Balign

      len = f.readData(ctx.domain.rootsOfUnity.addr, sizeof(ctx.domain.rootsOfUnity))
      if len != sizeof(ctx.domain.rootsOfUnity):
        return tsInvalidFile

      # Compute the inverse of the domain degree
      ctx.domain.invMaxDegree.fromUint(ctx.domain.rootsOfUnity.len.uint64)
      ctx.domain.invMaxDegree.inv_vartime()

    block: # Last sanity check
      # When the srs is in monomial form we can check that
      # the first point is the generator
      if bool(ctx.srs_monomial_g2.coefs[0] != BLS12_381.getGenerator"G2"):
        return tsWrongPreset

    return tsSuccess

  except IOError, OSError:
    return tsLowLevelReadError