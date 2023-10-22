# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./platforms/abstractions,
  ./serialization/io_limbs,
  ./math/config/curves,
  ./math/[arithmetic, extension_fields],
  ./math/arithmetic/limbs_montgomery,
  ./math/ec_shortweierstrass,
  ./math/pairings/[pairings_generic, miller_accumulators],
  ./math/constants/zoo_subgroups,
  ./math/io/[io_bigints, io_fields],
  ./math_arbitrary_precision/arithmetic/bigints_views

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
    cttEVM_InvalidInputSize
    cttEVM_InvalidOutputSize
    cttEVM_IntLargerThanModulus
    cttEVM_PointNotOnCurve
    cttEVM_PointNotInSubgroup

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
       dst: var ECP_ShortW_Jac[Fp[BN254_Snarks], G1],
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

func eth_evm_ecadd*(r: var openArray[byte], inputs: openarray[byte]): CttEVMStatus =
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
  ## - Output buffer MUST be of length 64 bytes
  ## - A G1 point R with coordinates (Px + Qx, Py + Qy)
  ## - Status code:
  ##   cttEVM_Success
  ##   cttEVM_IntLargerThanModulus
  ##   cttEVM_PointNotOnCurve
  ##
  ## Spec https://eips.ethereum.org/EIPS/eip-196

  if r.len != 64:
    return cttEVM_InvalidOutputSize

  # Auto-pad with zero
  var padded: array[128, byte]
  padded.rawCopy(0, inputs, 0, min(inputs.len, padded.len))

  var P{.noInit.}, Q{.noInit.}, R{.noInit.}: ECP_ShortW_Jac[Fp[BN254_Snarks], G1]

  let statusP = P.fromRawCoords(
    x = padded.toOpenArray(0, 31),
    y = padded.toOpenArray(32, 63))
  if statusP != cttEVM_Success:
    return statusP
  let statusQ = Q.fromRawCoords(
    x = padded.toOpenArray(64, 95),
    y = padded.toOpenArray(96, 127))
  if statusQ != cttEVM_Success:
    return statusQ

  R.sum_vartime(P, Q)
  var aff{.noInit.}: ECP_ShortW_Aff[Fp[BN254_Snarks], G1]
  aff.affine(R)

  r.toOpenArray(0, 31).marshal(aff.x, bigEndian)
  r.toOpenArray(32, 63).marshal(aff.y, bigEndian)
  return cttEVM_Success

func eth_evm_ecmul*(r: var openArray[byte], inputs: openarray[byte]): CttEVMStatus =
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
  ## - Output buffer MUST be of length 64 bytes
  ## - A G1 point R = [s]P
  ## - Status code:
  ##   cttEVM_Success
  ##   cttEVM_IntLargerThanModulus
  ##   cttEVM_PointNotOnCurve
  ##
  ## Spec https://eips.ethereum.org/EIPS/eip-196

  if r.len != 64:
    return cttEVM_InvalidOutputSize

  # Auto-pad with zero
  var padded: array[96, byte]
  padded.rawCopy(0, inputs, 0, min(inputs.len, padded.len))

  var P{.noInit.}: ECP_ShortW_Jac[Fp[BN254_Snarks], G1]

  let statusP = P.fromRawCoords(
    x = padded.toOpenArray(0, 31),
    y = padded.toOpenArray(32, 63))
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

    # Due to mismatch between the BigInt[256] input and the rest being BigInt[254]
    # we use the low-level getMont instead of 'fromBig'
    getMont(smod.mres.limbs, s.limbs,
                Fr[BN254_Snarks].fieldMod().limbs,
                Fr[BN254_Snarks].getR2modP().limbs,
                Fr[BN254_Snarks].getNegInvModWord(),
                Fr[BN254_Snarks].getSpareBits())
    P.scalarMul_vartime(smod.toBig())
  else:
    P.scalarMul_vartime(s)

  var aff{.noInit.}: ECP_ShortW_Aff[Fp[BN254_Snarks], G1]
  aff.affine(P)

  r.toOpenArray(0, 31).marshal(aff.x, bigEndian)
  r.toOpenArray(32, 63).marshal(aff.y, bigEndian)
  return cttEVM_Success

