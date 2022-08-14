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
  ../io/io_extfields

{.used.}

# Frobenius map - on extension fields
# -----------------------------------------------------------------

# We start from base frobenius constant for a 12 embedding degree.
# with
# - a sextic twist, SNR being the Sextic Non-Residue.
# - coef being the Frobenius coefficient "ID"
# c = SNR^((p-1)/6)^coef
#
# On Fp2 frobenius(c) = conj(c) so we have
# For n=2, with n the number of Frobenius applications
# c2 = c * (c^p) = c * frobenius(c) = c * conj(c)
# c2 = (SNR * conj(SNR))^((p-1)/6)^coef)
# c2 = (norm(SNR))^((p-1)/6)^coef)
# For k=3
# c3 = c * c2^p = c * frobenius(c2) = c * conj(c2)
# with conj(norm(SNR)) = norm(SNR) as a norm is strictly on the base field.
# c3 = (SNR * norm(SNR))^((p-1)/6)^coef)
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
# cn = SNR^((p-1)/6)^coef^((p^n-1)/(p-1))
# cn = SNR^((p^n-1)/6)^coef
# cn = SNR^(coef * (p^n-1)/6)

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
  [Fp2[BLS12_377].fromHex(  # SNR^((p^2-1)/6)^0
    "0x1",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # SNR^((p^2-1)/6)^1
    "0x9b3af05dd14f6ec619aaf7d34594aabc5ed1347970dec00452217cc900000008508c00000000002",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # SNR^((p^2-1)/6)^2
    "0x9b3af05dd14f6ec619aaf7d34594aabc5ed1347970dec00452217cc900000008508c00000000001",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # SNR^((p^2-1)/6)^3
    "0x1ae3a4617c510eac63b05c06ca1493b1a22d9f300f5138f1ef3622fba094800170b5d44300000008508c00000000000",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # SNR^((p^2-1)/6)^4
    "0x1ae3a4617c510eabc8756ba8f8c524eb8882a75cc9bc8e359064ee822fb5bffd1e945779fffffffffffffffffffffff",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # SNR^((p^2-1)/6)^5
    "0x1ae3a4617c510eabc8756ba8f8c524eb8882a75cc9bc8e359064ee822fb5bffd1e94577a00000000000000000000000",
    "0x0"
  )],

  # frobenius(3) -----------------------
  [Fp2[BLS12_377].fromHex(  # SNR^((p^3-1)/6)^0
    "0x1",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # SNR^((p^3-1)/6)^1
    "0x1680a40796537cac0c534db1a79beb1400398f50ad1dec1bce649cf436b0f6299588459bff27d8e6e76d5ecf1391c63",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # SNR^((p^3-1)/6)^2
    "0x1ae3a4617c510eac63b05c06ca1493b1a22d9f300f5138f1ef3622fba094800170b5d44300000008508c00000000000",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # SNR^((p^3-1)/6)^3
    "0x4630059e5fd9200575d0e552278a89da1f40fdf62334cd620d1860769e389d7db2d8ea700d82721691ea130ec6e39e",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # SNR^((p^3-1)/6)^4
    "0x1",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # SNR^((p^3-1)/6)^5
    "0x1680a40796537cac0c534db1a79beb1400398f50ad1dec1bce649cf436b0f6299588459bff27d8e6e76d5ecf1391c63",
    "0x0"
  )],
]

# ψ (Psi) - Untwist-Frobenius-Twist Endomorphisms on twisted curves
# -----------------------------------------------------------------
# BLS12_377 is a D-Twist: psi1_coef1 = SNR^((p-1)/6)

# SNR^(2(p-1)/6)
const BLS12_377_FrobeniusPsi_psi1_coef2* = Fp2[BLS12_377].fromHex(
  "0x9b3af05dd14f6ec619aaf7d34594aabc5ed1347970dec00452217cc900000008508c00000000002",
  "0x0"
)
# SNR^(3(p-1)/6)
const BLS12_377_FrobeniusPsi_psi1_coef3* = Fp2[BLS12_377].fromHex(
  "0x1680a40796537cac0c534db1a79beb1400398f50ad1dec1bce649cf436b0f6299588459bff27d8e6e76d5ecf1391c63",
  "0x0"
)
# SNR^(2(p^2-1)/6)
const BLS12_377_FrobeniusPsi_psi2_coef2* = Fp2[BLS12_377].fromHex(
  "0x9b3af05dd14f6ec619aaf7d34594aabc5ed1347970dec00452217cc900000008508c00000000001",
  "0x0"
)
# SNR^(3(p^2-1)/6)
const BLS12_377_FrobeniusPsi_psi2_coef3* = Fp2[BLS12_377].fromHex(
  "0x1ae3a4617c510eac63b05c06ca1493b1a22d9f300f5138f1ef3622fba094800170b5d44300000008508c00000000000",
  "0x0"
)
# SNR^(2(p^3-1)/6)
const BLS12_377_FrobeniusPsi_psi3_coef2* = Fp2[BLS12_377].fromHex(
  "0x1ae3a4617c510eac63b05c06ca1493b1a22d9f300f5138f1ef3622fba094800170b5d44300000008508c00000000000",
  "0x0"
)
# SNR^(3(p^3-1)/6)
const BLS12_377_FrobeniusPsi_psi3_coef3* = Fp2[BLS12_377].fromHex(
  "0x4630059e5fd9200575d0e552278a89da1f40fdf62334cd620d1860769e389d7db2d8ea700d82721691ea130ec6e39e",
  "0x0"
)
# SNR^(2(p^4-1)/6)
const BLS12_377_FrobeniusPsi_psi4_coef2* = Fp2[BLS12_377].fromHex(
  "0x1ae3a4617c510eabc8756ba8f8c524eb8882a75cc9bc8e359064ee822fb5bffd1e945779fffffffffffffffffffffff",
  "0x0"
)
# SNR^(3(p^4-1)/6)
const BLS12_377_FrobeniusPsi_psi4_coef3* = Fp2[BLS12_377].fromHex(
  "0x1",
  "0x0"
)

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
