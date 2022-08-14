# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/curves,
  ../extension_fields,
  ../io/[io_fields, io_extfields]

{.used.}

# Frobenius map - on extension fields
# -----------------------------------------------------------------

# We start from base frobenius constant for a 6 embedding degree.
# with
# - a sextic twist, SNR being the Sextic Non-Residue.
# - coef being the Frobenius coefficient "ID"
# c = SNR^((p-1)/3)^coef
#
# On Fp2 frobenius(c) = conj(c) so we have
# For n=2, with n the number of Frobenius applications
# c2 = c * (c^p) = c * frobenius(c) = c * conj(c)
# c2 = (SNR * conj(SNR))^((p-1)/3)^coef)
# c2 = (norm(SNR))^((p-1)/3)^coef)
# For k=3
# c3 = c * c2^p = c * frobenius(c2) = c * conj(c2)
# with conj(norm(SNR)) = norm(SNR) as a norm is strictly on the base field.
# c3 = (SNR * norm(SNR))^((p-1)/3)^coef)
#
# A more generic formula can be derived by observing that
# c3 = c * c2^p = c * (c * c^p)^p
# c3 = c * c^p * c^p²
# with 4, we have
# c4 = c * c3^p = c * (c * c^p * c^p²)^p
# c4 = c * c^p * c^p² * c^p³
# with n we have
# cn = c * c^p * c^p² ... * c^p^(n-1)
# cn = c^(1+p+p² + ... + p^(n-1))
# This is the sum of first n terms of a geometric series
# hence cn = c^((p^n-1)/(p-1))
# We now expand c
# cn = SNR^((p-1)/3)^coef^((p^n-1)/(p-1))
# cn = SNR^((p^n-1)/3)^coef
# cn = SNR^(coef * (p^n-1)/3)

const BW6_761_FrobeniusMapCoefficients* = [
  # frobenius(1) -----------------------
  [Fp2[BW6_761].fromHex(  # SNR^((p-1)/3)^0
    "0x1",
    "0x0"
  ),
  Fp2[BW6_761].fromHex(  # SNR^((p-1)/3)^1
    "0xcfca638f1500e327035cdf02acb2744d06e68545f7e64c256ab7ae14297a1a823132b971cdefc65870636cb60d217ff87fa59308c07a8fab8579e02ed3cddca5b093ed79b1c57b5fe3f89c11811c1e214983de300000535e7bc00000000061",
    "0x0"
  ),
  Fp2[BW6_761].fromHex(  # SNR^((p-1)/3)^2
    "0xcfca638f1500e327035cdf02acb2744d06e68545f7e64c256ab7ae14297a1a823132b971cdefc65870636cb60d217ff87fa59308c07a8fab8579e02ed3cddca5b093ed79b1c57b5fe3f89c11811c1e214983de300000535e7bc00000000060",
    "0x0"
  )],

  # frobenius(2) -----------------------
  [Fp2[BW6_761].fromHex(  # SNR^((p^2-1)/3)^0
    "0x1",
    "0x0"
  ),
  Fp2[BW6_761].fromHex(  # SNR^((p^2-1)/3)^1
    "0xcfca638f1500e327035cdf02acb2744d06e68545f7e64c256ab7ae14297a1a823132b971cdefc65870636cb60d217ff87fa59308c07a8fab8579e02ed3cddca5b093ed79b1c57b5fe3f89c11811c1e214983de300000535e7bc00000000060",
    "0x0"
  ),
  Fp2[BW6_761].fromHex(  # SNR^((p^2-1)/3)^2
    "0x531dc16c6ecd27aa846c61024e4cca6c1f31e53bd9603c2d17be416c5e4426ee4a737f73b6f952ab5e57926fa701848e0a235a0a398300c65759fc45183151f2f082d4dcb5e37cb6290012d96f8819c547ba8a4000002f962140000000002a",
    "0x0"
  )],

  # frobenius(3) -----------------------
  [Fp2[BW6_761].fromHex(  # SNR^((p^3-1)/3)^0
    "0x1",
    "0x0"
  ),
  Fp2[BW6_761].fromHex(  # SNR^((p^3-1)/3)^1
    "0x122e824fb83ce0ad187c94004faff3eb926186a81d14688528275ef8087be41707ba638e584e91903cebaff25b423048689c8ed12f9fd9071dcd3dc73ebff2e98a116c25667a8f8160cf8aeeaf0a437e6913e6870000082f49d00000000008a",
    "0x0"
  ),
  Fp2[BW6_761].fromHex(  # SNR^((p^3-1)/3)^2
    "0x1",
    "0x0"
  )],
]

