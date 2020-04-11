# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  macros,
  # Internal
  ./curves_parser, ./common,
  ../arithmetic/[precomputed, bigints]

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

type
  CurveFamily* = enum
    NoFamily
    BarretoNaehrig # BN curve

declareCurves:
  # -----------------------------------------------------------------------------
  # Curves added when passed "-d:testingCurves"
  curve Fake101:
    testingCurve: true
    bitsize: 7
    modulus: "0x65" # 101 in hex
  curve Fake103: # 103 ≡ 3 (mod 4)
    testingCurve: true
    bitsize: 7
    modulus: "0x67" # 103 in hex
  curve Fake10007: # 10007 ≡ 3 (mod 4)
    testingCurve: true
    bitsize: 14
    modulus: "0x2717" # 10007 in hex
  curve Fake65519: # 65519 ≡ 3 (mod 4)
    testingCurve: true
    bitsize: 16
    modulus: "0xFFEF" # 65519 in hex
  curve Mersenne61:
    testingCurve: true
    bitsize: 61
    modulus: "0x1fffffffffffffff" # 2^61 - 1
  curve Mersenne127:
    testingCurve: true
    bitsize: 127
    modulus: "0x7fffffffffffffffffffffffffffffff" # 2^127 - 1
  # -----------------------------------------------------------------------------
  curve P224: # NIST P-224
    bitsize: 224
    modulus: "0xffffffff_ffffffff_ffffffff_ffffffff_00000000_00000000_00000001"
  curve BN254_Nogami: # Integer Variable χ–Based Ate Pairing, 2008, Nogami et al
    bitsize: 254
    modulus: "0x2523648240000001ba344d80000000086121000000000013a700000000000013"
    family: BarretoNaehrig
    # Equation: Y^2 = X^3 + 2
    # u: -(2^62 + 2^55 + 1)
  curve BN254_Snarks: # Zero-Knowledge proofs curve (SNARKS, STARKS, Ethereum)
    bitsize: 254
    modulus: "0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47"
    family: BarretoNaehrig
    bn_u_bitwidth: 63
    bn_u: "0x44E992B44A6909F1"
    # Equation: Y^2 = X^3 + 3
    # u: 4965661367192848881
  curve Curve25519: # Bernstein curve
    bitsize: 255
    modulus: "0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffed"
  curve P256: # secp256r1 / NIST P-256
    bitsize: 256
    modulus: "0xffffffff00000001000000000000000000000000ffffffffffffffffffffffff"
  curve Secp256k1: # Bitcoin curve
    bitsize: 256
    modulus: "0xFFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFE FFFFFC2F"
  curve BLS12_377:
    # Zexe curve
    # (p41) https://eprint.iacr.org/2018/962.pdf
    # https://github.com/ethereum/EIPs/blob/41dea9615/EIPS/eip-2539.md
    bitsize: 377
    modulus: "0x01ae3a4617c510eac63b05c06ca1493b1a22d9f300f5138f1ef3622fba094800170b5d44300000008508c00000000001"
    # u: 3 * 2^46 * (7 * 13 * 499) + 1
    # u: 0x8508c00000000001
  curve BLS12_381:
    bitsize: 381
    modulus: "0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab"
    # Equation: y^2 = x^3 + 4
    # u: -(2^63 + 2^62 + 2^60 + 2^57 + 2^48 + 2^16)
  curve BN446:
    bitsize: 446
    modulus: "0x2400000000000000002400000002d00000000d800000021c0000001800000000870000000b0400000057c00000015c000000132000000067"
    family: BarretoNaehrig
    # u = 2^110 + 2^36 + 1
  curve FKM12_447: # Fotiadis-Konstantinou-Martindale
    bitsize: 447
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
    bitsize: 461
    modulus: "0x15555545554d5a555a55d69414935fbd6f1e32d8bacca47b14848b42a8dffa5c1cc00f26aa91557f00400020000555554aaaaaac0000aaaaaaab"
    # u = −2^77 + 2^50 + 2^33
    # p = (u - 1)^2 (u^4 - u^2 + 1)/3 + u
  curve BN462:
    # Pairing-Friendly Curves
    # IETF Draft
    # https://tools.ietf.org/id/draft-irtf-cfrg-pairing-friendly-curves-02.html

    # Updating Key Size Estimations for Pairings
    # Barbulescu, R. and S. Duquesne, 2018
    # https://hal.archives-ouvertes.fr/hal-01534101/file/main.pdf
    bitsize: 462
    modulus: "0x240480360120023ffffffffff6ff0cf6b7d9bfca0000000000d812908f41c8020ffffffffff6ff66fc6ff687f640000000002401b00840138013"
    family: BarretoNaehrig
    # u = 2^114 + 2^101 - 2^14 - 1

