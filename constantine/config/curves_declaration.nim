# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internal
  ./curves_parser

export CurveFamily

# ############################################################
#
#           Configuration of finite fields
#
# ############################################################

# Curves & their corresponding finite fields are preconfigured in this file

# Note, in the past the convention was to name a curve by its conjectured security level.
# as this might change with advances in research, the new convention is
# to name curves according to the length of the prime bit length.
# i.e. the BN254 was previously named BN128.

# Curves security level were significantly impacted by
# advances in the Tower Number Field Sieve.
# in particular BN254 curve security dropped
# from estimated 128-bit to estimated 100-bit
# Barbulescu, R. and S. Duquesne, "Updating Key Size Estimations for Pairings",
# Journal of Cryptology, DOI 10.1007/s00145-018-9280-5, January 2018.

# Generates public:
# - type Curve* = enum
# - proc Mod*(curve: static Curve): auto
#   which returns the field modulus of the curve
# - proc Family*(curve: static Curve): CurveFamily
#   which returns the curve family
# - proc get_BN_param_u_BE*(curve: static Curve): array[N, byte]
#   which returns the "u" parameter of a BN curve
#   as a big-endian canonical integer representation
#   if it's a BN curve and u is positive
# - proc get_BN_param_6u_minus1_BE*(curve: static Curve): array[N, byte]
#   which returns the "6u-1" parameter of a BN curve
#   as a big-endian canonical integer representation
#   if it's a BN curve and u is positive.
#   This is used for optimized field inversion for BN curves

