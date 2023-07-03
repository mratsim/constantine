# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ../platforms/[abstractions, views],
  ../math/config/curves,
  ../math/[arithmetic, extension_fields],
  ../math/constants/[zoo_hash_to_curve, zoo_subgroups],
  ../math/ec_shortweierstrass,
  ./h2c_hash_to_field,
  ./h2c_map_to_isocurve_swu,
  ./h2c_isogeny_maps,
  ./h2c_utilities,
  ../hashes

export abstractions, arithmetic # generic sandwich

# ############################################################
#
#                Hashing to Elliptic Curve
#
# ############################################################

# Normative references
# - https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-11
# - https://github.com/cfrg/draft-irtf-cfrg-hash-to-curve

# No exceptions allowed in core cryptographic operations
{.push raises: [].}

# Map to curve
# ----------------------------------------------------------------

func mapToCurve_svdw[F, G](
       r: var ECP_ShortW_Aff[F, G],
       u: F) =
  ## Deterministically map a field element u
  ## to an elliptic curve point `r`
  ## https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-14#section-6.6.1

  var
    tv1 {.noInit.}, tv2{.noInit.}, tv3{.noInit.}: F
    tv4{.noInit.}: F
    x1{.noInit.}, x2{.noInit.}: F
    gx1{.noInit.}, gx2{.noInit.}: F

  tv1.square(u)
  tv1 *= h2cConst(F.C, svdw, G, curve_eq_rhs_Z)
  tv2 = tv1
  when F is Fp:
    tv2 += F(mres: F.getMontyOne())
    tv1.diff(F(mres: F.getMontyOne()), tv1)
  else:
    tv2.c0 += Fp[F.F.C](mres: Fp[F.F.C].getMontyOne())
    tv1.c0.diff(Fp[F.F.C](mres: Fp[F.F.C].getMontyOne()), tv1.c0)
    tv1.c1.neg()
  tv3.prod(tv1, tv2)
  tv3.inv()

  tv4.prod(u, tv1)
  tv4 *= tv3
  tv4.mulCheckSparse(h2cConst(F.C, svdw, G, z3))

  x1.diff(h2cConst(F.C, svdw, G, minus_Z_div_2), tv4)
  x2.sum(h2cConst(F.C, svdw, G, minus_Z_div_2), tv4)
  r.x.square(tv2)
  r.x *= tv3
  r.x.square()
  r.x *= h2cConst(F.C, svdw, G, z4)
  r.x += h2cConst(F.C, svdw, G, Z)

  # x³+ax+b
  gx1.curve_eq_rhs(x1, G)
  gx2.curve_eq_rhs(x2, G)

  let e1 = gx1.isSquare()
  let e2 = gx2.isSquare() and not e1

  r.x.ccopy(x1, e1)
  r.x.ccopy(x2, e2)

  r.y.curve_eq_rhs(r.x, G)
  r.y.sqrt()

  r.y.cneg(sgn0(u) xor sgn0(r.y))

func mapToIsoCurve_sswuG1_opt3mod4[F](
       r: var ECP_ShortW_Jac[F, G1],
       u: F) =
  var
    xn{.noInit.}, xd{.noInit.}: F
    yn{.noInit.}: F
    xd3{.noInit.}: F

  mapToIsoCurve_sswuG1_opt3mod4(
    xn, xd,
    yn,
    u, xd3)

  # Convert to Jacobian
  r.z = xd          # Z = xd
  r.x.prod(xn, xd)  # X = xZ² = xn/xd * xd² = xn*xd
  r.y.prod(yn, xd3) # Y = yZ³ = yn * xd³

func mapToIsoCurve_sswuG2_opt9mod16[F](
       r: var ECP_ShortW_Jac[F, G2],
       u: F) =
  var
    xn{.noInit.}, xd{.noInit.}: F
    yn{.noInit.}: F
    xd3{.noInit.}: F

  mapToIsoCurve_sswuG2_opt9mod16(
    xn, xd,
    yn,
    u, xd3)

  # Convert to Jacobian
  r.z = xd          # Z = xd
  r.x.prod(xn, xd)  # X = xZ² = xn/xd * xd² = xn*xd
  r.y.prod(yn, xd3) # Y = yZ³ = yn * xd³

func mapToCurve_svdw_fusedAdd[F; G: static Subgroup](
       r: var ECP_ShortW_Jac[F, G],
       u0, u1: F) =
  ## Map 2 elements of the
  ## finite or extension field F
  ## to an elliptic curve E
  ## and add them
  var Q0{.noInit.}, Q1{.noInit.}: ECP_ShortW_Aff[F, G]
  Q0.mapToCurve_svdw(u0)
  Q1.mapToCurve_svdw(u1)

  r.fromAffine(Q0)
  r += Q1

