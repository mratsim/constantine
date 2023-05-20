# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./hashes,
  ./kdf/kdf_hkdf,
  ./math/config/[curves, type_ff],
  ./math/arithmetic/[bigints, limbs_montgomery],
  ./math/io/io_bigints,
  ./platforms/primitives,
  ./serialization/endians

# EIP2333: BLS12-381 Key Generation
# ------------------------------------------------------------
#
# https://eips.ethereum.org/EIPS/eip-2333

{.push raises: [], checks: off.} # No exceptions

type SecretKey = matchingOrderBigInt(BLS12_381)

func hkdf_mod_r(secretKey: var SecretKey, ikm: openArray[byte], key_info: openArray[byte]) =
  ## Ethereum 2 EIP-2333, extracts this from the BLS signature schemes
  # 1. salt = "BLS-SIG-KEYGEN-SALT-"
  # 2. SK = 0
  # 3. while SK == 0:
  # 4.     salt = H(salt)
  # 5.     PRK = HKDF-Extract(salt, IKM || I2OSP(0, 1))
  # 6.     OKM = HKDF-Expand(PRK, key_info || I2OSP(L, 2), L)
  # 7.     SK = OS2IP(OKM) mod r
  # 8. return SK
  const salt0 = "BLS-SIG-KEYGEN-SALT-"
  var ctx{.noInit.}: HKDF[sha256]
  var prk{.noInit.}: array[sha256.digestSize(), byte]

  var salt {.noInit.}: array[sha256.digestSize(), byte]
  sha256.hash(salt, salt0)

  while true:
    # 5. PRK = HKDF-Extract("BLS-SIG-KEYGEN-SALT-", IKM || I2OSP(0, 1))
    ctx.hkdf_extract_init(salt, ikm)
    ctx.hkdf_extract_append_to_IKM([byte 0])
    ctx.hkdf_extract_finish(prk)
    # curve order r = 52435875175126190479447740508185965837690552500527637822603658699938581184513
    # const L = ceil((1.5 * ceil(log2(r))) / 8) = 48
    # https://www.wolframalpha.com/input/?i=ceil%28%281.5+*+ceil%28log2%2852435875175126190479447740508185965837690552500527637822603658699938581184513%29%29%29+%2F+8%29
    # 6. OKM = HKDF-Expand(PRK, key_info || I2OSP(L, 2), L)
    const L = 48
    var okm{.noInit.}: array[L, byte]
    const L_octetstring = L.uint16.toBytes(bigEndian)
    ctx.hkdfExpand(okm, prk, key_info, append = L_octetstring, clearMem = true)
    #  7. x = OS2IP(OKM) mod r
    #  We reduce mod r via Montgomery reduction, instead of bigint division
    #  as constant-time division works bits by bits (384 bits) while
    #  Montgomery reduction works word by word, quadratically so 6*6 = 36 on 64-bit CPUs.
    #  With R ≡ (2^WordBitWidth)^numWords (mod M)
    #  redc2xMont(a) computes a/R
    #  mulMont(a, b) computes a.b.R⁻¹
    var seckeyDbl{.noInit.}: BigInt[2 * BLS12_381.getCurveOrderBitWidth()]
    seckeyDbl.unmarshal(okm, bigEndian)
    # secretKey.reduce(seckeyDbl, BLS12_381.getCurveOrder())
    secretKey.limbs.redc2xMont(seckeyDbl.limbs,                                      # seckey/R
                               BLS12_381.getCurveOrder().limbs, Fr[BLS12_381].getNegInvModWord(),
                               Fr[BLS12_381].getSpareBits())
    secretKey.limbs.mulMont(secretKey.limbs, Fr[BLS12_381].getR2modP().limbs,        # (seckey/R) * R² * R⁻¹ = seckey
                            BLS12_381.getCurveOrder().limbs, Fr[BLS12_381].getNegInvModWord(),
                            Fr[BLS12_381].getSpareBits())

    if bool secretKey.isZero():
      # Chance of 2⁻²⁵⁶ to happen
      sha256.hash(salt, salt)
    else:
      return

