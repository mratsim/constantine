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
  constantine/named/algebras,
  ./serialization/[codecs_status_codes, codecs_banderwagon]

# ------------------------------------------------------------
# TODO: finish refactoring generate_random_points
import
  ./platforms/allocs,
  ./hashes,
  ./serialization/endians,
  ./math/io/[io_bigints, io_fields]

import ./zoo_exports

const EthVerkleSeed* = "eth_verkle_oct_2021"

func generate_random_points*(r: var openArray[EC_TwEdw_Aff[Fp[Banderwagon]]]) =
  ## generate_random_points generates random points on the curve with the hardcoded EthVerkleSeed
  let points = allocHeapArrayAligned(EC_TwEdw_Aff[Fp[Banderwagon]], r.len, alignment = 64)

  var points_found: seq[EC_TwEdw_Aff[Fp[Banderwagon]]]
  var incrementer: uint64 = 0
  var idx: int = 0
  while true:
    var ctx {.noInit.}: sha256
    ctx.init()
    ctx.update(EthVerkleSeed)
    ctx.update(incrementer.toBytes(bigEndian))
    var hash : array[32, byte]
    ctx.finish(hash)
    ctx.clear()

    var x {.noInit.}:  Fp[Banderwagon]
    var t {.noInit.}: Fp[Banderwagon].getBigInt()

    t.unmarshal(hash, bigEndian)
    x.fromBig(t)

    incrementer = incrementer + 1

    var x_arr {.noInit.}: array[32, byte]
    x_arr.marshal(x, bigEndian)

    var x_p {.noInit.}: EC_TwEdw_Aff[Fp[Banderwagon]]
    let stat2 = x_p.deserialize_vartime(x_arr)
    if stat2 == cttCodecEcc_Success:
      points_found.add(x_p)
      points[idx] = points_found[idx]
      idx = idx + 1

    if points_found.len == r.len:
      break

  for i in 0 ..< r.len:
    r[i] = points[i]
  freeHeapAligned(points)

# ------------------------------------------------------------

# Ethereum Verkle IPA public API
# ------------------------------------------------------------
#
# We use a simple goto state machine to handle errors and cleanup (if allocs were done)
# and have 2 different checks:
# - Either we are in "HappyPath" section that shortcuts to resource cleanup on error
# - or there are no resources to clean and we can early return from a function.

const EthVerkleDomain* = 256

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

# Serialization
# ------------------------------------------------------------------------------------

type
  EthVerkleIpaProofBytes* = array[544, byte]
  EthVerkleIpaMultiProofBytes* = array[576, byte]
  EthVerkleIpaProof* = IpaProof[8, EC_TwEdw[Fp[Banderwagon]], Fr[Banderwagon]]
  EthVerkleIpaMultiProof* = IpaMultiProof[8, EC_TwEdw[Fp[Banderwagon]], Fr[Banderwagon]]

  # The aliases may throw strange errors like:
  # - Error: invalid type: 'EthVerkleIpaProof' for var
  # - Error: cannot instantiate: 'src:type'
  # as of Nim v2.0.4

func serialize*(dst: var EthVerkleIpaProofBytes,
                src: IpaProof[8, EC_TwEdw[Fp[Banderwagon]], Fr[Banderwagon]]
                ): cttEthVerkleIpaStatus {.libPrefix: prefix_ipa, discardable.} =
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
                  src: EthVerkleIpaProofBytes): cttEthVerkleIpaStatus {.libPrefix: prefix_ipa, discardable.} =

  const fpb = sizeof(Fp[Banderwagon])
  const frb = sizeof(Fr[Banderwagon])

  let L = cast[ptr array[8, array[fpb, byte]]](src.unsafeAddr)
  let R = cast[ptr array[8, array[fpb, byte]]](src[8 * fpb].unsafeAddr)
  let a0 = cast[ptr array[frb, byte]](src[2 * 8 * fpb].unsafeAddr)

  for i in 0 ..< 8:
    checkReturn dst.L[i].deserialize_vartime(L[i])

  for i in 0 ..< 8:
    checkReturn dst.R[i].deserialize_vartime(R[i])

  checkReturn dst.a0.deserialize_fr(a0[], littleEndian)
  return cttEthVerkleIpa_Success

