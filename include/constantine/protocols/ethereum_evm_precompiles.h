/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
#ifndef __CTT_H_ETHEREUM_EVM_PRECOMPILES__
#define __CTT_H_ETHEREUM_EVM_PRECOMPILES__

#include "constantine/core/datatypes.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum __attribute__((__packed__)) {
    cttEVM_Success,
    cttEVM_InvalidInputSize,
    cttEVM_InvalidOutputSize,
    cttEVM_IntLargerThanModulus,
    cttEVM_PointNotOnCurve,
    cttEVM_PointNotInSubgroup,
} ctt_evm_status;

static const char* ctt_evm_status_to_string(ctt_evm_status status) {
  static const char* const statuses[] = {
      "cttEVM_Success",
      "cttEVM_InvalidInputSize",
      "cttEVM_InvalidOutputSize",
      "cttEVM_IntLargerThanModulus",
      "cttEVM_PointNotOnCurve",
      "cttEVM_PointNotInSubgroup",
  };
  size_t length = sizeof statuses / sizeof *statuses;
  if (0 <= status && status < length) {
    return statuses[status];
  }
  return "cttEVM_InvalidStatusCode";
}

/**
 *  SHA256
 *
 *  Inputs:
 *  - r: array with 32 bytes of storage for the result
 *  - r_len: length of `r`. Must be 32
 *  - inputs: Message to hash
 *  - inputs_len: length of the inputs array
 *
 *  Output:
 *  - 32-byte digest
 *  - status code:
 *    cttEVM_Success
 *    cttEVM_InvalidOutputSize
 */
ctt_evm_status ctt_eth_evm_sha256(
    byte* r, size_t r_len,
    const byte* inputs, size_t inputs_len
    ) __attribute__((warn_unused_result));

/**
 *  Helper for `eth_evm_modexp`. Returns the size required to be allocated based on the
 *  given input. Call this function first, then allocate space for the result buffer
 *  in the call to `eth_evm_modexp` based on this function's result.
 *
 *  The size depends on the `modulusLen`, which is the third 32 bytes,
 *  `inputs == [baseLen { 32 bytes }, exponentLen { 32 bytes }, modulusLen { 32 bytes }, ... ]`
 *  in `inputs`.
 *
 *  The associated modulus length in bytes is the size required by the
 *  result to `eth_evm_modexp`.
 */
ctt_evm_status ctt_eth_evm_modexp_result_size(
    uint64_t* size,
    const byte* inputs, size_t inputs_len
) __attribute__((warn_unused_result));


/**
 *  Modular exponentiation
 *
 *  Name: MODEXP
 *
 *  Inputs:
 *  - `baseLen`:     32 bytes base integer length (in bytes)
 *  - `exponentLen`: 32 bytes exponent length (in bytes)
 *  - `modulusLen`:  32 bytes modulus length (in bytes)
 *  - `base`:        base integer (`baseLen` bytes)
 *  - `exponent`:    exponent (`exponentLen` bytes)
 *  - `modulus`:     modulus (`modulusLen` bytes)
 *
 *  Output:
 *  - baseᵉˣᵖᵒⁿᵉⁿᵗ (mod modulus)
 *    The result buffer size `r` MUST match the modulusLen
 *  - status code:
 *    cttEVM_Success
 *    cttEVM_InvalidInputSize if the lengths require more than 32-bit or 64-bit addressing (depending on hardware)
 *    cttEVM_InvalidOutputSize
 *
 *  Spec
 *    Yellow Paper Appendix E
 *    EIP-198 - https://github.com/ethereum/EIPs/blob/master/EIPS/eip-198.md
 *
 *  Hardware considerations:
 *    This procedure stack allocates a table of (16+1)*modulusLen and many stack temporaries.
 *    Make sure to validate gas costs and reject large inputs to bound stack usage.
 */
ctt_evm_status ctt_eth_evm_modexp(
    byte* r, size_t r_len,
    const byte* inputs, size_t inputs_len
) __attribute__((warn_unused_result));


/**
  *  Elliptic Curve addition on BN254_Snarks
  *  (also called alt_bn128 in Ethereum specs
  *   and bn256 in Ethereum tests)
  *
  *  Name: ECADD
  *
  *  Inputs:
  *  - A G1 point P with coordinates (Px, Py)
  *  - A G1 point Q with coordinates (Qx, Qy)
  *
  *  Each coordinate is a 32-byte bigEndian integer
  *  They are serialized concatenated in a byte array [Px, Py, Qx, Qy]
  *  If the length is less than 128 bytes, input is virtually padded with zeros.
  *  If the length is greater than 128 bytes, input is truncated to 128 bytes.
  *
  *  Output
  *  - Output buffer MUST be of length 64 bytes
  *  - A G1 point R = P+Q with coordinates (Rx, Ry)
  *  - Status code:
  *    cttEVM_Success
  *    cttEVM_InvalidOutputSize
  *    cttEVM_IntLargerThanModulus
  *    cttEVM_PointNotOnCurve
  *
  *  Spec https://eips.ethereum.org/EIPS/eip-196
  */