# ############################################################
#
#                        Twists
#
# ############################################################

type SexticTwist* = enum
  ## The sectic twist type of the current elliptic curve
  ##
  ## Assuming a standard curve `E` over the prime field `𝔽p`
  ## denoted `E(𝔽p)` in Short Weierstrass form
  ##   y² = x³ + Ax + B
  ##
  ## If E(𝔽p^k), the elliptic curve defined over the extension field
  ## of degree k, the embedding degree, admits an isomorphism
  ## to a curve E'(Fp^(k/d)), we call E' a twisted curve.
  ##
  ## For pairing they have the following equation
  ##   y² = x³ + Ax/µ² + B/µ³ for a D-Twist (Divisor)
  ## or
  ##   y² = x³ + µ²Ax + µ³B for a M-Twist (Multiplicand)
  ## with the polynomial x^k - µ being irreducible.
  ##
  ## i.e. if d == 2, E' is a quadratic twist and µ is a quadratic non-residue
  ## if d == 4, E' is a quartic twist
  ## if d == 6, E' is a sextic twist
  ##
  ## References:
  ## - Efficient Pairings on Twisted Elliptic Curve
  ##   Yasuyuki Nogami, Masataka Akane, Yumi Sakemi and Yoshitaka Morikawa, 2010
  ##   https://www.researchgate.net/publication/221908359_Efficient_Pairings_on_Twisted_Elliptic_Curve
  ##
  ## - A note on twists for pairing friendly curves\
  ##   Michael Scott, 2009\
  ##   http://indigo.ie/~mscott/twists.pdf
  NotTwisted
  D_Twist
  M_Twist

# ############################################################
#
#                  Curve characteristics
#
# ############################################################

{.experimental: "dynamicBindSym".}

macro Mod*(C: static Curve): untyped =
  ## Get the Modulus associated to a curve
  result = bindSym($C & "_Modulus")

func getCurveBitSize*(C: static Curve): static int =
  ## Returns the number of bits taken by the curve modulus
  result = static(CurveBitSize[C])

template matchingBigInt*(C: static Curve): untyped =
  BigInt[CurveBitSize[C]]

func family*(C: static Curve): CurveFamily =
  result = static(CurveFamilies[C])

# ############################################################
#
#  Autogeneration of precomputed constants in ROM
#
# ############################################################

