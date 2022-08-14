# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/curves,
  ../io/[io_fields, io_extfields]

{.used.}

# Hash-to-Curve Shallue-van de Woestijne (SVDW) BLS12_381 G2 map
# -----------------------------------------------------------------
# Spec:
# - https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-14#appendix-F.1
# This map is slower than SSWU 

const BLS12_381_h2c_svdw_G2_Z* = Fp2[BLS12_381].fromHex( 
  "0x0",
  "0x1"
)
const BLS12_381_h2c_svdw_G2_curve_eq_rhs_Z* = Fp2[BLS12_381].fromHex( 
  "0x4",
  "0x3"
)
const BLS12_381_h2c_svdw_G2_minus_Z_div_2* = Fp2[BLS12_381].fromHex( 
  "0x0",
  "0xd0088f51cbff34d258dd3db21a5d66bb23ba5c279c2895fb39869507b587b120f55ffff58a9ffffdcff7fffffffd555"
)
const BLS12_381_h2c_svdw_G2_z3* = Fp2[BLS12_381].fromHex( 
  "0xbdd5ce0da1f67a74801737ad294eb2e8792dfaff3b97d438795e114a0bf9b0d448554f8291ae6ae6f9aad7ac97e0842",
  "0x154a803c6f0a66f3f4bd964d1db96c49c5807ce89e413640c752821cda0b2d1c809f1c51d940f78f4bdd8f28edd47488"
)
const BLS12_381_h2c_svdw_G2_z4* = Fp2[BLS12_381].fromHex( 
  "0x11560bf17baa99bc32126fced787c88f984f87adf7ae0c7f9a208c6b4f20a4181472aaa9cb8d555526a9ffffffffc722",
  "0x4"
)


# Hash-to-Curve Simplified Shallue-van de Woestijne-Ulas (SSWU) map
# -----------------------------------------------------------------

# Hash-to-Curve map to isogenous BLS12-381 E'2 constants
# -----------------------------------------------------------------
#
# y² = x³ + A'*x + B' with p² = q ≡ 9 (mod 16), p the BLS12-381 characteristic (base modulus)
#
# Hardcoding from spec:
# - https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-11#section-8.8.2
# - https://github.com/cfrg/draft-irtf-cfrg-hash-to-curve/blob/f7dd3761/poc/sswu_opt_9mod16.sage#L142-L148

const BLS12_381_h2c_sswu_G2_Aprime_E2* = Fp2[BLS12_381].fromHex(  # 240𝑖
  "0x0",
  "0xf0"
)
const BLS12_381_h2c_sswu_G2_Bprime_E2* = Fp2[BLS12_381].fromHex(  # 1012 * (1 + 𝑖)
  "0x3f4",
  "0x3f4"
)
const BLS12_381_h2c_sswu_G2_Z* = Fp2[BLS12_381].fromHex(  # -(2 + 𝑖)
  "0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaa9",
  "0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaaa"
)
const BLS12_381_h2c_sswu_G2_minus_A* = Fp2[BLS12_381].fromHex(  # -240𝑖
  "0x0",
  "0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffa9bb"
)
const BLS12_381_h2c_sswu_G2_ZmulA* = Fp2[BLS12_381].fromHex(  # Z*A = 240-480𝑖
  "0xf0",
  "0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffa8cb"
)
const BLS12_381_h2c_sswu_G2_inv_Z3* = Fp2[BLS12_381].fromHex(  # 1/Z³
  "0xec5373b4fc387140dfd46af348f55e2ca7901ef5b371b085d6da6bdbb39819171ad78d43fdbbe76a0f1189374bc3a07",
  "0x9c70eed928c402db9efc63a4a7484928607fdacdea2acefe74fcc1fd9af14de7a1fe76c0d6d687295ce78d4fdf39630"
)
const BLS12_381_h2c_sswu_G2_squared_norm_inv_Z3* = Fp[BLS12_381].fromHex(  # ||1/Z³||²
  "0x59ded5774de2fc31e8f3083875e2b7a4cff24cacc26fbdb84e195f19dbbba49567f439538bc20c48c86f3b645a1b852")
const BLS12_381_h2c_sswu_G2_inv_norm_inv_Z3* = Fp[BLS12_381].fromHex(  # 1/||1/Z³||
  "0x810e5a23cbb86fd12ded1af502287a397ed25c1d6fe0444e38c48e9c7ddb3c27cfebdd464e90f201fda0eb6983f2533")


# Hash-to-Curve 3-isogeny map BLS12-381 E'2 constants
# -----------------------------------------------------------------
#
# The polynomials map a point (x', y') on the isogenous curve E'2
# to (x, y) on E2, represented as (xnum/xden, y' * ynum/yden)