ctt_evm_status ctt_eth_evm_bn254_g1add(
    byte* r, size_t r_len,
    const byte* inputs, size_t inputs_len
) __attribute__((warn_unused_result));

/**
  *  Elliptic Curve multiplication on BN254_Snarks
  *  (also called alt_bn128 in Ethereum specs
  *   and bn256 in Ethereum tests)
  *
  *  Name: ECMUL
  *
  *  Inputs:
  *  - A G1 point P with coordinates (Px, Py)
  *  - A scalar s in 0 ..< 2²⁵⁶
  *
  *  Each coordinate is a 32-byte bigEndian integer
  *  r is a 32-byte bigEndian integer
  *  They are serialized concatenated in a byte array [Px, Py, r]
  *  If the length is less than 96 bytes, input is virtually padded with zeros.
  *  If the length is greater than 96 bytes, input is truncated to 96 bytes.
  *
  *  Output
  *  - Output buffer MUST be of length 64 bytes
  *  - A G1 point R = [s]P
  *  - Status codes:
  *    cttEVM_Success
  *    cttEVM_IntLargerThanModulus
  *    cttEVM_PointNotOnCurve
  *
  *  Spec https://eips.ethereum.org/EIPS/eip-196
  */
ctt_evm_status ctt_eth_evm_bn254_g1mul(
    byte* r, size_t r_len,
    const byte* inputs, size_t inputs_len
) __attribute__((warn_unused_result));

/**
  *  Elliptic Curve pairing check on BN254_Snarks
  *  (also called alt_bn128 in Ethereum specs
  *   and bn256 in Ethereum tests)
  *
  *  Name: ECPAIRING / Pairing check
  *
  *  Inputs:
  *  - An array of [(P0, Q0), (P1, Q1), ... (Pk, Qk)] points in (G1, G2)
  *
  *  Output
  *  - Output buffer MUST be of length 32 bytes
  *  - 0 or 1 in uint256 BigEndian representation
  *  - Status codes:
  *    cttEVM_Success
  *    cttEVM_InvalidInputSize
  *    cttEVM_InvalidOutputSize
  *    cttEVM_IntLargerThanModulus
  *    cttEVM_PointNotOnCurve
  *    cttEVM_PointNotInSubgroup
  *
  *  Specs https://eips.ethereum.org/EIPS/eip-197
  *        https://eips.ethereum.org/EIPS/eip-1108
  */
ctt_evm_status ctt_eth_evm_bn254_ecpairingcheck(
    byte* r, size_t r_len,
    const byte* inputs, size_t inputs_len
) __attribute__((warn_unused_result));

/**
  *  Elliptic Curve addition on BLS12-381 G1
  *
  *  Name: BLS12_G1ADD
  *
  *  Inputs:
  *  - A G1 point P with coordinates (Px, Py)
  *  - A G1 point Q with coordinates (Qx, Qy)
  *  - Input buffer MUST be 256 bytes
  *
  *  Each coordinate is a 64-byte bigEndian integer
  *  They are serialized concatenated in a byte array [Px, Py, Qx, Qy]
  *
  *  Inputs are NOT subgroup-checked.
  *
  *  Output
  *  - Output buffer MUST be of length 128 bytes
  *  - A G1 point R=P+Q with coordinates (Rx, Ry)
  *  - Status codes:
  *    cttEVM_Success
  *    cttEVM_InvalidInputSize
  *    cttEVM_InvalidOutputSize
  *    cttEVM_IntLargerThanModulus
  *    cttEVM_PointNotOnCurve
  *
  *  Spec https://eips.ethereum.org/EIPS/eip-2537
  */
ctt_evm_status ctt_eth_evm_bls12381_g1add(
    byte* r, size_t r_len,
    const byte* inputs, size_t inputs_len
) __attribute__((warn_unused_result));

