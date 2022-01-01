# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ../config/[common, curves],
  ../primitives, ../arithmetic, ../towers,
  ../curves/zoo_hash_to_curve,
  ../ec_shortweierstrass,
  ./h2c_hash_to_field,
  ./h2c_map_to_isocurve_swu,
  ./cofactors,
  ../isogeny/h2c_isogeny_maps,
  ../hashes

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

func mapToIsoCurve_sswuG2_opt9mod16[F; G: static Subgroup](
       r: var ECP_ShortW_Jac[F, G],
       u: F) =
  var
    xn{.noInit.}, xd{.noInit.}: F
    yn{.noInit.}: F
    xd3{.noInit.}: F

  mapToIsoCurve_sswuG2_opt9mod16(
    xn, xd,
    yn,
    u, xd3
  )

  # Convert to Jacobian
  r.z = xd          # Z = xd
  r.x.prod(xn, xd)  # X = xZ² = xn/xd * xd² = xn*xd
  r.y.prod(yn, xd3) # Y = yZ³ = yn * xd³

func mapToCurve[F; G: static Subgroup](
       r: var (ECP_ShortW_Prj[F, G] or ECP_ShortW_Jac[F, G]),
       u: F) =
  ## Map an element of the
  ## finite or extension field F
  ## to an elliptic curve E

  when F.C == BLS12_381 and F is Fp2:
    # https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-11#section-6.6.3
    # Simplified Shallue-van de Woestijne-Ulas method for AB == 0

    # 1. Map to E'2 isogenous to E2
    var
      xn{.noInit.}, xd{.noInit.}: F
      yn{.noInit.}: F
      xd3{.noInit.}: F

    mapToIsoCurve_sswuG2_opt9mod16(
      xn, xd,
      yn,
      u, xd3
    )

    # 2. Map from E'2 to E2
    r.h2c_isogeny_map(
      xn, xd,
      yn,
      isodegree = 3
    )
  else:
    {.error: "Not implemented".}

func mapToCurve_fusedAdd[F; G: static Subgroup](
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

  var P0{.noInit.}, P1{.noInit.}: ECP_ShortW_Jac[F, G]
  when F.C == BLS12_381 and F is Fp2:
    # 1. Map to E'2 isogenous to E2
    P0.mapToIsoCurve_sswuG2_opt9mod16(u0)
    P1.mapToIsoCurve_sswuG2_opt9mod16(u1)

    P0.sum(P0, P1, h2CConst(F.C, G2, Aprime_E2))

    # 2. Map from E'2 to E2
    r.h2c_isogeny_map(P0, isodegree = 3)
  else:
    {.error: "Not implemented".}

# Hash to curve
# ----------------------------------------------------------------

func hashToCurve*[
         F; G: static Subgroup;
         B1, B2, B3: byte|char](
       H: type CryptoHash,
       k: static int,
       output: var ECP_ShortW_Prj[F, G],
       augmentation: openarray[B1],
       message: openarray[B2],
       domainSepTag: openarray[B3]
     ) =
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
  ##   https://tools.ietf.org/html/draft-irtf-cfrg-bls-signature-04#section-3.2
  ##   which requires `CoreSign(SK, PK || message)`
  ##   and `CoreVerify(PK, PK || message, signature)`
  ## - `message` is the message to hash
  ## - `domainSepTag` is the protocol domain separation tag (DST).
  ##   If a domainSepTag larger than 255-bit is required,
  ##   it is recommended to cache the reduced DST.

  var u{.noInit.}: array[2, F]
  H.hashToField(k, u, augmentation, message, domainSepTag)

  when false:
    var P{.noInit.}: array[2, ECP_ShortW_Prj[F, G]]
    P[0].mapToCurve(u[0])
    P[1].mapToCurve(u[1])
    output.sum(P[0], P[1])
  else:
    var Pjac{.noInit.}: ECP_ShortW_Jac[F, G]
    Pjac.mapToCurve_fusedAdd(u[0], u[1])
    output.projectiveFromJacobian(Pjac)

  output.clearCofactorFast()
