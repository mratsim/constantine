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

const BN254_Snarks_FrobeniusMapCoefficients* = [
  # frobenius(1) -----------------------
  [Fp2[BN254_Snarks].fromHex(  # SNR^((p-1)/6)^0
    "0x1",
    "0x0"
  ),
  Fp2[BN254_Snarks].fromHex(  # SNR^((p-1)/6)^1
    "0x1284b71c2865a7dfe8b99fdd76e68b605c521e08292f2176d60b35dadcc9e470",
    "0x246996f3b4fae7e6a6327cfe12150b8e747992778eeec7e5ca5cf05f80f362ac"
  ),
  Fp2[BN254_Snarks].fromHex(  # SNR^((p-1)/6)^2
    "0x2fb347984f7911f74c0bec3cf559b143b78cc310c2c3330c99e39557176f553d",
    "0x16c9e55061ebae204ba4cc8bd75a079432ae2a1d0b7c9dce1665d51c640fcba2"
  ),
  Fp2[BN254_Snarks].fromHex(  # SNR^((p-1)/6)^3
    "0x63cf305489af5dcdc5ec698b6e2f9b9dbaae0eda9c95998dc54014671a0135a",
    "0x7c03cbcac41049a0704b5a7ec796f2b21807dc98fa25bd282d37f632623b0e3"
  ),
  Fp2[BN254_Snarks].fromHex(  # SNR^((p-1)/6)^4
    "0x5b54f5e64eea80180f3c0b75a181e84d33365f7be94ec72848a1f55921ea762",
    "0x2c145edbe7fd8aee9f3a80b03b0b1c923685d2ea1bdec763c13b4711cd2b8126"
  ),
  Fp2[BN254_Snarks].fromHex(  # SNR^((p-1)/6)^5
    "0x183c1e74f798649e93a3661a4353ff4425c459b55aa1bd32ea2c810eab7692f",
    "0x12acf2ca76fd0675a27fb246c7729f7db080cb99678e2ac024c6b8ee6e0c2c4b"
  )],

  # frobenius(2) -----------------------
  [Fp2[BN254_Snarks].fromHex(  # SNR^((p^2-1)/6)^0
    "0x1",
    "0x0"
  ),
  Fp2[BN254_Snarks].fromHex(  # SNR^((p^2-1)/6)^1
    "0x30644e72e131a0295e6dd9e7e0acccb0c28f069fbb966e3de4bd44e5607cfd49",
    "0x0"
  ),
  Fp2[BN254_Snarks].fromHex(  # SNR^((p^2-1)/6)^2
    "0x30644e72e131a0295e6dd9e7e0acccb0c28f069fbb966e3de4bd44e5607cfd48",
    "0x0"
  ),
  Fp2[BN254_Snarks].fromHex(  # SNR^((p^2-1)/6)^3
    "0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd46",
    "0x0"
  ),
  Fp2[BN254_Snarks].fromHex(  # SNR^((p^2-1)/6)^4
    "0x59e26bcea0d48bacd4f263f1acdb5c4f5763473177fffffe",
    "0x0"
  ),
  Fp2[BN254_Snarks].fromHex(  # SNR^((p^2-1)/6)^5
    "0x59e26bcea0d48bacd4f263f1acdb5c4f5763473177ffffff",
    "0x0"
  )],

  # frobenius(3) -----------------------
  [Fp2[BN254_Snarks].fromHex(  # SNR^((p^3-1)/6)^0
    "0x1",
    "0x0"
  ),
  Fp2[BN254_Snarks].fromHex(  # SNR^((p^3-1)/6)^1
    "0x19dc81cfcc82e4bbefe9608cd0acaa90894cb38dbe55d24ae86f7d391ed4a67f",
    "0xabf8b60be77d7306cbeee33576139d7f03a5e397d439ec7694aa2bf4c0c101"
  ),
  Fp2[BN254_Snarks].fromHex(  # SNR^((p^3-1)/6)^2
    "0x856e078b755ef0abaff1c77959f25ac805ffd3d5d6942d37b746ee87bdcfb6d",
    "0x4f1de41b3d1766fa9f30e6dec26094f0fdf31bf98ff2631380cab2baaa586de"
  ),
  Fp2[BN254_Snarks].fromHex(  # SNR^((p^3-1)/6)^3
    "0x2a275b6d9896aa4cdbf17f1dca9e5ea3bbd689a3bea870f45fcc8ad066dce9ed",
    "0x28a411b634f09b8fb14b900e9507e9327600ecc7d8cf6ebab94d0cb3b2594c64"
  ),
  Fp2[BN254_Snarks].fromHex(  # SNR^((p^3-1)/6)^4
    "0xbc58c6611c08dab19bee0f7b5b2444ee633094575b06bcb0e1a92bc3ccbf066",
    "0x23d5e999e1910a12feb0f6ef0cd21d04a44a9e08737f96e55fe3ed9d730c239f"
  ),
  Fp2[BN254_Snarks].fromHex(  # SNR^((p^3-1)/6)^5
    "0x13c49044952c0905711699fa3b4d3f692ed68098967c84a5ebde847076261b43",
    "0x16db366a59b1dd0b9fb1b2282a48633d3e2ddaea200280211f25041384282499"
  )],
]

