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
const FrobConst_BN254_Snarks_coef1 = Fp2[BN254_Snarks].fromHex(
  "0x1284b71c2865a7dfe8b99fdd76e68b605c521e08292f2176d60b35dadcc9e470",
  "0x246996f3b4fae7e6a6327cfe12150b8e747992778eeec7e5ca5cf05f80f362ac"
)
#  SNR^((p-1)/3)
const FrobConst_BN254_Snarks_coef2 = Fp2[BN254_Snarks].fromHex(
  "0x2fb347984f7911f74c0bec3cf559b143b78cc310c2c3330c99e39557176f553d",
  "0x16c9e55061ebae204ba4cc8bd75a079432ae2a1d0b7c9dce1665d51c640fcba2"
)
#  SNR^((p-1)/2)
const FrobConst_BN254_Snarks_coef3 = Fp2[BN254_Snarks].fromHex(
  "0x63cf305489af5dcdc5ec698b6e2f9b9dbaae0eda9c95998dc54014671a0135a",
  "0x7c03cbcac41049a0704b5a7ec796f2b21807dc98fa25bd282d37f632623b0e3"
)

#   BLS12_377 is a D-Twist: SNR^((p-1)/6)
const FrobConst_BLS12_377_coef1 = Fp2[BLS12_377].fromHex(
  "0x9a9975399c019633c1e30682567f915c8a45e0f94ebc8ec681bf34a3aa559db57668e558eb0188e938a9d1104f2031",
  "0x0"
)
#  SNR^((p-1)/3)
const FrobConst_BLS12_377_coef2 = Fp2[BLS12_377].fromHex(
  "0x9b3af05dd14f6ec619aaf7d34594aabc5ed1347970dec00452217cc900000008508c00000000002",
  "0x0"
)
#  SNR^((p-1)/2)
const FrobConst_BLS12_377_coef3 = Fp2[BLS12_377].fromHex(
  "0x1680a40796537cac0c534db1a79beb1400398f50ad1dec1bce649cf436b0f6299588459bff27d8e6e76d5ecf1391c63",
  "0x0"
)

#   BLS12_381 is a M-twist: (1/SNR)^((p-1)/6)
const FrobConst_BLS12_381_coef1 = Fp2[BLS12_381].fromHex(
  "0x5b2cfd9013a5fd8df47fa6b48b1e045f39816240c0b8fee8beadf4d8e9c0566c63a3e6e257f87329b18fae980078116",
  "0x5b2cfd9013a5fd8df47fa6b48b1e045f39816240c0b8fee8beadf4d8e9c0566c63a3e6e257f87329b18fae980078116"
)
#  (1/SNR)^((p-1)/3)
const FrobConst_BLS12_381_coef2 = Fp2[BLS12_381].fromHex(
  "0x0",
  "0x1a0111ea397fe699ec02408663d4de85aa0d857d89759ad4897d29650fb85f9b409427eb4f49fffd8bfd00000000aaad"
)
#  (1/SNR)^((p-1)/2)
const FrobConst_BLS12_381_coef3 = Fp2[BLS12_381].fromHex(
  "0x135203e60180a68ee2e9c448d77a2cd91c3dedd930b1cf60ef396489f61eb45e304466cf3e67fa0af1ee7b04121bdea2",
  "0x6af0e0437ff400b6831e36d6bd17ffe48395dabc2d3435e77f76e17009241c5ee67992f72ec05f4c81084fbede3cc09"
)

{.experimental: "dynamicBindSym".}

macro frobConst(C: static Curve, pow: static int): untyped =
  return bindSym("FrobConst_" & $C & "_coef" & $pow)

template mulCheckSparse[Fp2](a: var Fp2, b: Fp2) =
  when b.c0.isZero().bool:
    a.mul_sparse_by_0y(b)
  elif b.c1.isZero().bool:
    a.mul_sparse_by_x0(b)
  else:
    a *= b

func frobenius_psi*[PointG2](r: var PointG2, P: PointG2) =
  ## "Untwist-Frobenius-Twist" endomorphism
  for coordR, coordP in fields(r, P):
    coordR.frobenius(coordP, 1)

  r.x.mulCheckSparse frobConst(PointG2.F.C, 2)
  r.y.mulCheckSparse frobConst(PointG2.F.C, 3)

# TODO: implement psi2.
#   - This saves of 3 Fp2 conjugate
#   - With nice sextic non residue like BLS12-381 (1+i)
#     the r.y coordinate is just a negation
# AFAIK there is no situation where we need psi2 without psi
# so the saving are comparing psi(psi(P)) vs psi2(P)
# assuming we will need to compute psi(P) in any case
