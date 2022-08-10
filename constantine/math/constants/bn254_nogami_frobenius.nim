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

const BN254_Nogami_FrobeniusMapCoefficients* = [
  # frobenius(1) -----------------------
  [Fp2[BN254_Nogami].fromHex(  # SNR^((p-1)/6)^0
    "0x1",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex(  # SNR^((p-1)/6)^1
    "0x1b377619212e7c8cb6499b50a846953f850974924d3f77c2e17de6c06f2a6de9",
    "0x9ebee691ed1837503eab22f57b96ac8dc178b6db2c08850c582193f90d5922a"
  ),
  Fp2[BN254_Nogami].fromHex(  # SNR^((p-1)/6)^2
    "0x0",
    "0x25236482400000017080eb4000000006181800000000000cd98000000000000b"
  ),
  Fp2[BN254_Nogami].fromHex(  # SNR^((p-1)/6)^3
    "0x23dfc9d1a39f4db8c69b87a8848aa075a7333a0e62d78cbf4b1b8eeae58b81c5",
    "0x23dfc9d1a39f4db8c69b87a8848aa075a7333a0e62d78cbf4b1b8eeae58b81c5"
  ),
  Fp2[BN254_Nogami].fromHex(  # SNR^((p-1)/6)^4
    "0x25236482400000017080eb4000000006181800000000000cd98000000000000c",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex(  # SNR^((p-1)/6)^5
    "0x19f3db6884cdca43c2b0d5792cd135accb1baea0b017046e859975ab54b5ef9b",
    "0xb2f8919bb3235bdf7837806d32eca5b9605515f4fe8fba521668a54ab4a1078"
  )],

  # frobenius(2) -----------------------
  [Fp2[BN254_Nogami].fromHex(  # SNR^((p^2-1)/6)^0
    "0x1",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex(  # SNR^((p^2-1)/6)^1
    "0x49b36240000000024909000000000006cd80000000000008",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex(  # SNR^((p^2-1)/6)^2
    "0x49b36240000000024909000000000006cd80000000000007",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex(  # SNR^((p^2-1)/6)^3
    "0x2523648240000001ba344d80000000086121000000000013a700000000000012",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex(  # SNR^((p^2-1)/6)^4
    "0x25236482400000017080eb4000000006181800000000000cd98000000000000b",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex(  # SNR^((p^2-1)/6)^5
    "0x25236482400000017080eb4000000006181800000000000cd98000000000000c",
    "0x0"
  )],

  # frobenius(3) -----------------------
  [Fp2[BN254_Nogami].fromHex(  # SNR^((p^3-1)/6)^0
    "0x1",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex(  # SNR^((p^3-1)/6)^1
    "0x1439ab09c60b248f398c5d77b755f92b9edc5f19d2873545be471151a747e4e",
    "0x23dfc9d1a39f4db8c69b87a8848aa075a7333a0e62d78cbf4b1b8eeae58b81c5"
  ),
  Fp2[BN254_Nogami].fromHex(  # SNR^((p^3-1)/6)^2
    "0x0",
    "0x1"
  ),
  Fp2[BN254_Nogami].fromHex(  # SNR^((p^3-1)/6)^3
    "0x1439ab09c60b248f398c5d77b755f92b9edc5f19d2873545be471151a747e4e",
    "0x1439ab09c60b248f398c5d77b755f92b9edc5f19d2873545be471151a747e4e"
  ),
  Fp2[BN254_Nogami].fromHex(  # SNR^((p^3-1)/6)^4
    "0x2523648240000001ba344d80000000086121000000000013a700000000000012",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex(  # SNR^((p^3-1)/6)^5
    "0x23dfc9d1a39f4db8c69b87a8848aa075a7333a0e62d78cbf4b1b8eeae58b81c5",
    "0x1439ab09c60b248f398c5d77b755f92b9edc5f19d2873545be471151a747e4e"
  )],
]

# ψ (Psi) - Untwist-Frobenius-Twist Endomorphisms on twisted curves
# -----------------------------------------------------------------
# BN254_Nogami is a D-Twist: psi1_coef1 = SNR^((p-1)/6)

# SNR^(2(p-1)/6)
const BN254_Nogami_FrobeniusPsi_psi1_coef2* = Fp2[BN254_Nogami].fromHex(
  "0x0",
  "0x25236482400000017080eb4000000006181800000000000cd98000000000000b"
)
# SNR^(3(p-1)/6)
const BN254_Nogami_FrobeniusPsi_psi1_coef3* = Fp2[BN254_Nogami].fromHex(
  "0x23dfc9d1a39f4db8c69b87a8848aa075a7333a0e62d78cbf4b1b8eeae58b81c5",
  "0x23dfc9d1a39f4db8c69b87a8848aa075a7333a0e62d78cbf4b1b8eeae58b81c5"
)
# SNR^(2(p^2-1)/6)
const BN254_Nogami_FrobeniusPsi_psi2_coef2* = Fp2[BN254_Nogami].fromHex(
  "0x49b36240000000024909000000000006cd80000000000007",
  "0x0"
)
# SNR^(3(p^2-1)/6)
const BN254_Nogami_FrobeniusPsi_psi2_coef3* = Fp2[BN254_Nogami].fromHex(
  "0x2523648240000001ba344d80000000086121000000000013a700000000000012",
  "0x0"
)
# SNR^(2(p^3-1)/6)
const BN254_Nogami_FrobeniusPsi_psi3_coef2* = Fp2[BN254_Nogami].fromHex(
  "0x0",
  "0x1"
)
# SNR^(3(p^3-1)/6)
const BN254_Nogami_FrobeniusPsi_psi3_coef3* = Fp2[BN254_Nogami].fromHex(
  "0x1439ab09c60b248f398c5d77b755f92b9edc5f19d2873545be471151a747e4e",
  "0x1439ab09c60b248f398c5d77b755f92b9edc5f19d2873545be471151a747e4e"
)
# SNR^(2(p^4-1)/6)
const BN254_Nogami_FrobeniusPsi_psi4_coef2* = Fp2[BN254_Nogami].fromHex(
  "0x25236482400000017080eb4000000006181800000000000cd98000000000000b",
  "0x0"
)
# SNR^(3(p^4-1)/6)
const BN254_Nogami_FrobeniusPsi_psi4_coef3* = Fp2[BN254_Nogami].fromHex(
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
