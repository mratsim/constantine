# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/[curves, type_fp],
  ../io/io_fields

# Frobenius map - on extension fields
# -----------------------------------------------------------------

# c = (SNR^((p-1)/3)^coef).
# Then for frobenius(2): c  * conjugate(c)
# And for frobenius(3):  c² * conjugate(c)
const BW6_761_FrobeniusMapCoefficients* = [
  # frobenius(1) -----------------------
  [Fp[BW6_761].fromHex(  # SNR^((p-1)/3)^0
    "0x1"),
  Fp[BW6_761].fromHex(  # SNR^((p-1)/3)^1
    "0xcfca638f1500e327035cdf02acb2744d06e68545f7e64c256ab7ae14297a1a823132b971cdefc65870636cb60d217ff87fa59308c07a8fab8579e02ed3cddca5b093ed79b1c57b5fe3f89c11811c1e214983de300000535e7bc00000000060"),
  Fp[BW6_761].fromHex(  # SNR^((p-1)/3)^2
    "0x531dc16c6ecd27aa846c61024e4cca6c1f31e53bd9603c2d17be416c5e4426ee4a737f73b6f952ab5e57926fa701848e0a235a0a398300c65759fc45183151f2f082d4dcb5e37cb6290012d96f8819c547ba8a4000002f962140000000002a"),
  Fp[BW6_761].fromHex(  # SNR^((p-1)/3)^3
    "0x1"),
  Fp[BW6_761].fromHex(  # SNR^((p-1)/3)^4
    "0xcfca638f1500e327035cdf02acb2744d06e68545f7e64c256ab7ae14297a1a823132b971cdefc65870636cb60d217ff87fa59308c07a8fab8579e02ed3cddca5b093ed79b1c57b5fe3f89c11811c1e214983de300000535e7bc00000000060"),
  Fp[BW6_761].fromHex(  # SNR^((p-1)/3)^5
    "0x531dc16c6ecd27aa846c61024e4cca6c1f31e53bd9603c2d17be416c5e4426ee4a737f73b6f952ab5e57926fa701848e0a235a0a398300c65759fc45183151f2f082d4dcb5e37cb6290012d96f8819c547ba8a4000002f962140000000002a")],
  # frobenius(2) -----------------------
  [Fp[BW6_761].fromHex(  # norm(SNR)^((p-1)/3)^0
    "0x1"),
  Fp[BW6_761].fromHex(  # norm(SNR)^((p-1)/3)^1
    "0x531dc16c6ecd27aa846c61024e4cca6c1f31e53bd9603c2d17be416c5e4426ee4a737f73b6f952ab5e57926fa701848e0a235a0a398300c65759fc45183151f2f082d4dcb5e37cb6290012d96f8819c547ba8a4000002f962140000000002a"),
  Fp[BW6_761].fromHex(  # norm(SNR)^((p-1)/3)^2
    "0xcfca638f1500e327035cdf02acb2744d06e68545f7e64c256ab7ae14297a1a823132b971cdefc65870636cb60d217ff87fa59308c07a8fab8579e02ed3cddca5b093ed79b1c57b5fe3f89c11811c1e214983de300000535e7bc00000000060"),
  Fp[BW6_761].fromHex(  # norm(SNR)^((p-1)/3)^3
    "0x1"),
  Fp[BW6_761].fromHex(  # norm(SNR)^((p-1)/3)^4
    "0x531dc16c6ecd27aa846c61024e4cca6c1f31e53bd9603c2d17be416c5e4426ee4a737f73b6f952ab5e57926fa701848e0a235a0a398300c65759fc45183151f2f082d4dcb5e37cb6290012d96f8819c547ba8a4000002f962140000000002a"),
  Fp[BW6_761].fromHex(  # norm(SNR)^((p-1)/3)^5
    "0xcfca638f1500e327035cdf02acb2744d06e68545f7e64c256ab7ae14297a1a823132b971cdefc65870636cb60d217ff87fa59308c07a8fab8579e02ed3cddca5b093ed79b1c57b5fe3f89c11811c1e214983de300000535e7bc00000000060")],
  # frobenius(3) -----------------------
  [Fp[BW6_761].fromHex(  # (SNR²)^((p-1)/3)^0
    "0x1"),
  Fp[BW6_761].fromHex(  # (SNR²)^((p-1)/3)^1
    "0x1"),
  Fp[BW6_761].fromHex(  # (SNR²)^((p-1)/3)^2
    "0x1"),
  Fp[BW6_761].fromHex(  # (SNR²)^((p-1)/3)^3
    "0x1"),
  Fp[BW6_761].fromHex(  # (SNR²)^((p-1)/3)^4
    "0x1"),
  Fp[BW6_761].fromHex(  # (SNR²)^((p-1)/3)^5
    "0x1")]]

# ψ (Psi) - Untwist-Frobenius-Twist Endomorphisms on twisted curves
# -----------------------------------------------------------------
# BW6_761 is a M-Twist: psi1_coef1 = (1/SNR)^((p-1)/3)

# (1/SNR)^(2(p-1)/3)
const BW6_761_FrobeniusPsi_psi1_coef2* = Fp[BW6_761].fromHex(
  "0x531dc16c6ecd27aa846c61024e4cca6c1f31e53bd9603c2d17be416c5e4426ee4a737f73b6f952ab5e57926fa701848e0a235a0a398300c65759fc45183151f2f082d4dcb5e37cb6290012d96f8819c547ba8a4000002f962140000000002a")
# (1/SNR)^(3(p-1)/3)
const BW6_761_FrobeniusPsi_psi1_coef3* = Fp[BW6_761].fromHex(
  "0x122e824fb83ce0ad187c94004faff3eb926186a81d14688528275ef8087be41707ba638e584e91903cebaff25b423048689c8ed12f9fd9071dcd3dc73ebff2e98a116c25667a8f8160cf8aeeaf0a437e6913e6870000082f49d00000000008a")
# norm((1/SNR))^(2(p-1)/3)
const BW6_761_FrobeniusPsi_psi2_coef2* = Fp[BW6_761].fromHex(
  "0xcfca638f1500e327035cdf02acb2744d06e68545f7e64c256ab7ae14297a1a823132b971cdefc65870636cb60d217ff87fa59308c07a8fab8579e02ed3cddca5b093ed79b1c57b5fe3f89c11811c1e214983de300000535e7bc00000000060")
# norm((1/SNR))^(3(p-1)/3)
const BW6_761_FrobeniusPsi_psi2_coef3* = Fp[BW6_761].fromHex(
  "0x1")
