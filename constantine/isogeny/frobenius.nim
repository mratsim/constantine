# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/macros,
  ../config/[common, curves],
  ../io/io_towers,
  ../towers, ../arithmetic

# Frobenius automorphism
# ------------------------------------------------------------
#
# https://en.wikipedia.org/wiki/Frobenius_endomorphism
# For p prime
#
#   a^p (mod p) ≡ a (mod p)
#
# Also
#
#   (a + b)^p (mod p) ≡ a^p + b^p (mod p)
#                     ≡ a   + b   (mod p)
#
# Because p is prime and all expanded terms (from binomial expansion)
# besides a^p and b^p are divisible by p

# For 𝔽p2, with `u` the quadratic non-residue (usually the complex 𝑖)
# (a + u b)^p² (mod p²) ≡ a + u^p² b (mod p²)
#
# For 𝔽p2, frobenius acts like the conjugate
# whether u = √-1 = i
# or          √-2 or √-5

func frobenius*(r: var Fp2, a: Fp2, k: static int = 1) {.inline.} =
  ## Computes a^(p^k)
  ## The p-power frobenius automorphism on 𝔽p2
  r.c0 = a.c0
  when (k and 1) == 1:
    r.c1.neg(a.c1)
  else:
    r.c1 = a.c1

# Frobenius endomorphism
# ------------------------------------------------------------
# TODO: generate those constants via Sage in a Json file
#       and parse at compile-time

# Constants:
#   Assuming embedding degree of 12 and a sextic twist
#   with SNR the sextic non-residue
#
#   BN254_Snarks is a D-Twist: SNR^((p-1)/6)
const FrobConst_BN254_Snarks_psi1_coef1 = Fp2[BN254_Snarks].fromHex(
  "0x1284b71c2865a7dfe8b99fdd76e68b605c521e08292f2176d60b35dadcc9e470",
  "0x246996f3b4fae7e6a6327cfe12150b8e747992778eeec7e5ca5cf05f80f362ac"
)
#  SNR^((p-1)/3)
const FrobConst_BN254_Snarks_psi1_coef2 = Fp2[BN254_Snarks].fromHex(
  "0x2fb347984f7911f74c0bec3cf559b143b78cc310c2c3330c99e39557176f553d",
  "0x16c9e55061ebae204ba4cc8bd75a079432ae2a1d0b7c9dce1665d51c640fcba2"
)
#  SNR^((p-1)/2)
const FrobConst_BN254_Snarks_psi1_coef3 = Fp2[BN254_Snarks].fromHex(
  "0x63cf305489af5dcdc5ec698b6e2f9b9dbaae0eda9c95998dc54014671a0135a",
  "0x7c03cbcac41049a0704b5a7ec796f2b21807dc98fa25bd282d37f632623b0e3"
)
#  norm(SNR)^((p-1)/3)
const FrobConst_BN254_Snarks_psi2_coef2 = Fp2[BN254_Snarks].fromHex(
  "0x30644e72e131a0295e6dd9e7e0acccb0c28f069fbb966e3de4bd44e5607cfd48",
  "0x0"
)

#   BLS12_377 is a D-Twist: SNR^((p-1)/6)
const FrobConst_BLS12_377_psi1_coef1 = Fp2[BLS12_377].fromHex(
  "0x9a9975399c019633c1e30682567f915c8a45e0f94ebc8ec681bf34a3aa559db57668e558eb0188e938a9d1104f2031",
  "0x0"
)
#  SNR^((p-1)/3)
const FrobConst_BLS12_377_psi1_coef2 = Fp2[BLS12_377].fromHex(
  "0x9b3af05dd14f6ec619aaf7d34594aabc5ed1347970dec00452217cc900000008508c00000000002",
  "0x0"
)
#  SNR^((p-1)/2)
const FrobConst_BLS12_377_psi1_coef3 = Fp2[BLS12_377].fromHex(
  "0x1680a40796537cac0c534db1a79beb1400398f50ad1dec1bce649cf436b0f6299588459bff27d8e6e76d5ecf1391c63",
  "0x0"
)
#  norm(SNR)^((p-1)/3)
const FrobConst_BLS12_377_psi2_coef2 = Fp2[BLS12_377].fromHex(
  "0x9b3af05dd14f6ec619aaf7d34594aabc5ed1347970dec00452217cc900000008508c00000000001",
  "0x0"
)