const BLS12_381_h2c_sswu_G2_isogeny_map_xnum* = [
  # Polynomial k₀ + k₁ x + k₂ x² + k₃ x³ + ... + kₙ xⁿ
  # The polynomial is stored as an array of coefficients ordered from k₀ to kₙ

  # 1
  Fp2[BLS12_381].fromHex(
    "0x5c759507e8e333ebb5b7a9a47d7ed8532c52d39fd3a042a88b58423c50ae15d5c2638e343d9c71c6238aaaaaaaa97d6",
    "0x5c759507e8e333ebb5b7a9a47d7ed8532c52d39fd3a042a88b58423c50ae15d5c2638e343d9c71c6238aaaaaaaa97d6"
  ),
  # x
  Fp2[BLS12_381].fromHex(
    "0x0",
    "0x11560bf17baa99bc32126fced787c88f984f87adf7ae0c7f9a208c6b4f20a4181472aaa9cb8d555526a9ffffffffc71a"
  ),
  # x²
  Fp2[BLS12_381].fromHex(
    "0x11560bf17baa99bc32126fced787c88f984f87adf7ae0c7f9a208c6b4f20a4181472aaa9cb8d555526a9ffffffffc71e",
    "0x8ab05f8bdd54cde190937e76bc3e447cc27c3d6fbd7063fcd104635a790520c0a395554e5c6aaaa9354ffffffffe38d"
  ),
  # x³
  Fp2[BLS12_381].fromHex(
    "0x171d6541fa38ccfaed6dea691f5fb614cb14b4e7f4e810aa22d6108f142b85757098e38d0f671c7188e2aaaaaaaa5ed1",
    "0x0"
  )
]
const BLS12_381_h2c_sswu_G2_isogeny_map_xden* = [
  # Polynomial k₀ + k₁ x + k₂ x² + k₃ x³ + ... + kₙ xⁿ
  # The polynomial is stored as an array of coefficients ordered from k₀ to kₙ

  # 1
  Fp2[BLS12_381].fromHex(
    "0x0",
    "0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaa63"
  ),
  # x
  Fp2[BLS12_381].fromHex(
    "0xc",
    "0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaa9f"
  ),
  # x²
  Fp2[BLS12_381].fromHex(
    "0x1",
    "0x0"
  )
]
const BLS12_381_h2c_sswu_G2_isogeny_map_ynum* = [
  # Polynomial k₀ + k₁ x + k₂ x² + k₃ x³ + ... + kₙ xⁿ
  # The polynomial is stored as an array of coefficients ordered from k₀ to kₙ

  # y
  Fp2[BLS12_381].fromHex(
    "0x1530477c7ab4113b59a4c18b076d11930f7da5d4a07f649bf54439d87d27e500fc8c25ebf8c92f6812cfc71c71c6d706",
    "0x1530477c7ab4113b59a4c18b076d11930f7da5d4a07f649bf54439d87d27e500fc8c25ebf8c92f6812cfc71c71c6d706"
  ),
  # x*y
  Fp2[BLS12_381].fromHex(
    "0x0",
    "0x5c759507e8e333ebb5b7a9a47d7ed8532c52d39fd3a042a88b58423c50ae15d5c2638e343d9c71c6238aaaaaaaa97be"
  ),
  # x²*y
  Fp2[BLS12_381].fromHex(
    "0x11560bf17baa99bc32126fced787c88f984f87adf7ae0c7f9a208c6b4f20a4181472aaa9cb8d555526a9ffffffffc71c",
    "0x8ab05f8bdd54cde190937e76bc3e447cc27c3d6fbd7063fcd104635a790520c0a395554e5c6aaaa9354ffffffffe38f"
  ),
  # x³*y
  Fp2[BLS12_381].fromHex(
    "0x124c9ad43b6cf79bfbf7043de3811ad0761b0f37a1e26286b0e977c69aa274524e79097a56dc4bd9e1b371c71c718b10",
    "0x0"
  )
]
const BLS12_381_h2c_sswu_G2_isogeny_map_yden* = [
  # Polynomial k₀ + k₁ x + k₂ x² + k₃ x³ + ... + kₙ xⁿ
  # The polynomial is stored as an array of coefficients ordered from k₀ to kₙ

  # 1
  Fp2[BLS12_381].fromHex(
    "0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffa8fb",
    "0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffa8fb"
  ),
  # x
  Fp2[BLS12_381].fromHex(
    "0x0",
    "0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffa9d3"
  ),
  # x²
  Fp2[BLS12_381].fromHex(
    "0x12",
    "0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaa99"
  ),
  # x³
  Fp2[BLS12_381].fromHex(
    "0x1",
    "0x0"
  )
]