# ψ (Psi) - Untwist-Frobenius-Twist Endomorphisms on twisted curves
# -----------------------------------------------------------------
# BW6_761 is a M-Twist: psi1_coef1 = (1/SNR)^((p-1)/6)

# (1/SNR)^(2(p-1)/6)
const BW6_761_FrobeniusPsi_psi1_coef2* = Fp[BW6_761].fromHex(
  "0x531dc16c6ecd27aa846c61024e4cca6c1f31e53bd9603c2d17be416c5e4426ee4a737f73b6f952ab5e57926fa701848e0a235a0a398300c65759fc45183151f2f082d4dcb5e37cb6290012d96f8819c547ba8a4000002f962140000000002a")
# (1/SNR)^(3(p-1)/6)
const BW6_761_FrobeniusPsi_psi1_coef3* = Fp[BW6_761].fromHex(
  "0x122e824fb83ce0ad187c94004faff3eb926186a81d14688528275ef8087be41707ba638e584e91903cebaff25b423048689c8ed12f9fd9071dcd3dc73ebff2e98a116c25667a8f8160cf8aeeaf0a437e6913e6870000082f49d00000000008a")
# (1/SNR)^(2(p^2-1)/6)
const BW6_761_FrobeniusPsi_psi2_coef2* = Fp[BW6_761].fromHex(
  "0xcfca638f1500e327035cdf02acb2744d06e68545f7e64c256ab7ae14297a1a823132b971cdefc65870636cb60d217ff87fa59308c07a8fab8579e02ed3cddca5b093ed79b1c57b5fe3f89c11811c1e214983de300000535e7bc00000000060")
# (1/SNR)^(3(p^2-1)/6)
const BW6_761_FrobeniusPsi_psi2_coef3* = Fp[BW6_761].fromHex(
  "0x1")

# For a sextic twist
# - p ≡ 1 (mod 2)
# - p ≡ 1 (mod 3)
#
# psi2_coef3 is always -1 (mod p^m) with m = embdeg/twdeg
# Recap, with ξ (xi) the sextic non-residue for D-Twist or 1/SNR for M-Twist
# psi_2 ≡ ξ^((p-1)/6)^2 ≡ ξ^((p-1)/3)
# psi_3 ≡ psi_2 * ξ^((p-1)/6) ≡ ξ^((p-1)/3) * ξ^((p-1)/6) ≡ ξ^((p-1)/2)
#
# In Fp² (i.e. embedding degree of 12, G2 on Fp2)
# - quadratic non-residues respect the equation a^((p²-1)/2) ≡ -1 (mod p²) by the Legendre symbol
# - sextic non-residues are also quadratic non-residues so ξ^((p²-1)/2) ≡ -1 (mod p²)
# - QRT(1/a) = QRT(a) with QRT the quadratic residuosity test
#
# We have psi2_3 ≡ psi_3 * psi_3^p ≡ psi_3^(p+1)
#                ≡ (ξ^(p-1)/2)^(p+1) (mod p²)
#                ≡ ξ^((p-1)(p+1)/2) (mod p²)
#                ≡ ξ^((p²-1)/2) (mod p²)
# And ξ^((p²-1)/2) ≡ -1 (mod p²) since ξ is a quadratic non-residue
# So psi2_3 ≡ -1 (mod p²)
#
#
# In Fp (i.e. embedding degree of 6, G2 on Fp)
# - Fermat's Little Theorem gives us a^(p-1) ≡ 1 (mod p)
#
# psi2_3 ≡ ξ^((p-1)(p+1)/2) (mod p)
#        ≡ ξ^((p+1)/2)^(p-1) (mod p) as we have 2|p+1
#        ≡ 1 (mod p) by Fermat's Little Theorem
