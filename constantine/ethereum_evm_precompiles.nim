# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./platforms/abstractions,
  ./math/config/curves,
  ./math/[arithmetic, extension_fields],
  ./math/arithmetic/limbs_montgomery,
  ./math/ec_shortweierstrass,
  ./math/pairings/[pairings_bn, miller_loops, cyclotomic_subgroups],
  ./math/constants/zoo_subgroups,
  ./math/io/[io_bigints, io_fields]

# ############################################################
#
#                       Ethereum EVM precompiles
#
# ############################################################

# No exceptions for the EVM API
{.push raises: [].}

type
  CttEVMStatus* = enum
    cttEVM_Success
    cttEVM_IntLargerThanModulus
    cttEVM_PointNotOnCurve
    cttEVM_PointNotInSubgroup
    cttEVM_InvalidInputLength

func parseRawUint(
       dst: var Fp[BN254_Snarks],
       src: openarray[byte]): CttEVMStatus =
  ## Parse an unsigned integer from its canonical
  ## big-endian or little-endian unsigned representation
  ## And store it into a field element.
  ##
  ## Return false if the integer is larger than the field modulus.
  ## Returns true on success.
  var big {.noInit.}: BigInt[254]
  big.unmarshal(src, bigEndian)

  if not bool(big < Mod(BN254_Snarks)):
    return cttEVM_IntLargerThanModulus

  dst.fromBig(big)
  return cttEVM_Success

func fromRawCoords(
       dst: var ECP_ShortW_Prj[Fp[BN254_Snarks], G1],
       x, y: openarray[byte]): CttEVMStatus =

  # Deserialization
  # ----------------------
  # Encoding spec https://eips.ethereum.org/EIPS/eip-196

  let status_x = dst.x.parseRawUint(x)
  if status_x != cttEVM_Success:
    return status_x
  let status_y = dst.y.parseRawUint(y)
  if status_y != cttEVM_Success:
    return status_y

  # Handle point at infinity
  if dst.x.isZero().bool and dst.y.isZero().bool:
    dst.setInf()
    return cttEVM_Success

  # Otherwise regular point
  dst.z.setOne()

  # Deserialization checks
  # ----------------------

  # Point on curve
  if not bool(isOnCurve(dst.x, dst.y, G1)):
    return cttEVM_PointNotOnCurve

  # BN254_Snarks is a curve with cofactor 1,
  # so no subgroup checks are necessary

  return cttEVM_Success

func eth_evm_ecadd*(
      r: var array[64, byte], inputs: openarray[byte]): CttEVMStatus =
  ## Elliptic Curve addition on BN254_Snarks
  ## (also called alt_bn128 in Ethereum specs
  ##  and bn256 in Ethereum tests)
  ##
  ## Name: ECADD
  ##
  ## Inputs:
  ## - A G1 point P with coordinates (Px, Py)
  ## - A G1 point Q with coordinates (Qx, Qy)
  ##
  ## Each coordinate is a 32-bit bigEndian integer
  ## They are serialized concatenated in a byte array [Px, Py, Qx, Qy]
  ## If the length is less than 128 bytes, input is virtually padded with zeros.
  ## If the length is greater than 128 bytes, input is truncated to 128 bytes.
  ##
  ## Output
  ## - A G1 point R with coordinates (Px + Qx, Py + Qy)
  ## - Status code:
  ##   cttEVM_Success
  ##   cttEVM_IntLargerThanModulus
  ##   cttEVM_PointNotOnCurve
  ##
  ## Spec https://eips.ethereum.org/EIPS/eip-196

  # Auto-pad with zero
  var padded: array[128, byte]
  let lastIdx = min(inputs.len, 128) - 1
  padded[0 .. lastIdx] = inputs.toOpenArray(0, lastIdx)

  var P{.noInit.}, Q{.noInit.}, R{.noInit.}: ECP_ShortW_Prj[Fp[BN254_Snarks], G1]

  let statusP = P.fromRawCoords(
    x = padded.toOpenArray(0, 31),
    y = padded.toOpenArray(32, 63)
  )
  if statusP != cttEVM_Success:
    return statusP
  let statusQ = Q.fromRawCoords(
    x = padded.toOpenArray(64, 95),
    y = padded.toOpenArray(96, 127)
  )
  if statusQ != cttEVM_Success:
    return statusQ

  R.sum(P, Q)
  var aff{.noInit.}: ECP_ShortW_Aff[Fp[BN254_Snarks], G1]
  aff.affine(R)

  r.toOpenArray(0, 31).marshal(
    aff.x, bigEndian
  )
  r.toOpenArray(32, 63).marshal(
    aff.y, bigEndian
  )