macro genConstants(): untyped =
  ## Store
  ## - the Montgomery magic constant "R^2 mod N" in ROM
  ##   For each curve under the private symbol "MyCurve_R2modP"
  ## - the Montgomery magic constant -1/P mod 2^WordBitSize
  ##   For each curve under the private symbol "MyCurve_NegInvModWord
  ## - ...
  result = newStmtList()

  template used(name: string): NimNode =
    nnkPragmaExpr.newTree(
      ident(name),
      nnkPragma.newTree(ident"used")
    )

  for curve in Curve.low .. Curve.high:
    # const MyCurve_CanUseNoCarryMontyMul = useNoCarryMontyMul(MyCurve_Modulus)
    result.add newConstStmt(
      used($curve & "_CanUseNoCarryMontyMul"), newCall(
        bindSym"useNoCarryMontyMul",
        bindSym($curve & "_Modulus")
      )
    )

    # const MyCurve_CanUseNoCarryMontySquare = useNoCarryMontySquare(MyCurve_Modulus)
    result.add newConstStmt(
      used($curve & "_CanUseNoCarryMontySquare"), newCall(
        bindSym"useNoCarryMontySquare",
        bindSym($curve & "_Modulus")
      )
    )

    # const MyCurve_R2modP = r2mod(MyCurve_Modulus)
    result.add newConstStmt(
      used($curve & "_R2modP"), newCall(
        bindSym"r2mod",
        bindSym($curve & "_Modulus")
      )
    )

    # const MyCurve_NegInvModWord = negInvModWord(MyCurve_Modulus)
    result.add newConstStmt(
      used($curve & "_NegInvModWord"), newCall(
        bindSym"negInvModWord",
        bindSym($curve & "_Modulus")
      )
    )
    # const MyCurve_montyOne = montyOne(MyCurve_Modulus)
    result.add newConstStmt(
      used($curve & "_MontyOne"), newCall(
        bindSym"montyOne",
        bindSym($curve & "_Modulus")
      )
    )
    # const MyCurve_MontyPrimeMinus1 = montyPrimeMinus1(MyCurve_Modulus)
    result.add newConstStmt(
      used($curve & "_MontyPrimeMinus1"), newCall(
        bindSym"montyPrimeMinus1",
        bindSym($curve & "_Modulus")
      )
    )
    # const MyCurve_InvModExponent = primeMinus2_BE(MyCurve_Modulus)
    result.add newConstStmt(
      used($curve & "_InvModExponent"), newCall(
        bindSym"primeMinus2_BE",
        bindSym($curve & "_Modulus")
      )
    )
    # const MyCurve_PrimePlus1div2 = primePlus1div2(MyCurve_Modulus)
    result.add newConstStmt(
      used($curve & "_PrimePlus1div2"), newCall(
        bindSym"primePlus1div2",
        bindSym($curve & "_Modulus")
      )
    )
    # const MyCurve_PrimeMinus1div2_BE = primeMinus1div2_BE(MyCurve_Modulus)
    result.add newConstStmt(
      used($curve & "_PrimeMinus1div2_BE"), newCall(
        bindSym"primeMinus1div2_BE",
        bindSym($curve & "_Modulus")
      )
    )
    # const MyCurve_PrimeMinus3div4_BE = primeMinus3div4_BE(MyCurve_Modulus)
    result.add newConstStmt(
      used($curve & "_PrimeMinus3div4_BE"), newCall(
        bindSym"primeMinus3div4_BE",
        bindSym($curve & "_Modulus")
      )
    )
    # const MyCurve_PrimePlus1div4_BE = primePlus1div4_BE(MyCurve_Modulus)
    result.add newConstStmt(
      used($curve & "_PrimePlus1div4_BE"), newCall(
        bindSym"primePlus1div4_BE",
        bindSym($curve & "_Modulus")
      )
    )

    if CurveFamilies[curve] == BarretoNaehrig:
      # when declared(MyCurve_BN_param_u):
      #   const MyCurve_BN_u_BE = toCanonicalIntRepr(MyCurve_BN_param_u)
      #   const MyCurve_BN_6u_minus_1_BE = bn_6u_minus_1_BE(MyCurve_BN_param_u)
      var bnStmts = newStmtList()
      bnStmts.add newConstStmt(
        used($curve & "_BN_u_BE"), newCall(
          bindSym"toCanonicalIntRepr",
          ident($curve & "_BN_param_u")
        )
      )
      bnStmts.add newConstStmt(
        used($curve & "_BN_6u_minus_1_BE"), newCall(
          bindSym"bn_6u_minus_1_BE",
          ident($curve & "_BN_param_u")
        )
      )

      result.add nnkWhenStmt.newTree(
        nnkElifBranch.newTree(
          newCall(ident"declared", ident($curve & "_BN_param_u")),
          bnStmts
        )
      )

genConstants()

