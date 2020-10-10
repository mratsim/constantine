# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/curves,
  ../towers,
  ../io/io_towers

# Frobenius map - on extension fields
# -----------------------------------------------------------------

# c = (SNR^((p-1)/6)^coef).
# Then for frobenius(2): c  * conjugate(c)
# And for frobenius(3):  c² * conjugate(c)
const BLS12_377_FrobeniusMapCoefficients* = [
  # frobenius(1) -----------------------
  [Fp2[BLS12_377].fromHex(  # SNR^((p-1)/6)^0
    "0x1",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # SNR^((p-1)/6)^1
    "0x9a9975399c019633c1e30682567f915c8a45e0f94ebc8ec681bf34a3aa559db57668e558eb0188e938a9d1104f2031",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # SNR^((p-1)/6)^2
    "0x9b3af05dd14f6ec619aaf7d34594aabc5ed1347970dec00452217cc900000008508c00000000002",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # SNR^((p-1)/6)^3
    "0x1680a40796537cac0c534db1a79beb1400398f50ad1dec1bce649cf436b0f6299588459bff27d8e6e76d5ecf1391c63",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # SNR^((p-1)/6)^4
    "0x9b3af05dd14f6ec619aaf7d34594aabc5ed1347970dec00452217cc900000008508c00000000001",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # SNR^((p-1)/6)^5
    "0xcd70cb3fc936348d0351d498233f1fe379531411832232f6648a9a9fc0b9c4e3e21b7467077c05853e2c1be0e9fc32",
    "0x0"
  )],
  # frobenius(2) -----------------------
  [Fp2[BLS12_377].fromHex(  # norm(SNR)^((p-1)/6)^0
    "0x1",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # norm(SNR)^((p-1)/6)^1
    "0x9b3af05dd14f6ec619aaf7d34594aabc5ed1347970dec00452217cc900000008508c00000000002",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # norm(SNR)^((p-1)/6)^2
    "0x9b3af05dd14f6ec619aaf7d34594aabc5ed1347970dec00452217cc900000008508c00000000001",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # norm(SNR)^((p-1)/6)^3
    "0x1ae3a4617c510eac63b05c06ca1493b1a22d9f300f5138f1ef3622fba094800170b5d44300000008508c00000000000",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # norm(SNR)^((p-1)/6)^4
    "0x1ae3a4617c510eabc8756ba8f8c524eb8882a75cc9bc8e359064ee822fb5bffd1e945779fffffffffffffffffffffff",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # norm(SNR)^((p-1)/6)^5
    "0x1ae3a4617c510eabc8756ba8f8c524eb8882a75cc9bc8e359064ee822fb5bffd1e94577a00000000000000000000000",
    "0x0"
  )],
  # frobenius(3) -----------------------
  [Fp2[BLS12_377].fromHex(  # (SNR²)^((p-1)/6)^0
    "0x1",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # (SNR²)^((p-1)/6)^1
    "0x1680a40796537cac0c534db1a79beb1400398f50ad1dec1bce649cf436b0f6299588459bff27d8e6e76d5ecf1391c63",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # (SNR²)^((p-1)/6)^2
    "0x1ae3a4617c510eac63b05c06ca1493b1a22d9f300f5138f1ef3622fba094800170b5d44300000008508c00000000000",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # (SNR²)^((p-1)/6)^3
    "0x4630059e5fd9200575d0e552278a89da1f40fdf62334cd620d1860769e389d7db2d8ea700d82721691ea130ec6e39e",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # (SNR²)^((p-1)/6)^4
    "0x1",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # (SNR²)^((p-1)/6)^5
    "0x1680a40796537cac0c534db1a79beb1400398f50ad1dec1bce649cf436b0f6299588459bff27d8e6e76d5ecf1391c63",
    "0x0"
  )]]

# ψ (Psi) - Untwist-Frobenius-Twist Endomorphisms on twisted curves
# -----------------------------------------------------------------
# BLS12_377 is a D-Twist: psi1_coef1 = SNR^((p-1)/6)

# SNR^((p-1)/3)
const BLS12_377_FrobeniusPsi_psi1_coef2* = Fp2[BLS12_377].fromHex( 
  "0x9b3af05dd14f6ec619aaf7d34594aabc5ed1347970dec00452217cc900000008508c00000000002",
  "0x0"
)
# SNR^((p-1)/2)
const BLS12_377_FrobeniusPsi_psi1_coef3* = Fp2[BLS12_377].fromHex( 
  "0x1680a40796537cac0c534db1a79beb1400398f50ad1dec1bce649cf436b0f6299588459bff27d8e6e76d5ecf1391c63",
  "0x0"
)
# norm(SNR)^((p-1)/3)
const BLS12_377_FrobeniusPsi_psi2_coef2* = Fp2[BLS12_377].fromHex( 
  "0x9b3af05dd14f6ec619aaf7d34594aabc5ed1347970dec00452217cc900000008508c00000000001",
  "0x0"
)