func eth_evm_ecmul*(
      r: var array[64, byte], inputs: openarray[byte]): CttEVMStatus =
  ## Elliptic Curve multiplication on BN254_Snarks
  ## (also called alt_bn128 in Ethereum specs
  ##  and bn256 in Ethereum tests)
  ##
  ## Name: ECMUL
  ##
  ## Inputs:
  ## - A G1 point P with coordinates (Px, Py)
  ## - A scalar s in 0 ..< 2²⁵⁶
  ##
  ## Each coordinate is a 32-bit bigEndian integer
  ## They are serialized concatenated in a byte array [Px, Py, r]
  ## If the length is less than 96 bytes, input is virtually padded with zeros.
  ## If the length is greater than 96 bytes, input is truncated to 96 bytes.
  ##
  ## Output
  ## - A G1 point R = [s]P
  ## - Status code:
  ##   cttEVM_Success
  ##   cttEVM_IntLargerThanModulus
  ##   cttEVM_PointNotOnCurve
  ##
  ## Spec https://eips.ethereum.org/EIPS/eip-196

  # Auto-pad with zero
  var padded: array[128, byte]
  let lastIdx = min(inputs.len, 128) - 1
  padded[0 .. lastIdx] = inputs.toOpenArray(0, lastIdx)

  var P{.noInit.}: ECP_ShortW_Prj[Fp[BN254_Snarks], G1]

  let statusP = P.fromRawCoords(
    x = padded.toOpenArray(0, 31),
    y = padded.toOpenArray(32, 63)
  )
  if statusP != cttEVM_Success:
    return statusP

  var smod{.noInit.}: Fr[BN254_Snarks]
  var s{.noInit.}: BigInt[256]
  s.unmarshal(padded.toOpenArray(64,95), bigEndian)

  when true:
    # The spec allows s to be bigger than the curve order r and the field modulus p.
    # As, elliptic curve are a cyclic group mod r, we can reduce modulo r and get the same result.
    # This allows to use windowed endomorphism acceleration
    # which is 31.5% faster than plain windowed scalar multiplication
    # at the low cost of a modular reduction.

    var sprime{.noInit.}: typeof(smod.mres)
    # Due to mismatch between the BigInt[256] input and the rest being BigInt[254]
    # we use the low-level getMont instead of 'fromBig'
    getMont(smod.mres.limbs, s.limbs,
                Fr[BN254_Snarks].fieldMod().limbs,
                Fr[BN254_Snarks].getR2modP().limbs,
                Fr[BN254_Snarks].getNegInvModWord(),
                Fr[BN254_Snarks].getSpareBits())
    sprime = smod.toBig()
    P.scalarMul(sprime)
  else:
    P.scalarMul(s)

  var aff{.noInit.}: ECP_ShortW_Aff[Fp[BN254_Snarks], G1]
  aff.affine(P)

  r.toOpenArray(0, 31).marshal(
    aff.x, bigEndian
  )
  r.toOpenArray(32, 63).marshal(
    aff.y, bigEndian
  )

func subgroupCheck(P: ECP_ShortW_Aff[Fp2[BN254_Snarks], G2]): bool =
  ## A point may be on a curve but in case the curve has a cofactor != 1
  ## that point may not be in the correct cyclic subgroup.
  ## If we are on the subgroup of order r then [r]P = 0
  var Q{.noInit.}: ECP_ShortW_Prj[Fp2[BN254_Snarks], G2]
  Q.fromAffine(P)
  return bool(Q.isInSubgroup())