func serialize*(dst: var EthVerkleIpaMultiProofBytes,
                src: IpaMultiProof[8, EC_TwEdw[Fp[Banderwagon]], Fr[Banderwagon]]
                ): cttEthVerkleIpaStatus {.libPrefix: prefix_ipa, discardable.} =

  const frb = sizeof(Fr[Banderwagon])
  let D = cast[ptr array[frb, byte]](dst.addr)
  let g2Proof = cast[ptr EthVerkleIpaProofBytes](dst[frb].addr)

  D[].serialize(src.D)
  g2Proof[].serialize(src.g2_proof)
  return cttEthVerkleIpa_Success

func deserialize*(dst: var EthVerkleIpaMultiProof,
                  src: EthVerkleIpaMultiProofBytes
                  ): cttEthVerkleIpaStatus {.libPrefix: prefix_ipa.} =

  const frb = sizeof(Fr[Banderwagon])
  let D = cast[ptr array[frb, byte]](src.unsafeAddr)
  let g2Proof = cast[ptr EthVerkleIpaProofBytes](src[frb].unsafeAddr)

  checkReturn dst.D.deserialize_vartime(D[])
  return dst.g2_proof.deserialize(g2Proof[])

# Mapping EC to scalars
# ------------------------------------------------------------------------------------

# TODO: refactor, this shouldn't use curves_primitives but internal functions
import ./lowlevel_fields

func mapToBaseField*(dst: var Fp[Banderwagon],p: EC_TwEdw[Fp[Banderwagon]]) {.libPrefix: prefix_ipa, discardable.} =
  ## The mapping chosen for the Banderwagon Curve is x/y
  ##
  ## This function takes a Banderwagon element & then
  ## computes the x/y value and returns as an Fp element
  ##
  ## Spec : https://hackmd.io/@6iQDuIePQjyYBqDChYw_jg/BJBNcv9fq#Map-To-Field

  var invY: Fp[Banderwagon]
  invY.inv(p.y)             # invY = 1/Y
  dst.prod(p.x, invY)       # dst = (X) * (1/Y)

func mapToScalarField*(res: var Fr[Banderwagon], p: EC_TwEdw[Fp[Banderwagon]]): bool {.libPrefix: prefix_ipa, discardable.} =
  ## This function takes the x/y value from the above function as Fp element
  ## and convert that to bytes in Big Endian,
  ## and then load that to a Fr element
  ##
  ## Spec : https://hackmd.io/wliPP_RMT4emsucVuCqfHA?view#MapToFieldElement

  var baseField: Fp[Banderwagon]
  var baseFieldBytes: array[32, byte]

  baseField.mapToBaseField(p)   # compute the defined mapping

  let check1 = baseFieldBytes.marshalBE(baseField)  # Fp -> bytes
  let check2 = res.unmarshalBE(baseFieldBytes)      # bytes -> Fr

  return check1 and check2

func batchMapToScalarField*(
      res: var openArray[Fr[Banderwagon]],
      points: openArray[EC_TwEdw[Fp[Banderwagon]]]): bool {.libPrefix: prefix_ipa, discardable, noinline.} =
  ## This function performs the `mapToScalarField` operation
  ## on a batch of points
  ##
  ## The batch inversion used in this using
  ## the montogomenry trick, makes is faster than
  ## just iterating of over the array of points and
  ## converting the curve points to field elements
  ##
  ## Spec : https://hackmd.io/wliPP_RMT4emsucVuCqfHA?view#MapToFieldElement

  var check: bool = true
  check = check and (res.len == points.len)

  let N = res.len
  var ys = allocStackArray(Fp[Banderwagon], N)
  var ys_inv = allocStackArray(Fp[Banderwagon], N)


  for i in 0 ..< N:
    ys[i] = points[i].y

  ys_inv.batchInv_vartime(ys, N)

  for i in 0 ..< N:
    var mappedElement: Fp[Banderwagon]
    var bytes: array[32, byte]

    mappedElement.prod(points[i].x, ys_inv[i])
    check = bytes.marshalBE(mappedElement)
    check = check and res[i].unmarshalBE(bytes)

  return check

# Inner Product Argument
# ------------------------------------------------------------------------------------
# TODO: proper IPA wrapper for https://github.com/status-im/nim-eth-verkle
#
# For now we reexport
# - eth_verkle_ipa
# - sha256 for transcripts

export eth_verkle_ipa
export hashes