func mapToCurve_sswu_fusedAdd[F; G: static Subgroup](
       r: var ECP_ShortW_Jac[F, G],
       u0, u1: F) =
  ## Map 2 elements of the
  ## finite or extension field F
  ## to an elliptic curve E
  ## and add them
  # Optimization suggested in https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-11#section-6.6.3
  #   Note that iso_map is a group homomorphism, meaning that point
  #   addition commutes with iso_map.  Thus, when using this mapping in the
  #   hash_to_curve construction of Section 3, one can effect a small
  #   optimization by first mapping u0 and u1 to E', adding the resulting
  #   points on E', and then applying iso_map to the sum.  This gives the
  #   same result while requiring only one evaluation of iso_map.

  # Jacobian formulae are independent of the curve equation B'
  # y² = x³ + A'*x + B'
  # unlike the complete projective formulae which heavily depends on it
  # So we use jacobian coordinates for computation on isogenies.

  when F.C.getCoefA() * F.C.getCoefB() == 0:
    # https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-11#section-6.6.3
    # Simplified Shallue-van de Woestijne-Ulas method for AB == 0

    var Q0{.noInit.}, Q1{.noInit.}: ECP_ShortW_Jac[F, G]

    # 1. Map to E' isogenous to E
    when F is Fp and F.C.has_P_3mod4_primeModulus():
      # 1. Map to E'1 isogenous to E1
      Q0.mapToIsoCurve_sswuG1_opt3mod4(u0)
      Q1.mapToIsoCurve_sswuG1_opt3mod4(u1)
      Q0.sum(Q0, Q1, h2CConst(F.C, sswu, G1, Aprime_E1))
    elif F is Fp2 and F.C.has_Psquare_9mod16_primePower():
      # 1. Map to E'2 isogenous to E2
      Q0.mapToIsoCurve_sswuG2_opt9mod16(u0)
      Q1.mapToIsoCurve_sswuG2_opt9mod16(u1)
      Q0.sum(Q0, Q1, h2CConst(F.C, sswu, G2, Aprime_E2))
    else:
      {.error: "Not implemented".}

    # 2. Map from E'2 to E2
    r.h2c_isogeny_map(Q0)
  else:
    {.error: "Not implemented".}

# Hash to curve
# ----------------------------------------------------------------

func hashToCurve_svdw*[F; G: static Subgroup](
       H: type CryptoHash,
       k: static int,
       output: var ECP_ShortW_Jac[F, G],
       augmentation: openArray[byte],
       message: openArray[byte],
       domainSepTag: openArray[byte]) {.genCharAPI.} =
  ## Hash a message to an elliptic curve
  ##
  ## Arguments:
  ## - `Hash` a cryptographic hash function.
  ##   - `Hash` MAY be a Merkle-Damgaard hash function like SHA-2
  ##   - `Hash` MAY be a sponge-based hash function like SHA-3 or BLAKE2
  ##   - Otherwise, H MUST be a hash function that has been proved
  ##    indifferentiable from a random oracle [MRH04] under a reasonable
  ##    cryptographic assumption.
  ## - k the security parameter of the suite in bits (for example 128)
  ## - `output`, an elliptic curve point that will be overwritten.
  ## - `augmentation`, an optional augmentation to the message. This will be prepended,
  ##   prior to hashing.
  ##   This is used for building the "message augmentation" variant of BLS signatures
  ##   https://www.ietf.org/archive/id/draft-irtf-cfrg-bls-signature-05.html#section-3.2
  ##   which requires `CoreSign(SK, PK || message)`
  ##   and `CoreVerify(PK, PK || message, signature)`
  ## - `message` is the message to hash
  ## - `domainSepTag` is the protocol domain separation tag (DST).

  var u{.noInit.}: array[2, F]
  if domainSepTag.len <= 255:
    H.hashToField(k, u, augmentation, message, domainSepTag)
  else:
    const N = H.type.digestSize()
    var dst {.noInit.}: array[N, byte]
    H.shortDomainSepTag(dst, domainSepTag)
    H.hashToField(k, u, augmentation, message, dst)

  output.mapToCurve_svdw_fusedAdd(u[0], u[1])
  output.clearCofactor()