func fromRawCoords(
       dst: var ECP_ShortW_Aff[Fp[BN254_Snarks], G1],
       x, y: openarray[byte]): CttEVMStatus =

  # Deserialization
  # ----------------------
  # Encoding spec https://eips.ethereum.org/EIPS/eip-196

  let status_x = dst.x.parseRawUint(x)
  if status_x != cttEVM_Success:
    return status_x
  let status_y = dst.y.parseRawUint(y)
  if status_y != cttEVM_Success:
    return status_y

  # Handle point at infinity
  if dst.x.isZero().bool and dst.y.isZero().bool:
    return cttEVM_Success

  # Deserialization checks
  # ----------------------

  # Point on curve
  if not bool(isOnCurve(dst.x, dst.y, G1)):
    return cttEVM_PointNotOnCurve

  # BN254_Snarks is a curve with cofactor 1,
  # so no subgroup checks are necessary

  return cttEVM_Success

func fromRawCoords(
       dst: var ECP_ShortW_Aff[Fp2[BN254_Snarks], G2],
       x0, x1, y0, y1: openarray[byte]): CttEVMStatus =

  # Deserialization
  # ----------------------
  # Encoding spec https://eips.ethereum.org/EIPS/eip-196

  let status_x0 = dst.x.c0.parseRawUint(x0)
  if status_x0 != cttEVM_Success:
    return status_x0
  let status_x1 = dst.x.c1.parseRawUint(x1)
  if status_x1 != cttEVM_Success:
    return status_x1

  let status_y0 = dst.y.c0.parseRawUint(y0)
  if status_y0 != cttEVM_Success:
    return status_y0
  let status_y1 = dst.y.c1.parseRawUint(y1)
  if status_y1 != cttEVM_Success:
    return status_y1

  # Handle point at infinity
  if dst.x.isZero().bool and dst.y.isZero().bool:
    return cttEVM_Success

  # Deserialization checks
  # ----------------------

  # Point on curve
  if not bool(isOnCurve(dst.x, dst.y, G2)):
    return cttEVM_PointNotOnCurve

  if not subgroupCheck(dst):
    return cttEVM_PointNotInSubgroup

  return cttEVM_Success

func eth_evm_ecpairing*(
      r: var array[32, byte], inputs: openarray[byte]): CttEVMStatus =
  ## Elliptic Curve pairing on BN254_Snarks
  ## (also called alt_bn128 in Ethereum specs
  ##  and bn256 in Ethereum tests)
  ##
  ## Name: ECPAIRING
  ##
  ## Inputs:
  ## - An array of [(P0, Q0), (P1, Q1), ... (Pk, Qk)] points in (G1, G2)
  ##
  ## Output
  ## - 0 or 1 in uint256 BigEndian representation
  ## - Status code:
  ##   cttEVM_Success
  ##   cttEVM_IntLargerThanModulus
  ##   cttEVM_PointNotOnCurve
  ##   cttEVM_InvalidInputLength
  ##
  ## Spec https://eips.ethereum.org/EIPS/eip-197

  let N = inputs.len div 192
  if inputs.len mod 192 != 0:
    return cttEVM_InvalidInputLength

  if N == 0:
    # Spec: "Empty input is valid and results in returning one."
    zeroMem(r.addr, r.sizeof())
    r[r.len-1] = byte 1
    return

  var gt0{.noInit.}, gt1{.noInit.}: Fp12[BN254_Snarks]
  var P{.noInit.}: ECP_ShortW_Aff[Fp[BN254_Snarks], G1]
  var Q{.noInit.}: ECP_ShortW_Aff[Fp2[BN254_Snarks], G2]

  for i in 0 ..< N:
    let pos = i*192

    let statusP = P.fromRawCoords(
      x = inputs.toOpenArray(pos, pos+31),
      y = inputs.toOpenArray(pos+32, pos+63)
    )
    if statusP != cttEVM_Success:
      return statusP

    # Warning EIP197 encoding order:
    # Fp2 (a, b) <=> a*𝑖 + b instead of regular a+𝑖b
    let statusQ = Q.fromRawCoords(
      x1 = inputs.toOpenArray(pos+64, pos+95),
      x0 = inputs.toOpenArray(pos+96, pos+127),
      y1 = inputs.toOpenArray(pos+128, pos+159),
      y0 = inputs.toOpenArray(pos+160, pos+191)
    )
    if statusQ != cttEVM_Success:
      return statusQ

    gt1.millerLoopGenericBN(P, Q)
    if i == 0:
      gt0 = gt1
    else:
      gt0 *= gt1

  gt0.finalExpEasy()
  gt0.finalExpHard_BN()

  zeroMem(r.addr, r.sizeof())
  if gt0.isOne().bool:
    r[r.len-1] = byte 1