# ψ (Psi) - Untwist-Frobenius-Twist Endomorphisms on twisted curves
# -----------------------------------------------------------------
# BN254_Snarks is a D-Twist: psi1_coef1 = SNR^((p-1)/6)

# SNR^(2(p-1)/6)
const BN254_Snarks_FrobeniusPsi_psi1_coef2* = Fp2[BN254_Snarks].fromHex(
  "0x2fb347984f7911f74c0bec3cf559b143b78cc310c2c3330c99e39557176f553d",
  "0x16c9e55061ebae204ba4cc8bd75a079432ae2a1d0b7c9dce1665d51c640fcba2"
)
# SNR^(3(p-1)/6)
const BN254_Snarks_FrobeniusPsi_psi1_coef3* = Fp2[BN254_Snarks].fromHex(
  "0x63cf305489af5dcdc5ec698b6e2f9b9dbaae0eda9c95998dc54014671a0135a",
  "0x7c03cbcac41049a0704b5a7ec796f2b21807dc98fa25bd282d37f632623b0e3"
)
# SNR^(2(p^2-1)/6)
const BN254_Snarks_FrobeniusPsi_psi2_coef2* = Fp2[BN254_Snarks].fromHex(
  "0x30644e72e131a0295e6dd9e7e0acccb0c28f069fbb966e3de4bd44e5607cfd48",
  "0x0"
)
# SNR^(3(p^2-1)/6)
const BN254_Snarks_FrobeniusPsi_psi2_coef3* = Fp2[BN254_Snarks].fromHex(
  "0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd46",
  "0x0"
)
# SNR^(2(p^3-1)/6)
const BN254_Snarks_FrobeniusPsi_psi3_coef2* = Fp2[BN254_Snarks].fromHex(
  "0x856e078b755ef0abaff1c77959f25ac805ffd3d5d6942d37b746ee87bdcfb6d",
  "0x4f1de41b3d1766fa9f30e6dec26094f0fdf31bf98ff2631380cab2baaa586de"
)
# SNR^(3(p^3-1)/6)
const BN254_Snarks_FrobeniusPsi_psi3_coef3* = Fp2[BN254_Snarks].fromHex(
  "0x2a275b6d9896aa4cdbf17f1dca9e5ea3bbd689a3bea870f45fcc8ad066dce9ed",
  "0x28a411b634f09b8fb14b900e9507e9327600ecc7d8cf6ebab94d0cb3b2594c64"
)
# SNR^(2(p^4-1)/6)
const BN254_Snarks_FrobeniusPsi_psi4_coef2* = Fp2[BN254_Snarks].fromHex(
  "0x59e26bcea0d48bacd4f263f1acdb5c4f5763473177fffffe",
  "0x0"
)
# SNR^(3(p^4-1)/6)
const BN254_Snarks_FrobeniusPsi_psi4_coef3* = Fp2[BN254_Snarks].fromHex(
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