/**
  *  Elliptic Curve addition on BLS12-381 G2
  *
  *  Name: BLS12_G2ADD
  *
  *  Inputs:
  *  - A G2 point P with coordinates (Px, Py)
  *  - A G2 point Q with coordinates (Qx, Qy)
  *  - Input buffer MUST be 512 bytes
  *
  *  Each coordinate is a 128-byte bigEndian integer pair (a+𝑖b) with 𝑖 = √-1
  *  They are serialized concatenated in a byte array [Px, Py, Qx, Qy]
  *
  *  Inputs are NOT subgroup-checked.
  *
  *  Output
  *  - Output buffer MUST be of length 256 bytes
  *  - A G2 point R=P+Q with coordinates (Rx, Ry)
  *  - Status codes:
  *    cttEVM_Success
  *    cttEVM_InvalidInputSize
  *    cttEVM_InvalidOutputSize
  *    cttEVM_IntLargerThanModulus
  *    cttEVM_PointNotOnCurve
  *
  *  Spec https://eips.ethereum.org/EIPS/eip-2537
  */
ctt_evm_status ctt_eth_evm_bls12381_g2add(
    byte* r, size_t r_len,
    const byte* inputs, size_t inputs_len
) __attribute__((warn_unused_result));

/**
  *  Elliptic Curve scalar multiplication on BLS12-381 G1
  *
  *  Name: BLS12_G1MUL
  *
  *  Inputs:
  *  - A G1 point P with coordinates (Px, Py)
  *  - A scalar s in 0 ..< 2²⁵⁶
  *  - Input buffer MUST be 160 bytes
  *
  *  Each coordinate is a 64-byte bigEndian integer
  *  s is a 32-byte bigEndian integer
  *  They are serialized concatenated in a byte array [Px, Py, s]
  *
  *  Output
  *  - Output buffer MUST be of length 128 bytes
  *  - A G1 point R=P+Q with coordinates (Rx, Ry)
  *  - Status code:
  *    cttEVM_Success
  *    cttEVM_InvalidInputSize
  *    cttEVM_InvalidOutputSize
  *    cttEVM_IntLargerThanModulus
  *    cttEVM_PointNotOnCurve
  *
  *  Spec https://eips.ethereum.org/EIPS/eip-2537
  */
ctt_evm_status ctt_eth_evm_bls12381_g1mul(
    byte* r, size_t r_len,
    const byte* inputs, size_t inputs_len
) __attribute__((warn_unused_result));

/**
     *  Elliptic Curve scalar multiplication on BLS12-381 G2
  *
  *  Name: BLS12_G2MUL
  *
  *  Inputs:
  *  - A G2 point P with coordinates (Px, Py)
  *  - A scalar s in 0 ..< 2²⁵⁶
  *  - Input buffer MUST be 288 bytes
  *
  *  Each coordinate is a 128-byte bigEndian integer pair (a+𝑖b) with 𝑖 = √-1
  *  s is a 32-byte bigEndian integer
  *  They are serialized concatenated in a byte array [Px, Py, s]
  *
  *  Output
  *  - Output buffer MUST be of length 256 bytes
  *  - A G2 point R=P+Q with coordinates (Rx, Ry)
  *  - Status code:
  *    cttEVM_Success
  *    cttEVM_InvalidInputSize
  *    cttEVM_InvalidOutputSize
  *    cttEVM_IntLargerThanModulus
  *    cttEVM_PointNotOnCurve
  *
  *  Spec https://eips.ethereum.org/EIPS/eip-2537
  */
ctt_evm_status ctt_eth_evm_bls12381_g2mul(
    byte* r, size_t r_len,
    const byte* inputs, size_t inputs_len
) __attribute__((warn_unused_result));

/**
  *  Elliptic Curve addition on BLS12-381 G1
  *
  *  Name: BLS12_G1MSM
  *
  *  Inputs:
  *  - A sequence of pairs of points
  *    - G1 points Pᵢ with coordinates (Pᵢx, Pᵢy)
  *    - scalar sᵢ in 0 ..< 2²⁵⁶
  *  - Each pair MUST be 160 bytes
  *  - The total length MUST be a multiple of 160 bytes
  *
  *  Each coordinate is a 64-byte bigEndian integer
  *  s is a 32-byte bigEndian integer
  *  They are serialized concatenated in a byte array [(P₀x, P₀y, r₀), (P₁x, P₁y, r₁) ..., (Pₙx, Pₙy, rₙ)]
  *
  *  Output
  *  - Output buffer MUST be of length 128 bytes
  *  - A G1 point R=P+Q with coordinates (Rx, Ry)
  *  - Status code:
  *    cttEVM_Success
  *    cttEVM_InvalidInputSize
  *    cttEVM_InvalidOutputSize
  *    cttEVM_IntLargerThanModulus
  *    cttEVM_PointNotOnCurve
  *
  *  Spec https://eips.ethereum.org/EIPS/eip-2537
  */
