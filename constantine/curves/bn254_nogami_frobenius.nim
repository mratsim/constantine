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
# Then for frobenius(2): c * conjugate(c)
# And for frobenius(3): c² * conjugate(c)
const FrobMapConst_BN254_Nogami* = [
  # frobenius(1)
  [Fp2[BN254_Nogami].fromHex( # SNR^((p-1)/6)^0
    "0x1",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex(  # SNR^((p-1)/6)^1
    "0x1b377619212e7c8cb6499b50a846953f850974924d3f77c2e17de6c06f2a6de9",
    "0x9ebee691ed1837503eab22f57b96ac8dc178b6db2c08850c582193f90d5922a"
  ),
  Fp2[BN254_Nogami].fromHex(  # SNR^((p-1)/6)^2 = SNR^((p-1)/3)
    "0x0",
    "0x25236482400000017080eb4000000006181800000000000cd98000000000000b"
  ),
  Fp2[BN254_Nogami].fromHex( # SNR^((p-1)/6)^3 = SNR^((p-1)/2)
    "0x23dfc9d1a39f4db8c69b87a8848aa075a7333a0e62d78cbf4b1b8eeae58b81c5",
    "0x23dfc9d1a39f4db8c69b87a8848aa075a7333a0e62d78cbf4b1b8eeae58b81c5"
  ),
  Fp2[BN254_Nogami].fromHex( # SNR^((p-1)/6)^4 = SNR^(2(p-1)/3)
    "0x25236482400000017080eb4000000006181800000000000cd98000000000000c",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex( # SNR^((p-1)/6)^5
    "0x19f3db6884cdca43c2b0d5792cd135accb1baea0b017046e859975ab54b5ef9b",
    "0xb2f8919bb3235bdf7837806d32eca5b9605515f4fe8fba521668a54ab4a1078"
  )],
  # frobenius(2)
  [Fp2[BN254_Nogami].fromHex( # norm(SNR)^((p-1)/6)^1
    "0x1",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex( # norm(SNR)^((p-1)/6)^2
    "0x49b36240000000024909000000000006cd80000000000008",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex(
    "0x49b36240000000024909000000000006cd80000000000007",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex(
    "0x2523648240000001ba344d80000000086121000000000013a700000000000012",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex(
    "0x25236482400000017080eb4000000006181800000000000cd98000000000000b",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex(
    "0x25236482400000017080eb4000000006181800000000000cd98000000000000c",
    "0x0"
  )],
  # frobenius(3)
  [Fp2[BN254_Nogami].fromHex(
    "0x1",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex(
    "0x1439ab09c60b248f398c5d77b755f92b9edc5f19d2873545be471151a747e4e",
    "0x23dfc9d1a39f4db8c69b87a8848aa075a7333a0e62d78cbf4b1b8eeae58b81c5"
  ),
  Fp2[BN254_Nogami].fromHex(
    "0x0",
    "0x1"
  ),
  Fp2[BN254_Nogami].fromHex(
    "0x1439ab09c60b248f398c5d77b755f92b9edc5f19d2873545be471151a747e4e",
    "0x1439ab09c60b248f398c5d77b755f92b9edc5f19d2873545be471151a747e4e"
  ),
  Fp2[BN254_Nogami].fromHex(
    "0x2523648240000001ba344d80000000086121000000000013a700000000000012",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex(
    "0x23dfc9d1a39f4db8c69b87a8848aa075a7333a0e62d78cbf4b1b8eeae58b81c5",
    "0x1439ab09c60b248f398c5d77b755f92b9edc5f19d2873545be471151a747e4e"
  )]]

# ψ (Psi) - Untwist-Frobenius-Twist Endomorphisms on twisted curves
# -----------------------------------------------------------------

#   BN254_Snarks is a D-Twist: SNR^((p-1)/6)
const FrobPsiConst_BN254_Nogami_psi1_coef1* = Fp2[BN254_Nogami].fromHex(
  "0x1b377619212e7c8cb6499b50a846953f850974924d3f77c2e17de6c06f2a6de9",
  "0x9ebee691ed1837503eab22f57b96ac8dc178b6db2c08850c582193f90d5922a"
)
#  SNR^((p-1)/3)
const FrobPsiConst_BN254_Nogami_psi1_coef2* = Fp2[BN254_Nogami].fromHex(
  "0x0",
  "0x25236482400000017080eb4000000006181800000000000cd98000000000000b"
)
#  SNR^((p-1)/2)
const FrobPsiConst_BN254_Nogami_psi1_coef3* = Fp2[BN254_Nogami].fromHex(
  "0x23dfc9d1a39f4db8c69b87a8848aa075a7333a0e62d78cbf4b1b8eeae58b81c5",
  "0x23dfc9d1a39f4db8c69b87a8848aa075a7333a0e62d78cbf4b1b8eeae58b81c5"
)
#  norm(SNR)^((p-1)/3)
const FrobPsiConst_BN254_Nogami_psi2_coef2* = Fp2[BN254_Nogami].fromHex(
  "0x49b36240000000024909000000000006cd80000000000007",
  "0x0"
)