iterator ikm_to_lamport_SK(
           lamportSecretKeyChunk: var array[32, byte],
           ikm: array[32, byte], salt: array[4, byte]): int =
  ## Generate a Lamport secret key
  ## This uses an iterator to stream HKDF
  ## instead of allocating 255*32 bytes ~= 8KB
  var ctx{.noInit.}: HKDF[sha256]
  var prk{.noInit.}: array[32, byte]

  # 0. PRK = HKDF-Extract(salt, IKM)
  ctx.hkdfExtract(prk, salt, ikm)

  # 1. OKM = HKDF-Expand(PRK, "" , L)
  #    with L = K * 255 and K = 32 (sha256 output)
  for i in ctx.hkdfExpandChunk(
            lamportSecretKeyChunk,
            prk, default(array[0, byte]), default(array[0, byte])):
    yield i

  ctx.clear()

func parent_SK_to_lamport_PK(
       lamportPublicKey: var array[32, byte],
       parentSecretKey: SecretKey,
       index: uint32) =
  ## Derives the index'th child's lamport PublicKey
  ## from the parent SecretKey

  # 0. salt = I2OSP(index, 4)
  let salt{.noInit.} = index.toBytes(bigEndian)

  # 1. IKM = I2OSP(parent_SK, 32)
  var ikm {.noinit.}: array[32, byte]
  ikm.marshal(parentSecretKey, bigEndian)

  # Reorganized the spec to save on stack allocations
  # by reusing buffers and using streaming HKDF

  # 5. lamport_PK = ""
  var ctx{.noInit.}: sha256
  ctx.init()

  var tmp{.noInit.}, chunk{.noInit.}: array[32, byte]

  # 2. lamport_0 = IKM_to_lamport_SK(IKM, salt)
  # 6. for i = 1, .., 255 (inclusive)
  #        lamport_PK = lamport_PK | SHA256(lamport_0[i])
  for i in ikm_to_lamport_SK(chunk, ikm, salt):
    sha256.hash(tmp, chunk)
    ctx.update(tmp)
    if i == 254:
      # We iterate from 0
      break

  # 3. not_IKM = flip_bits(parent_SK)
  for i in 0 ..< 32:
    ikm[i] = not ikm[i]

  # 4. lamport_1 = IKM_to_lamport_SK(not_IKM, salt)
  # 7. for i = 1, .., 255 (inclusive)
  #        lamport_PK = lamport_PK | SHA256(lamport_1[i])
  for i in ikm_to_lamport_SK(chunk, ikm, salt):
    sha256.hash(tmp, chunk)
    ctx.update(tmp)
    if i == 254:
      # We iterate from 0
      break

  # 8. compressed_lamport_PK = SHA256(lamport_PK)
  # 9. return compressed_lamport_PK
  ctx.finish(lamportPublicKey)

func derive_child_secretKey*(
        childSecretKey: var SecretKey,
        parentSecretKey: SecretKey,
        index: uint32): bool =
  ## EIP2333 Child Key derivation function
  var compressed_lamport_PK{.noInit.}: array[32, byte]
  # 0. compressed_lamport_PK = parent_SK_to_lamport_PK(parent_SK, index)
  parent_SK_to_lamport_PK(
    compressed_lamport_PK,
    parentSecretKey,
    index)
  childSecretKey.hkdf_mod_r(compressed_lamport_PK, key_info = default(array[0, byte]))
  compressed_lamport_PK.setZero()
  return true

func derive_master_secretKey*(
        masterSecretKey: var SecretKey,
        ikm: openArray[byte]): bool =
  ## EIP2333 Master key derivation
  ## The input keying material SHOULD be cleared after use
  ## to prevent leakage.
  if ikm.len < 32:
    return false

  masterSecretKey.hkdf_mod_r(ikm, key_info = default(array[0, byte]))
  return true