func subgroupCheck(P: ECP_ShortW_Aff[Fp2[BN254_Snarks], G2]): bool =
  ## A point may be on a curve but in case the curve has a cofactor != 1
  ## that point may not be in the correct cyclic subgroup.
  ## If we are on the subgroup of order r then [r]P = 0
  var Q{.noInit.}: ECP_ShortW_Jac[Fp2[BN254_Snarks], G2]
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
      r: var openArray[byte], inputs: openarray[byte]): CttEVMStatus =
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
  ## - Output buffer MUST be of length 32 bytes
  ## - 0 or 1 in uint256 BigEndian representation
  ## - Status code:
  ##   cttEVM_Success
  ##   cttEVM_IntLargerThanModulus
  ##   cttEVM_PointNotOnCurve
  ##   cttEVM_InvalidInputSize
  ##
  ## Spec https://eips.ethereum.org/EIPS/eip-197
  if r.len != 32:
    return cttEVM_InvalidOutputSize

  let N = inputs.len div 192
  if inputs.len mod 192 != 0:
    return cttEVM_InvalidInputSize

  if N == 0:
    # Spec: "Empty input is valid and results in returning one."
    zeroMem(r[0].addr, r.len-1)
    r[r.len-1] = byte 1
    return cttEVM_Success

  var P{.noInit.}: ECP_ShortW_Aff[Fp[BN254_Snarks], G1]
  var Q{.noInit.}: ECP_ShortW_Aff[Fp2[BN254_Snarks], G2]

  var acc {.noInit.}: MillerAccumulator[Fp[BN254_Snarks], Fp2[BN254_Snarks], Fp12[BN254_Snarks]]
  acc.init()
  var foundInfinity = false

  for i in 0 ..< N:
    let pos = i*192

    let statusP = P.fromRawCoords(
      x = inputs.toOpenArray(pos, pos+31),
      y = inputs.toOpenArray(pos+32, pos+63))

    if statusP != cttEVM_Success:
      return statusP

    # Warning EIP197 encoding order:
    # Fp2 (a, b) <=> a*𝑖 + b instead of regular a+𝑖b
    let statusQ = Q.fromRawCoords(
      x1 = inputs.toOpenArray(pos+64, pos+95),
      x0 = inputs.toOpenArray(pos+96, pos+127),
      y1 = inputs.toOpenArray(pos+128, pos+159),
      y0 = inputs.toOpenArray(pos+160, pos+191))

    if statusQ != cttEVM_Success:
      return statusQ

    let regular = acc.update(P, Q)
    if not regular:
      foundInfinity = true

  if foundInfinity: # pairing with infinity returns 1, hence no need to compute the following
    zeroMem(r[0].addr, r.len-1)
    r[r.len-1] = byte 1
    return cttEVM_Success

  var gt {.noinit.}: Fp12[BN254_Snarks]
  acc.finish(gt)
  gt.finalExp()

  zeroMem(r[0].addr, r.len)
  if gt.isOne().bool:
    r[r.len-1] = byte 1
  return cttEVM_Success