#   BLS12_381 is a M-twist: (1/SNR)^((p-1)/6)
const FrobConst_BLS12_381_psi1_coef1 = Fp2[BLS12_381].fromHex(
  "0x5b2cfd9013a5fd8df47fa6b48b1e045f39816240c0b8fee8beadf4d8e9c0566c63a3e6e257f87329b18fae980078116",
  "0x5b2cfd9013a5fd8df47fa6b48b1e045f39816240c0b8fee8beadf4d8e9c0566c63a3e6e257f87329b18fae980078116"
)
#  (1/SNR)^((p-1)/3)
const FrobConst_BLS12_381_psi1_coef2 = Fp2[BLS12_381].fromHex(
  "0x0",
  "0x1a0111ea397fe699ec02408663d4de85aa0d857d89759ad4897d29650fb85f9b409427eb4f49fffd8bfd00000000aaad"
)
#  (1/SNR)^((p-1)/2)
const FrobConst_BLS12_381_psi1_coef3 = Fp2[BLS12_381].fromHex(
  "0x135203e60180a68ee2e9c448d77a2cd91c3dedd930b1cf60ef396489f61eb45e304466cf3e67fa0af1ee7b04121bdea2",
  "0x6af0e0437ff400b6831e36d6bd17ffe48395dabc2d3435e77f76e17009241c5ee67992f72ec05f4c81084fbede3cc09"
)
#  norm(SNR)^((p-1)/3)
const FrobConst_BLS12_381_psi2_coef2 = Fp2[BLS12_381].fromHex(
  "0x1a0111ea397fe699ec02408663d4de85aa0d857d89759ad4897d29650fb85f9b409427eb4f49fffd8bfd00000000aaac",
  "0x0"
)

{.experimental: "dynamicBindSym".}

macro frobConst(C: static Curve, psipow, coefpow: static int): untyped =
  return bindSym("FrobConst_" & $C & "_psi" & $psipow & "_coef" & $coefpow)

template mulCheckSparse[Fp2](a: var Fp2, b: Fp2) =
  when b.c0.isZero().bool:
    a.mul_sparse_by_0y(b)
  elif b.c1.isZero().bool:
    a.mul_sparse_by_x0(b)
  else:
    a *= b

func frobenius_psi*[PointG2](r: var PointG2, P: PointG2) =
  ## "Untwist-Frobenius-Twist" endomorphism
  ## r = ψ(P)
  for coordR, coordP in fields(r, P):
    coordR.frobenius(coordP, 1)

  # With ξ (xi) the sextic non-residue
  # c = ξ^((p-1)/6) for D-Twist
  # c = (1/ξ)^((p-1)/6) for M-Twist
  #
  # c1_2 = c²
  # c1_3 = c³

  r.x.mulCheckSparse frobConst(PointG2.F.C, psipow=1, coefpow=2)
  r.y.mulCheckSparse frobConst(PointG2.F.C, psipow=1, coefpow=3)

func frobenius_psi2*[PointG2](r: var PointG2, P: PointG2) =
  ## "Untwist-Frobenius-Twist" endomorphism applied twice
  ## r = ψ(ψ(P))
  for coordR, coordP in fields(r, P):
    coordR.frobenius(coordP, 2)

  # With ξ (xi) the sextic non-residue
  # c = ξ for D-Twist
  # c = (1/ξ) for M-Twist
  #
  # frobenius(a) = conj(a) = a^p
  #
  # c1_2 = (c^((p-1)/6))² = c^((p-1)/3)
  # c1_3 = (c^((p-1)/6))³ = c^((p-1)/2)
  #
  # c2_2 = c1_2 * frobenius(c1_2) = c^((p-1)/3) * c^((p-1)/3)^p
  #      = c^((p-1)/3) * conj(c)^((p-1)/3)
  #      = norm(c)^((p-1)/3)
  #
  # c2_3 = c1_3 * frobenius(c1_3) = c^((p-1)/2) * c^((p-1)/2)^p
  #      = c^((p-1)/2) * conj(c)^((p-1)/2)
  #      = norm(c)^((p-1)/2)
  # We prove that c2_3 ≡ -1 (mod p²) with the following:
  #
  # - Whether c = ξ or c = (1/ξ), c is a quadratic non-residue (QNR) in 𝔽p2
  #   because:
  #   - ξ is quadratic non-residue as it is a sextic non-residue
  #     by construction of the tower extension
  #   - if a is QNR then 1/a is also a QNR
  # - Then c^((p²-1)/2) ≡ -1 (mod p²) from the Legendre symbol in 𝔽p2
  #
  # c2_3 = c^((p-1)/2) * c^((p-1)/2)^p = c^((p+1)*(p-1)/2)
  #      = c^((p²-1)/2)
  # c2_3 ≡ -1 (mod p²)
  # QED

  r.x.mulCheckSparse frobConst(PointG2.F.C, psipow=2, coefpow=2)
  r.y.neg(r.y)