declareCurves:
  # -----------------------------------------------------------------------------
  # Curves added when passed "-d:testingCurves"
  curve Fake101:
    testingCurve: true
    bitwidth: 7
    modulus: "0x65" # 101 in hex
  curve Fake103: # 103 ≡ 3 (mod 4)
    testingCurve: true
    bitwidth: 7
    modulus: "0x67" # 103 in hex
  curve Fake10007: # 10007 ≡ 3 (mod 4)
    testingCurve: true
    bitwidth: 14
    modulus: "0x2717" # 10007 in hex
  curve Fake65519: # 65519 ≡ 3 (mod 4)
    testingCurve: true
    bitwidth: 16
    modulus: "0xFFEF" # 65519 in hex
  curve Mersenne61:
    testingCurve: true
    bitwidth: 61
    modulus: "0x1fffffffffffffff" # 2^61 - 1
  curve Mersenne127:
    testingCurve: true
    bitwidth: 127
    modulus: "0x7fffffffffffffffffffffffffffffff" # 2^127 - 1
  # -----------------------------------------------------------------------------
  curve P224: # NIST P-224
    bitwidth: 224
    modulus: "0xffffffff_ffffffff_ffffffff_ffffffff_00000000_00000000_00000001"
  curve BN254_Nogami: # Integer Variable χ–Based Ate Pairing, 2008, Nogami et al
    bitwidth: 254
    modulus: "0x2523648240000001ba344d80000000086121000000000013a700000000000013"
    family: BarretoNaehrig
    # Equation: Y^2 = X^3 + 2
    # u: -(2^62 + 2^55 + 1)

    order: "0x2523648240000001ba344d8000000007ff9f800000000010a10000000000000d"
    orderBitwidth: 254
    cofactor: 1
    eq_form: ShortWeierstrass
    coef_a: 0
    coef_b: 2
    nonresidue_quad_fp: -1       #      -1   is not a square in 𝔽p
    nonresidue_cube_fp2: (1, 1)  # 1+𝑖   1+𝑖  is not a cube in 𝔽p²

    sexticTwist: D_Twist
    sexticNonResidue_fp2: (1, 1) # 1+𝑖

  curve BN254_Snarks: # Zero-Knowledge proofs curve (SNARKS, STARKS, Ethereum)
    bitwidth: 254
    modulus: "0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47"
    family: BarretoNaehrig
    bn_u_bitwidth: 63
    bn_u: "0x44E992B44A6909F1" # u: 4965661367192848881
    cubicRootOfUnity_modP: "0x30644e72e131a0295e6dd9e7e0acccb0c28f069fbb966e3de4bd44e5607cfd48"
    # For sanity checks
    cubicRootOfUnity_modR: "0x30644e72e131a029048b6e193fd84104cc37a73fec2bc5e9b8ca0b2d36636f23"

    # G1 Equation: Y^2 = X^3 + 3
    # G2 Equation: Y^2 = X^3 + 3/(9+𝑖)
    order: "0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001"
    orderBitwidth: 254
    cofactor: 1
    eq_form: ShortWeierstrass
    coef_a: 0
    coef_b: 3
    nonresidue_quad_fp: -1       #      -1   is not a square in 𝔽p
    nonresidue_cube_fp2: (9, 1)  # 9+𝑖   9+𝑖  is not a cube in 𝔽p²

    sexticTwist: D_Twist
    sexticNonResidue_fp2: (9, 1) # 9+𝑖

  curve Curve25519: # Bernstein curve
    bitwidth: 255
    modulus: "0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffed"
  curve P256: # secp256r1 / NIST P-256
    bitwidth: 256
    modulus: "0xffffffff00000001000000000000000000000000ffffffffffffffffffffffff"
  curve Secp256k1: # Bitcoin curve
    bitwidth: 256
    modulus: "0xFFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFE FFFFFC2F"
  curve BLS12_377:
    # Zexe curve
    # (p41) https://eprint.iacr.org/2018/962.pdf
    # https://github.com/ethereum/EIPs/blob/41dea9615/EIPS/eip-2539.md
    bitwidth: 377
    modulus: "0x01ae3a4617c510eac63b05c06ca1493b1a22d9f300f5138f1ef3622fba094800170b5d44300000008508c00000000001"
    family: BarretoLynnScott
    # u: 3 * 2^46 * (7 * 13 * 499) + 1
    # u: 0x8508c00000000001

    # G1 Equation: y² = x³ + 1
    # G2 Equation: y² = x³ + 1/ with 𝑗 = √-5
    eq_form: ShortWeierstrass
    coef_a: 0
    coef_b: 1
    nonresidue_quad_fp: -5       #      -5   is not a square in 𝔽p
    nonresidue_cube_fp2: (0, 1)  # √-5  √-5  is not a cube in 𝔽p²

    sexticTwist: D_Twist
    sexticNonResidue_fp2: (0, 1) # √-5

  curve BLS12_381:
    bitwidth: 381
    modulus: "0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab"
    family: BarretoLynnScott
    # u: -(2^63 + 2^62 + 2^60 + 2^57 + 2^48 + 2^16)
    cubicRootOfUnity_mod_p: "0x1a0111ea397fe699ec02408663d4de85aa0d857d89759ad4897d29650fb85f9b409427eb4f49fffd8bfd00000000aaac"

    # G1 Equation: y² = x³ + 4
    # G2 Equation: y² = x³ + 4 (1+i)
    order: "0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001"
    orderBitwidth: 255
    cofactor: "0x396c8c005555e1568c00aaab0000aaab"
    eq_form: ShortWeierstrass
    coef_a: 0
    coef_b: 4
    nonresidue_quad_fp: -1       #      -1   is not a square in 𝔽p
    nonresidue_cube_fp2: (1, 1)  # 1+𝑖   1+𝑖  is not a cube in 𝔽p²

    sexticTwist: M_Twist
    sexticNonResidue_fp2: (1, 1) # 1+𝑖

  curve BN446:
    bitwidth: 446
    modulus: "0x2400000000000000002400000002d00000000d800000021c0000001800000000870000000b0400000057c00000015c000000132000000067"
    family: BarretoNaehrig
    # u = 2^110 + 2^36 + 1
  curve FKM12_447: # Fotiadis-Konstantinou-Martindale
    bitwidth: 447
    modulus: "0x4ce300001338c00001c08180000f20cfffffe5a8bffffd08a000000f228000007e8ffffffaddfffffffdc00000009efffffffca000000007"
    # TNFS Resistant Families of Pairing-Friendly Elliptic Curves
    # Georgios Fotiadis and Elisavet Konstantinou, 2018
    # https://eprint.iacr.org/2018/1017
    #
    # Family 17 choice b of
    # Optimal TNFS-secure pairings on elliptic curves with composite embedding degree
    # Georgios Fotiadis and Chloe Martindale, 2019
    # https://eprint.iacr.org/2019/555
    #
    # A short-list of pairing-friendly curves resistant toSpecial TNFS at the 128-bit security level
    # Aurore Guillevic
    # https://hal.inria.fr/hal-02396352v2/document
    #
    # p(x) = 1728x^6 + 2160x^5 + 1548x^4 + 756x^3 + 240x^2 + 54x + 7
    # t(x) = −6x² + 1,  r(x) = 36x^4 + 36x^3 + 18x^2 + 6x + 1.
    # Choice (b):u=−2^72 − 2^71 − 2^36
    #
    # Note the paper mentions 446-bit but it's 447
  curve BLS12_461:
    # Updating Key Size Estimations for Pairings
    # Barbulescu, R. and S. Duquesne, 2018
    # https://hal.archives-ouvertes.fr/hal-01534101/file/main.pdf
    bitwidth: 461
    modulus: "0x15555545554d5a555a55d69414935fbd6f1e32d8bacca47b14848b42a8dffa5c1cc00f26aa91557f00400020000555554aaaaaac0000aaaaaaab"
    # u = −2^77 + 2^50 + 2^33
    # p = (u - 1)^2 (u^4 - u^2 + 1)/3 + u

    # Note there is another BLS12-461 proposed here:
    # https://tools.ietf.org/id/draft-yonezawa-pairing-friendly-curves-00.html#rfc.section.4.2
  curve BN462:
    # Pairing-Friendly Curves
    # IETF Draft
    # https://tools.ietf.org/id/draft-irtf-cfrg-pairing-friendly-curves-02.html

    # Updating Key Size Estimations for Pairings
    # Barbulescu, R. and S. Duquesne, 2018
    # https://hal.archives-ouvertes.fr/hal-01534101/file/main.pdf
    bitwidth: 462
    modulus: "0x240480360120023ffffffffff6ff0cf6b7d9bfca0000000000d812908f41c8020ffffffffff6ff66fc6ff687f640000000002401b00840138013"
    family: BarretoNaehrig
    # u = 2^114 + 2^101 - 2^14 - 1
