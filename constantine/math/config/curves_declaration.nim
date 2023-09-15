# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internal
  ./curves_parser_field

export CurveFamily, SexticTwist

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
# - proc family*(curve: static Curve): CurveFamily
#   which returns the curve family

declareCurves:
  # -----------------------------------------------------------------------------
  # Curves added when passed "-d:CTT_TEST_CURVES"
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
    modulus: "0xffffffffffffffffffffffffffffffff000000000000000000000001"
    order: "0xffffffffffffffffffffffffffff16a2e0b8f03e13dd29455c5c2a3d"
    orderBitwidth: 224

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
    nonresidue_fp: -1       #      -1   is not a square in 𝔽p
    nonresidue_fp2: (1, 1)  # 1+𝑖   1+𝑖  is not a square or cube in 𝔽p²

    embedding_degree: 12
    sexticTwist: D_Twist

  curve BN254_Snarks: # Zero-Knowledge proofs curve (SNARKS, STARKS, Ethereum)
    bitwidth: 254
    modulus: "0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47"
    family: BarretoNaehrig

    # G1 Equation: Y^2 = X^3 + 3
    # G2 Equation: Y^2 = X^3 + 3/(9+𝑖)
    order: "0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001"
    orderBitwidth: 254
    cofactor: 1
    eq_form: ShortWeierstrass
    coef_a: 0
    coef_b: 3
    nonresidue_fp: -1       #      -1   is not a square in 𝔽p
    nonresidue_fp2: (9, 1)  # 9+𝑖   9+𝑖  is not a square or cube in 𝔽p²

    embedding_degree: 12
    sexticTwist: D_Twist

  curve BabyJubjub: # Curve embedded in BN254_Snarks scalar field
    # https://iden3-docs.readthedocs.io/en/latest/_downloads/33717d75ab84e11313cc0d8a090b636f/Baby-Jubjub.pdf
    bitwidth: 254
    modulus: "0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001"

    # Montgomery form: y² = x³ + 168698x² + x
    # Edwards form: x² + y² = 1 + dx²y² with d=168696/168700
    order: "0x60c89ce5c263405370a08b6d0302b0bab3eedb83920ee0a677297dc392126f1"
    orderBitwidth: 251
    cofactor: 8
    # eq_form: Edwards
    coef_d: "0x1575bd81821016c07a5fd2dee78446612498beee8e01a829736c2b06fb281473"

  curve Jubjub: # Zcash Sapling curve embedded in BLS12-381 scalar field
    # https://z.cash/technology/jubjub/
    bitwidth: 255
    modulus: "0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001"
    # Montgomery form: y² = x³ + 40962x² + x
    # Twisted Edwards: ax² + y² = 1+dx²y² with a = -1 d=-10240/10241
    order: "0xe7db4ea6533afa906673b0101343b00a6682093ccc81082d0970e5ed6f72cb7"
    orderBitwidth: 252
    cofactor: 8
    eq_form: TwistedEdwards
    coef_a: -1
    coef_d: "0x2a9318e74bfa2b48f5fd9207e6bd7fd4292d7f6d37579d2601065fd6d6343eb1"

  curve Bandersnatch: # Anoma curve embedded in BLS12-381 scalar field
    # https://eprint.iacr.org/2021/1152
    bitwidth: 255
    modulus: "0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001"

    # Weierstrass form: y² = x³ − 3763200000x − 7867596800000
    # Mongomery form: By² = x³ + Ax² + x
    #   B=0x300c3385d13bedb7c9e229e185c4ce8b1dd3b71366bb97c30855c0aa41d62727
    #   A=0x4247698f4e32ad45a293959b4ca17afa4a2d2317e4c6ce5023e1f
    # Twisted Edwards form: −5x² + y² = 1 + dx²y²
    #   d = 138827208126141220649022263972958607803 / 171449701953573178309673572579671231137
    order: "0x1cfb69d4ca675f520cce760202687600ff8f87007419047174fd06b52876e7e1"
    orderBitwidth: 253
    cofactor: 4
    eq_form: TwistedEdwards
    coef_a: -5
    coef_d: "6389c12633c267cbc66e3bf86be3b6d8cb66677177e54f92b369f2f5188d58e7"

  curve Banderwagon: # Banderwagon is a prime subgroup constructed over the Bandersnatch Curve.
    # https://hackmd.io/@6iQDuIePQjyYBqDChYw_jg/BJBNcv9fq
    bitwidth: 255
    modulus: "0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001"

    # Weierstrass form: y² = x³ − 3763200000x − 7867596800000
    # Mongomery form: By² = x³ + Ax² + x
    #   B=0x300c3385d13bedb7c9e229e185c4ce8b1dd3b71366bb97c30855c0aa41d62727
    #   A=0x4247698f4e32ad45a293959b4ca17afa4a2d2317e4c6ce5023e1f
    # Twisted Edwards form: −5x² + y² = 1 + dx²y²
    #   d = 138827208126141220649022263972958607803 / 171449701953573178309673572579671231137
    order: "0x1cfb69d4ca675f520cce760202687600ff8f87007419047174fd06b52876e7e1"
    orderBitwidth: 253
    cofactor: 4
    eq_form: TwistedEdwards
    coef_a: -5
    coef_d: "6389c12633c267cbc66e3bf86be3b6d8cb66677177e54f92b369f2f5188d58e7"

  curve Edwards25519: # Bernstein curve
    bitwidth: 255
    modulus: "0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffed"

    # Montgomery form:            y² = x³ + 486662x² + x
    # Edwards form:          x² + y² = 1+dx²y²           with d = 121665/121666
    # Twisted Edwards form: ax² + y² = 1+dx²y²           with a = 121666 and d = 121665
    # or for use in Hisil, Wong, Carter, and Dawson extended coordinates
    #                       ax² + y² = 1+dx²y²           with a = -1 d=-121665/121666
    order: "0x1000000000000000000000000000000014def9dea2f79cd65812631a5cf5d3ed"
    orderBitwidth: 253
    cofactor: 8
    eq_form: TwistedEdwards
    coef_a: -1
    coef_d: "0x52036cee2b6ffe738cc740797779e89800700a4d4141d8ab75eb4dca135978a3"

  curve Pallas: # https://github.com/zcash/pasta
    bitwidth: 255
    modulus: "0x40000000000000000000000000000000224698fc094cf91b992d30ed00000001"
    order: "0x40000000000000000000000000000000224698fc0994a8dd8c46eb2100000001"
    orderBitwidth: 255
    eq_form: ShortWeierstrass
    coef_a: 0
    coef_b: 5
  curve Vesta: # https://github.com/zcash/pasta
    bitwidth: 255
    modulus: "0x40000000000000000000000000000000224698fc0994a8dd8c46eb2100000001"
    order: "0x40000000000000000000000000000000224698fc094cf91b992d30ed00000001"
    orderBitwidth: 255
    eq_form: ShortWeierstrass
    coef_a: 0
    coef_b: 5

  curve P256: # secp256r1 / NIST P-256
    bitwidth: 256
    modulus: "0xffffffff00000001000000000000000000000000ffffffffffffffffffffffff"
    order: "0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551"
    orderBitwidth: 256
  curve Secp256k1: # Bitcoin curve
    bitwidth: 256
    modulus: "0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f"
    order: "0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141"
    orderBitwidth: 256
    eq_form: ShortWeierstrass
    coef_a: 0
    coef_b: 7
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
    # G2 Equation: y² = x³ + 1/𝑗 with 𝑗 = √-5
    order: "0x12ab655e9a2ca55660b44d1e5c37b00159aa76fed00000010a11800000000001"
    orderBitwidth: 253
    eq_form: ShortWeierstrass
    coef_a: 0
    coef_b: 1
    nonresidue_fp: -5       #      -5   is not a square in 𝔽p
    nonresidue_fp2: (0, 1)  # √-5  √-5  is not a square or cube in 𝔽p²

    embedding_degree: 12
    sexticTwist: D_Twist

  curve BLS12_381:
    bitwidth: 381
    modulus: "0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab"
    family: BarretoLynnScott
    # u: -(2^63 + 2^62 + 2^60 + 2^57 + 2^48 + 2^16)

    # G1 Equation: y² = x³ + 4
    # G2 Equation: y² = x³ + 4 (1+i)
    order: "0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001"
    orderBitwidth: 255
    cofactor: "0x396c8c005555e1568c00aaab0000aaab"
    eq_form: ShortWeierstrass
    coef_a: 0
    coef_b: 4
    nonresidue_fp: -1       #      -1   is not a square in 𝔽p
    nonresidue_fp2: (1, 1)  # 1+𝑖   1+𝑖  is not a square or cube in 𝔽p²

    embedding_degree: 12
    sexticTwist: M_Twist

  curve BW6_761:
    bitwidth: 761
    modulus: "0x122e824fb83ce0ad187c94004faff3eb926186a81d14688528275ef8087be41707ba638e584e91903cebaff25b423048689c8ed12f9fd9071dcd3dc73ebff2e98a116c25667a8f8160cf8aeeaf0a437e6913e6870000082f49d00000000008b"
    family: BrezingWeng
    # Curve that embeds BLS12-377, see https://eprint.iacr.org/2020/351.pdf
    # u: 3 * 2^46 * (7 * 13 * 499) + 1
    # u: 0x8508c00000000001
    # r = p_BLS12-377 = (x⁶−2x⁵+2x³+x+1)/3
    # p = 103x¹²−379x¹¹+250x¹⁰+691x⁹−911x⁸−79x⁷+623x⁶−640x⁵+274x⁴+763x³+73x²+254x+229)/9

    # G1 Equation: y² = x³ - 1
    # G6 Equation: y² = x³ + 4 (M-Twist)
    order: "0x01ae3a4617c510eac63b05c06ca1493b1a22d9f300f5138f1ef3622fba094800170b5d44300000008508c00000000001"
    orderBitwidth: 377
    coef_a: 0
    coef_b: -1

    # TODO: rework the quad/cube/sextic non residue declaration
    nonresidue_fp: -4       # -4   is not a square or cube in 𝔽p
    nonresidue_fp2: (0, 1)  # -4   is not a cube in 𝔽p²

    embedding_degree: 6
    sexticTwist: M_Twist