macro canUseNoCarryMontyMul*(C: static Curve): untyped =
  ## Returns true if the Modulus is compatible with a fast
  ## Montgomery multiplication that avoids many carries
  result = bindSym($C & "_CanUseNoCarryMontyMul")

macro canUseNoCarryMontySquare*(C: static Curve): untyped =
  ## Returns true if the Modulus is compatible with a fast
  ## Montgomery squaring that avoids many carries
  result = bindSym($C & "_CanUseNoCarryMontySquare")

macro getR2modP*(C: static Curve): untyped =
  ## Get the Montgomery "R^2 mod P" constant associated to a curve field modulus
  result = bindSym($C & "_R2modP")

macro getNegInvModWord*(C: static Curve): untyped =
  ## Get the Montgomery "-1/P[0] mod 2^WordBitSize" constant associated to a curve field modulus
  result = bindSym($C & "_NegInvModWord")

macro getMontyOne*(C: static Curve): untyped =
  ## Get one in Montgomery representation (i.e. R mod P)
  result = bindSym($C & "_MontyOne")

macro getMontyPrimeMinus1*(C: static Curve): untyped =
  ## Get (P+1) / 2 for an odd prime
  result = bindSym($C & "_MontyPrimeMinus1")

macro getInvModExponent*(C: static Curve): untyped =
  ## Get modular inversion exponent (Modulus-2 in canonical representation)
  result = bindSym($C & "_InvModExponent")

macro getPrimePlus1div2*(C: static Curve): untyped =
  ## Get (P+1) / 2 for an odd prime
  ## Warning ⚠️: Result in canonical domain (not Montgomery)
  result = bindSym($C & "_PrimePlus1div2")

macro getPrimeMinus1div2_BE*(C: static Curve): untyped =
  ## Get (P-1) / 2 in big-endian serialized format
  result = bindSym($C & "_PrimeMinus1div2_BE")

macro getPrimeMinus3div4_BE*(C: static Curve): untyped =
  ## Get (P-3) / 2 in big-endian serialized format
  result = bindSym($C & "_PrimeMinus3div4_BE")

macro getPrimePlus1div4_BE*(C: static Curve): untyped =
  ## Get (P+1) / 4 for an odd prime in big-endian serialized format
  result = bindSym($C & "_PrimePlus1div4_BE")

# Family specific
# -------------------------------------------------------
macro canUseFast_BN_Inversion*(C: static Curve): untyped =
  ## A BN curve can use the fast BN inversion if the parameter "u" is positive
  if CurveFamilies[C] != BarretoNaehrig:
    return newLit false
  return bindSym($C & "_BN_can_use_fast_inversion")

macro getBN_param_u_BE*(C: static Curve): untyped =
  ## Get the ``u`` parameter of a BN curve in canonical big-endian representation
  result = bindSym($C & "_BN_u_BE")

macro getBN_param_6u_minus_1_BE*(C: static Curve): untyped =
  ## Get the ``6u-1`` from the ``u`` parameter
  ## of a BN curve in canonical big-endian representation
  result = bindSym($C & "_BN_6u_minus_1_BE")

# ############################################################
#
#                Debug info printed at compile-time
#
# ############################################################

macro debugConsts(): untyped {.used.} =
  let curves = bindSym("Curve")
  let E = curves.getImpl[2]

  result = newStmtList()
  for i in 1 ..< E.len:
    let curve = E[i]
    let curveName = $curve
    let modulus = bindSym(curveName & "_Modulus")
    let r2modp = bindSym(curveName & "_R2modP")
    let negInvModWord = bindSym(curveName & "_NegInvModWord")

    result.add quote do:
      echo "Curve ", `curveName`,':'
      echo "  Field Modulus:                 ", `modulus`
      echo "  Montgomery R² (mod P):         ", `r2modp`
      echo "  Montgomery -1/P[0] (mod 2^", WordBitWidth, "): ", `negInvModWord`
  result.add quote do:
    echo "----------------------------------------------------------------------------"

# debug: # displayed with -d:debugConstantine
#   debugConsts()