ctt_evm_status ctt_eth_evm_bls12381_g1msm(
    byte* r, size_t r_len,
    const byte* inputs, size_t inputs_len
) __attribute__((warn_unused_result));

/**
  *  Elliptic Curve addition on BLS12-381 G2
  *
  *  Name: BLS12_G2MSM
  *
  *  Inputs:
  *  - A sequence of pairs of points
  *    - G2 points Pᵢ with coordinates (Pᵢx, Pᵢy)
  *    - scalar sᵢ in 0 ..< 2²⁵⁶
  *  - Each pair MUST be 288 bytes
  *  - The total length MUST be a multiple of 288 bytes
  *
  *  Each coordinate is a 128-byte bigEndian integer pair (a+𝑖b) with 𝑖 = √-1
  *  s is a 32-byte bigEndian integer
  *  They are serialized concatenated in a byte array [(P₀x, P₀y, r₀), (P₁x, P₁y, r₁) ..., (Pₙx, Pₙy, rₙ)]
  *
  *  Output
  *  - Output buffer MUST be of length 512 bytes
  *  - A G2 point R=P+Q with coordinates (Rx, Ry)
  *  - Status code:
  *    cttEVM_Success
  *    cttEVM_InvalidInputSize
  *    cttEVM_InvalidOutputSize
  *    cttEVM_IntLargerThanModulus
  *    cttEVM_PointNotOnCurve
  *
  *  Spec https://eips.ethereum.org/EIPS/eip-2537
  */
ctt_evm_status ctt_eth_evm_bls12381_g2msm(
    byte* r, size_t r_len,
    const byte* inputs, size_t inputs_len
) __attribute__((warn_unused_result));

/**
  *  Elliptic curve pairing check on BLS12-381
  *
  *  Name: BLS12_PAIRINGCHECK
  *
  *  Inputs:
  *  - An array of [(P0, Q0), (P1, Q1), ... (Pk, Qk)] points in (G1, G2)
  *
  *  Output
  *  - Output buffer MUST be of length 32 bytes
  *  - 0 or 1 in uint256 BigEndian representation
  *  - Status codes:
  *    cttEVM_Success
  *    cttEVM_InvalidInputSize
  *    cttEVM_InvalidOutputSize
  *    cttEVM_IntLargerThanModulus
  *    cttEVM_PointNotOnCurve
  *    cttEVM_PointNotInSubgroup
  *
  *  specs https://eips.ethereum.org/EIPS/eip-2537
  */
ctt_evm_status ctt_eth_evm_bls12381_pairingcheck(
    byte* r, size_t r_len,
    const byte* inputs, size_t inputs_len
) __attribute__((warn_unused_result));

/**
  *  Map a field element to G1
  *
  *  Name: BLS12_MAP_FP_TO_G1
  *
  *  Input:
  *  - A field element in 0 ..< p, p the prime field of BLS12-381
  *  - The length MUST be a 48-byte (381-bit) number serialized in 64-byte big-endian number
  *
  *  Output
  *  - Output buffer MUST be of length 64 bytes
  *  - A G1 point R with coordinates (Rx, Ry)
  *  - Status code:
  *    cttEVM_Success
  *    cttEVM_InvalidInputSize
  *    cttEVM_InvalidOutputSize
  *    cttEVM_IntLargerThanModulus
  *
  *  Spec https://eips.ethereum.org/EIPS/eip-2537
  */
ctt_evm_status ctt_eth_evm_bls12381_map_fp_to_g1(
    byte* r, size_t r_len,
    const byte* inputs, size_t inputs_len
) __attribute__((warn_unused_result));

/**
  *  Map an Fp2 extension field element to G2
  *
  *  Name: BLS12_MAP_FP2_TO_G2
  *
  *  Input:
  *  - An extension field element in (0, 0) ..< (p, p), p the prime field of BLS12-381
  *  - The length MUST be a tuple of 48-byte (381-bit) number serialized in tuple of 64-byte big-endian numbers
  *
  *  Output
  *  - Output buffer MUST be of length 128 bytes
  *  - A G2 point R with coordinates (Rx, Ry)
  *  - Status code:
  *    cttEVM_Success
  *    cttEVM_InvalidInputSize
  *    cttEVM_InvalidOutputSize
  *    cttEVM_IntLargerThanModulus
  *
  *  Spec https://eips.ethereum.org/EIPS/eip-2537
  */
ctt_evm_status ctt_eth_evm_bls12381_map_fp2_to_g2(
    byte* r, size_t r_len,
    const byte* inputs, size_t inputs_len
) __attribute__((warn_unused_result));


#ifdef __cplusplus
}
#endif

#endif // __CTT_H_ETHEREUM_EVM_PRECOMPILES__