func eth_evm_modexp*(r: var openArray[byte], inputs: openArray[byte]): CttEVMStatus {.noInline, tags:[Alloca, Vartime], meter.} =
  ## Modular exponentiation
  ##
  ## Name: MODEXP
  ##
  ## Inputs:
  ## - `baseLen`:     32 bytes base integer length (in bytes)
  ## - `exponentLen`: 32 bytes exponent length (in bytes)
  ## - `modulusLen`:  32 bytes modulus length (in bytes)
  ## - `base`:        base integer (`baseLen` bytes)
  ## - `exponent`:    exponent (`exponentLen` bytes)
  ## - `modulus`:     modulus (`modulusLen` bytes)
  ##
  ## Output:
  ## - baseᵉˣᵖᵒⁿᵉⁿᵗ (mod modulus)
  ##   The result buffer size `r` MUST match the modulusLen
  ## - status code:
  ##   cttEVM_Success
  ##   cttEVM_InvalidInputSize if the lengths require more than 32-bit or 64-bit addressing (depending on hardware)
  ##   cttEVM_InvalidOutputSize
  ##
  ## Spec
  ##   Yellow Paper Appendix E
  ##   EIP-198 - https://github.com/ethereum/EIPs/blob/master/EIPS/eip-198.md
  ##
  ## Hardware considerations:
  ##   This procedure stack allocates a table of (16+1)*modulusLen and many stack temporaries.
  ##   Make sure to validate gas costs and reject large inputs to bound stack usage.

  # Input parse sizes
  # -----------------

  # Auto-pad with zero
  var paddedLengths: array[96, byte]
  paddedLengths.rawCopy(0, inputs, 0, min(inputs.len, paddedLengths.len))

  let
    bL = BigInt[256].unmarshal(paddedLengths.toOpenArray(0, 31), bigEndian)
    eL = BigInt[256].unmarshal(paddedLengths.toOpenArray(32, 63), bigEndian)
    mL = BigInt[256].unmarshal(paddedLengths.toOpenArray(64, 95), bigEndian)

    maxSize = BigInt[256].fromUint(high(uint)) # A CPU can only address up to high(uint)

  # Input validation
  # -----------------
  if bool(bL > maxSize):
    return cttEVM_InvalidInputSize
  if bool(eL > maxSize):
    return cttEVM_InvalidInputSize
  if bool(mL > maxSize):
    return cttEVM_InvalidInputSize

  let
    baseByteLen = cast[int](bL.limbs[0])
    exponentByteLen = cast[int](eL.limbs[0])
    modulusByteLen = cast[int](mL.limbs[0])

    baseWordLen = baseByteLen.ceilDiv_vartime(WordBitWidth div 8)
    modulusWordLen = modulusByteLen.ceilDiv_vartime(WordBitWidth div 8)

  if r.len != modulusByteLen:
    return cttEVM_InvalidOutputSize

  # Special cases
  # ----------------------
  if paddedLengths.len + baseByteLen + exponentByteLen >= inputs.len:
    # Modulus value is in the infinitely right padded zeros input, hence is zero.
    r.setZero()
    return cttEVM_Success

  if modulusByteLen == 0:
    r.setZero()
    return cttEVM_Success

  if exponentByteLen == 0:
    r.setZero()
    r[r.len-1] = byte 1 # 0^0 = 1 and x^0 = 1
    return cttEVM_Success

  if baseByteLen == 0:
    r.setZero()
    return cttEVM_Success

  # Input deserialization
  # ---------------------

  # Inclusive stops
  # Due to special-case checks and early returns,
  # only the modulus can require right-padding with zeros here
  # inputs[expStop] cannot buffer overflow
  let baseStart = paddedLengths.len
  let baseStop  = baseStart+baseByteLen-1
  let expStart  = baseStop+1
  let expStop   = expStart+exponentByteLen-1
  let modStart  = expStop+1
  let modStop   = modStart+modulusByteLen-1

  # We assume that gas checks prevent numbers too big for stack allocation.
  var baseBuf = allocStackArray(SecretWord, baseWordLen)
  var modulusBuf = allocStackArray(SecretWord, modulusWordLen)
  var outputBuf = allocStackArray(SecretWord, modulusWordLen)

  template base(): untyped = baseBuf.toOpenArray(0, baseWordLen-1)
  template exponent(): untyped = inputs.toOpenArray(expStart, expStop)
  template modulus(): untyped = modulusBuf.toOpenArray(0, modulusWordLen-1)
  template output(): untyped = outputBuf.toOpenArray(0, modulusWordLen-1)

  # Base deserialization
  base.toOpenArray(0, baseWordLen-1).unmarshal(inputs.toOpenArray(baseStart, baseStop), WordBitWidth, bigEndian)

  # Modulus deserialization
  let realLen = paddedLengths.len + baseByteLen + exponentByteLen + modulusByteLen
  let overflowLen = realLen - inputs.len
  if overflowLen > 0:
    let physLen = inputs.len-modStart # Length of data physically present (i.e. excluding padded zeros)
    var paddedModBuf = allocStackArray(byte, modulusByteLen)
    template paddedMod(): untyped = paddedModBuf.toOpenArray(0, modulusByteLen-1)

    paddedMod.rawCopy(0, inputs, modStart, physLen)
    zeroMem(paddedMod[physLen].addr, overflowLen)
    modulus.unmarshal(paddedMod, WordBitWidth, bigEndian)
  else:
    modulus.unmarshal(inputs.toOpenArray(modStart, modStop), WordBitWidth, bigEndian)

  # Computation
  # ---------------------
  output.powMod_vartime(base, exponent, modulus, window = 4)

  # Output serialization
  # ---------------------
  r.marshal(output, WordBitWidth, bigEndian)
  return cttEVM_Success