func hashToCurve_sswu*[F; G: static Subgroup](
       H: type CryptoHash,
       k: static int,
       output: var ECP_ShortW_Jac[F, G],
       augmentation: openArray[byte],
       message: openArray[byte],
       domainSepTag: openArray[byte]) {.genCharAPI.} =
  ## Hash a message to an elliptic curve
  ##
  ## Arguments:
  ## - `Hash` a cryptographic hash function.
  ##   - `Hash` MAY be a Merkle-Damgaard hash function like SHA-2
  ##   - `Hash` MAY be a sponge-based hash function like SHA-3 or BLAKE2
  ##   - Otherwise, H MUST be a hash function that has been proved
  ##    indifferentiable from a random oracle [MRH04] under a reasonable
  ##    cryptographic assumption.
  ## - k the security parameter of the suite in bits (for example 128)
  ## - `output`, an elliptic curve point that will be overwritten.
  ## - `augmentation`, an optional augmentation to the message. This will be prepended,
  ##   prior to hashing.
  ##   This is used for building the "message augmentation" variant of BLS signatures
  ##   https://www.ietf.org/archive/id/draft-irtf-cfrg-bls-signature-05.html#section-3.2
  ##   which requires `CoreSign(SK, PK || message)`
  ##   and `CoreVerify(PK, PK || message, signature)`
  ## - `message` is the message to hash
  ## - `domainSepTag` is the protocol domain separation tag (DST).

  var u{.noInit.}: array[2, F]
  if domainSepTag.len <= 255:
    H.hashToField(k, u, augmentation, message, domainSepTag)
  else:
    const N = H.type.digestSize()
    var dst {.noInit.}: array[N, byte]
    H.shortDomainSepTag(dst, domainSepTag)
    H.hashToField(k, u, augmentation, message, dst)

  output.mapToCurve_sswu_fusedAdd(u[0], u[1])
  output.clearCofactor()

func hashToCurve*[F; G: static Subgroup](
       H: type CryptoHash,
       k: static int,
       output: var ECP_ShortW_Jac[F, G],
       augmentation: openArray[byte],
       message: openArray[byte],
       domainSepTag: openArray[byte]) {.inline, genCharAPI.} =
  ## Hash a message to an elliptic curve
  ##
  ## Arguments:
  ## - `Hash` a cryptographic hash function.
  ##   - `Hash` MAY be a Merkle-Damgaard hash function like SHA-2
  ##   - `Hash` MAY be a sponge-based hash function like SHA-3 or BLAKE2
  ##   - Otherwise, H MUST be a hash function that has been proved
  ##    indifferentiable from a random oracle [MRH04] under a reasonable
  ##    cryptographic assumption.
  ## - k the security parameter of the suite in bits (for example 128)
  ## - `output`, an elliptic curve point that will be overwritten.
  ## - `augmentation`, an optional augmentation to the message. This will be prepended,
  ##   prior to hashing.
  ##   This is used for building the "message augmentation" variant of BLS signatures
  ##   https://www.ietf.org/archive/id/draft-irtf-cfrg-bls-signature-05.html#section-3.2
  ##   which requires `CoreSign(SK, PK || message)`
  ##   and `CoreVerify(PK, PK || message, signature)`
  ## - `message` is the message to hash
  ## - `domainSepTag` is the protocol domain separation tag (DST).
  when F.C == BLS12_381:
    hashToCurve_sswu(H, k, output,
      augmentation, message, domainSepTag)
  elif F.C == BN254_Snarks:
    hashToCurve_svdw(H, k, output,
      augmentation, message, domainSepTag)
  else:
    {.error: "Not implemented".}

func hashToCurve*[F; G: static Subgroup](
       H: type CryptoHash,
       k: static int,
       output: var (ECP_ShortW_Prj[F, G] or ECP_ShortW_Aff[F, G]),
       augmentation: openArray[byte],
       message: openArray[byte],
       domainSepTag: openArray[byte]) {.inline, genCharAPI.} =
  ## Hash a message to an elliptic curve
  ##
  ## Arguments:
  ## - `Hash` a cryptographic hash function.
  ##   - `Hash` MAY be a Merkle-Damgaard hash function like SHA-2
  ##   - `Hash` MAY be a sponge-based hash function like SHA-3 or BLAKE2
  ##   - Otherwise, H MUST be a hash function that has been proved
  ##    indifferentiable from a random oracle [MRH04] under a reasonable
  ##    cryptographic assumption.
  ## - k the security parameter of the suite in bits (for example 128)
  ## - `output`, an elliptic curve point that will be overwritten.
  ## - `augmentation`, an optional augmentation to the message. This will be prepended,
  ##   prior to hashing.
  ##   This is used for building the "message augmentation" variant of BLS signatures
  ##   https://www.ietf.org/archive/id/draft-irtf-cfrg-bls-signature-05.html#section-3.2
  ##   which requires `CoreSign(SK, PK || message)`
  ##   and `CoreVerify(PK, PK || message, signature)`
  ## - `message` is the message to hash
  ## - `domainSepTag` is the protocol domain separation tag (DST).

  var Pjac{.noInit.}: ECP_ShortW_Jac[F, G]
  H.hashToCurve(k, Pjac, augmentation, message, domainSepTag)
  when output is ECP_ShortW_Prj:
    output.projectiveFromJacobian(Pjac)
  else:
    output.affine(Pjac)