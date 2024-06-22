# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./commitments/eth_verkle_ipa,
  ./math/[arithmetic, ec_twistededwards],
  ./math/config/curves,
  ./serialization/[codecs_status_codes, codecs_banderwagon]

# Ethereum Verkle IPA public API
# ------------------------------------------------------------
#
# We use a simple goto state machine to handle errors and cleanup (if allocs were done)
# and have 2 different checks:
# - Either we are in "HappyPath" section that shortcuts to resource cleanup on error
# - or there are no resources to clean and we can early return from a function.

type
  cttEthVerkleIpaStatus* = enum
    cttEthVerkleIpa_Success
    cttEthVerkleIpa_VerificationFailure
    cttEthVerkleIpa_InputsLengthsMismatch
    cttEthVerkleIpa_ScalarZero
    cttEthVerkleIpa_ScalarLargerThanCurveOrder
    cttEthVerkleIpa_EccInvalidEncoding
    cttEthVerkleIpa_EccCoordinateGreaterThanOrEqualModulus
    cttEthVerkleIpa_EccPointNotOnCurve
    cttEthVerkleIpa_EccPointNotInSubGroup

template checkReturn(evalExpr: CttCodecScalarStatus): untyped {.dirty.} =
  # Translate codec status code to KZG status code
  # Beware of resource cleanup like heap allocation, this can early exit the caller.
  block:
    let status = evalExpr # Ensure single evaluation
    case status
    of cttCodecScalar_Success:                          discard
    of cttCodecScalar_Zero:                             discard
    of cttCodecScalar_ScalarLargerThanCurveOrder:       return cttEthVerkleIpa_ScalarLargerThanCurveOrder

template checkReturn(evalExpr: CttCodecEccStatus): untyped {.dirty.} =
  # Translate codec status code to KZG status code
  # Beware of resource cleanup like heap allocation, this can early exit the caller.
  block:
    let status = evalExpr # Ensure single evaluation
    case status
    of cttCodecEcc_Success:                             discard
    of cttCodecEcc_InvalidEncoding:                     return cttEthVerkleIpa_EccInvalidEncoding
    of cttCodecEcc_CoordinateGreaterThanOrEqualModulus: return cttEthVerkleIpa_EccCoordinateGreaterThanOrEqualModulus
    of cttCodecEcc_PointNotOnCurve:                     return cttEthVerkleIpa_EccPointNotOnCurve
    of cttCodecEcc_PointNotInSubgroup:                  return cttEthVerkleIpa_EccPointNotInSubGroup
    of cttCodecEcc_PointAtInfinity:                     discard

template check(Section: untyped, evalExpr: CttCodecScalarStatus): untyped {.dirty.} =
  # Translate codec status code to KZG status code
  # Exit current code block
  block:
    let status = evalExpr # Ensure single evaluation
    case status
    of cttCodecScalar_Success:                          discard
    of cttCodecScalar_Zero:                             discard
    of cttCodecScalar_ScalarLargerThanCurveOrder:       result = cttEthVerkleIpa_ScalarLargerThanCurveOrder; break Section

template check(Section: untyped, evalExpr: CttCodecEccStatus): untyped {.dirty.} =
  # Translate codec status code to KZG status code
  # Exit current code block
  block:
    let status = evalExpr # Ensure single evaluation
    case status
    of cttCodecEcc_Success:                             discard
    of cttCodecEcc_InvalidEncoding:                     result = cttEthVerkleIpa_EccInvalidEncoding; break Section
    of cttCodecEcc_CoordinateGreaterThanOrEqualModulus: result = cttEthVerkleIpa_EccCoordinateGreaterThanOrEqualModulus; break Section
    of cttCodecEcc_PointNotOnCurve:                     result = cttEthVerkleIpa_EccPointNotOnCurve; break Section
    of cttCodecEcc_PointNotInSubgroup:                  result = cttEthVerkleIpa_EccPointNotInSubGroup; break Section
    of cttCodecEcc_PointAtInfinity:                     discard

type
  EthVerkleIpaProofBytes* = array[544, byte]
  EthVerkleIpaMultiProofBytes* = array[576, byte]
  EthVerkleIpaProof* = IpaProof[8, ECP_TwEdwards[Fp[Banderwagon]], Fr[Banderwagon]]
  EthVerkleIpaMultiProof* = IpaMultiProof[8, ECP_TwEdwards[Fp[Banderwagon]], Fr[Banderwagon]]

  # The aliases may throw strange errors like:
  # - Error: invalid type: 'EthVerkleIpaProof' for var
  # - Error: cannot instantiate: 'src:type'
  # as of Nim v2.0.4

func serialize*(dst: var EthVerkleIpaProofBytes,
                src: IpaProof[8, ECP_TwEdwards[Fp[Banderwagon]], Fr[Banderwagon]]
                ): cttEthVerkleIpaStatus {.discardable.} =
  # Note: We store 1 out of 2 coordinates of an EC point, so size(Fp[Banderwagon])
  const fpb = sizeof(Fp[Banderwagon])
  const frb = sizeof(Fr[Banderwagon])

  let L = cast[ptr array[8, array[fpb, byte]]](dst.addr)
  let R = cast[ptr array[8, array[fpb, byte]]](dst[8 * fpb].addr)
  let a0 = cast[ptr array[frb, byte]](dst[2 * 8 * fpb].addr)

  for i in 0 ..< 8:
    L[i].serialize(src.L[i])

  for i in 0 ..< 8:
    R[i].serialize(src.R[i])

  a0[].serialize_fr(src.a0, littleEndian)
  return cttEthVerkleIpa_Success

func deserialize*(dst: var EthVerkleIpaProof,
                  src: EthVerkleIpaProofBytes): cttEthVerkleIpaStatus =

  const fpb = sizeof(Fp[Banderwagon])
  const frb = sizeof(Fr[Banderwagon])

  let L = cast[ptr array[8, array[fpb, byte]]](src.addr)
  let R = cast[ptr array[8, array[fpb, byte]]](src[8 * fpb].addr)
  let a0 = cast[ptr array[frb, byte]](src[2 * 8 * fpb].addr)

  for i in 0 ..< 8:
    checkReturn dst.L[i].deserialize(L[i])

  for i in 0 ..< 8:
    checkReturn dst.R[i].deserialize(R[i])

  checkReturn dst.a0.deserialize_fr(a0[], littleEndian)
  return cttEthVerkleIpa_Success

func serialize*(dst: var EthVerkleIpaMultiProofBytes,
                src: IpaMultiProof[8, ECP_TwEdwards[Fp[Banderwagon]], Fr[Banderwagon]]
                ): cttEthVerkleIpaStatus {.discardable.} =

  const frb = sizeof(Fr[Banderwagon])
  let D = cast[ptr array[frb, byte]](dst.addr)
  let g2Proof = cast[ptr EthVerkleIpaProofBytes](dst[frb].addr)

  D[].serialize(src.D)
  g2Proof[].serialize(src.g2_proof)
  return cttEthVerkleIpa_Success

func deserialize*(dst: var EthVerkleIpaMultiProof,
                  src: EthVerkleIpaMultiProofBytes
                  ): cttEthVerkleIpaStatus =

  const frb = sizeof(Fr[Banderwagon])
  let D = cast[ptr array[frb, byte]](src.addr)
  let g2Proof = cast[ptr EthVerkleIpaProofBytes](src[frb].addr)

  checkReturn dst.D.deserialize(D[])
  return dst.g2_proof.deserialize(g2Proof[])
