# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/typetraits,
  ../primitives,
  ../config/[common, curves],
  ../arithmetic,
  ../towers,
  ../elliptic/[
    ec_weierstrass_affine,
    ec_weierstrass_projective
  ],
  ../io/io_towers

# ############################################################
#
#            Miller Loop's Line Evaluation
#             with projective coordinates
#
# ############################################################
#
# - Pairing Implementation Revisited
#   Michael Scott, 2019
#   https://eprint.iacr.org/2019/077
#
# - The Realm of the Pairings
#   Diego F. Aranha and Paulo S. L. M. Barreto
#   and Patrick Longa and Jefferson E. Ricardini, 2013
#   https://eprint.iacr.org/2013/722.pdf
#   http://sac2013.irmacs.sfu.ca/slides/s1.pdf

#
# TODO: Implement fused line doubling and addition
#       from Costello2009 or Aranha2010
#       We don't need the complete formulae in the Miller Loop

type
  Line*[F; twist: static SexticTwist] = object
    ## Packed line representation over a E'(Fp^k/d)
    ## with k the embedding degree and d the twist degree
    ## i.e. for a curve with embedding degree 12 and sextic twist
    ## F is Fp2
    ##
    ## Assuming a Sextic Twist
    ##
    ## Out of 6 Fp2 coordinates, 3 are 0 and
    ## the non-zero coordinates depend on the twist kind.
    ##
    ## For a D-twist,
    ##   (x, y, z) corresponds to an sparse element of Fp12
    ##   with Fp2 coordinates: xy00z0
    ## For a M-Twist
    ##   (x, y, z) corresponds to an sparse element of Fp12
    ##   with Fp2 coordinates: xyz000
    x*, y*, z*: F

func toHex*(line: Line, order: static Endianness = bigEndian): string =
  result = static($line.typeof.genericHead() & '(')
  for fieldName, fieldValue in fieldPairs(line):
    when fieldName != "x":
      result.add ", "
    result.add fieldName & ": "
    result.appendHex(fieldValue, order)
  result.add ")"

# Line evaluation
# --------------------------------------------------

func `*=`(a: var Fp2, b: Fp) =
  ## Multiply an element of Fp2 by an element of Fp
  # TODO: make generic and move to tower_field_extensions
  a.c0 *= b
  a.c1 *= b

func line_update(line: var Line, P: ECP_SWei_Aff) =
  ## Update the line evaluation with P
  ## after addition or doubling
  ## P in G1
  line.x *= P.y
  line.z *= P.x

func line_eval_double*(line: var Line, T: ECP_SWei_Proj) =
  ## Evaluate the line function for doubling
  ## i.e. the tangent at T
  ##
  ## With T in homogenous projective coordinates (X, Y, Z)
  ## And ξ the sextic non residue to construct 𝔽p4 / 𝔽p6 / 𝔽p12
  ##
  ## M-Twist:
  ##   A = -2ξ Y.Z
  ##   B = 3bξ Z² - Y²
  ##   C = 3 X²
  ##
  ## D-Twist are scaled by ξ to avoid dividing by ξ:
  ##   A = -2ξ Y.Z
  ##   B = 3b Z² - ξY²
  ##   C = 3ξ X²
  ##
  ## Instead of
  ##   - equation 10 from The Real of pairing, Aranha et al, 2013
  ##   - or chapter 3 from pairing Implementation Revisited, Scott 2019
  ##   A = -2 Y.Z
  ##   B = 3b/ξ Z² - Y²
  ##   C = 3 X²
  ##
  ## A constant factor will be wiped by the final exponentiation
  ## as for all non-zero α ∈ GF(pᵐ)
  ## with
  ## - p odd prime
  ## - and gcd(α,pᵐ) = 1 (i.e. the extension field pᵐ is using irreducible polynomials)
  ##
  ## Little Fermat holds and we have
  ## α^(pᵐ - 1) ≡ 1 (mod pᵐ)
  ##
  ## The final exponent is of the form
  ## (pᵏ-1)/r
  ##
  ## A constant factor on twisted coordinates pᵏᐟᵈ
  ## is a constant factor on pᵏ with d the twisting degree
  ## and so will be elminated. QED.
  var v {.noInit.}: Line.F
  const b3 = 3 * ECP_SWei_Proj.F.C.getCoefB()

  template A: untyped = line.x
  template B: untyped = line.y
  template C: untyped = line.z

  A = T.y               # A = Y
  v = T.y               # v = Y
  B = T.z               # B = Z
  C = T.x               # C = X

  A *= B                # A = Y.Z
  C.square()            # C = X²
  v.square()            # v = Y²
  B.square()            # B = Z²

  A.double()            # A =  2 Y.Z
  A.neg()               # A = -2 Y.Z
  A *= SexticNonResidue # A = -2 ξ Y.Z

  B *= b3               # B = 3b Z²
  C *= 3                # C = 3X²
  when ECP_SWei_Proj.F.C.getSexticTwist() == M_Twist:
    B *= SexticNonResidue # B = 3b' Z² = 3bξ Z²
  elif ECP_SWei_Proj.F.C.getSexticTwist() == D_Twist:
    v *= SexticNonResidue # v =  ξ Y²
    C *= SexticNonResidue # C = 3ξ X²
  else:
    {.error: "unreachable".}

  B -= v                # B = 3bξ Z² - Y²  (M-twist)
                        # B = 3b Z² - ξ Y² (D-twist)

func line_eval_add*(line: var Line, T: ECP_SWei_Proj, Q: ECP_SWei_Aff) =
  ## Evaluate the line function for addition
  ## i.e. the line between T and Q
  ##
  ## With T in homogenous projective coordinates (X, Y, Z)
  ## And ξ the sextic non residue to construct 𝔽p4 / 𝔽p6 / 𝔽p12
  ##
  ## M-Twist:
  ##   A = ξ (X₁ - Z₁X₂)
  ##   B = (Y₁ - Z₁Y₂) X₂ - (X₁ - Z₁X₂) Y₂
  ##   C = - (Y₁ - Z₁Y₂)
  ##
  ## D-Twist:
  ##   A = X₁ - Z₁X₂
  ##   B = (Y₁ - Z₁Y₂) X₂ - (X₁ - Z₁X₂) Y₂
  ##   C = - (Y₁ - Z₁Y₂)
  ##
  ## Note: There is no need for complete formula as
  ## we have T ∉ [Q, -Q] in the Miller loop doubling-and-add
  ## i.e. the line cannot be vertical
  var v {.noInit.}: Line.F

  template A: untyped = line.x
  template B: untyped = line.y
  template C: untyped = line.z

  A = T.x     # A = X₁
  v = T.z     # v = Z₁
  B = T.z     # B = Z₁
  C = T.y     # C = Y₁

  v *= Q.y    # v = Z₁Y₂
  B *= Q.x    # B = Z₁X₂

  A -= B      # A = X₁-Z₁X₂
  C -= v      # C = Y₁-Z₁Y₂

  v = A       # v = X₁-Z₁X₂
  when ECP_SWei_Proj.F.C.getSexticTwist() == M_Twist:
    A *= SexticNonResidue # A = ξ (X₁ - Z₁X₂)

  v *= Q.y    # v = (X₁-Z₁X₂) Y₂
  B = C       # B = Y₁-Z₁Y₂
  B *= Q.x    # B = (Y₁-Z₁Y₂) X₂
  B -= v      # B = (Y₁-Z₁Y₂) X₂ - (X₁-Z₁X₂) Y₂

  C.neg()     # C = -(Y₁-Z₁Y₂)

func line_double*(line: var Line, T: var ECP_SWei_Proj, P: ECP_SWei_Aff) =
  ## Doubling step of the Miller loop
  ## T in G2, P in G1
  ##
  ## Compute lt,t(P)
  ##
  # TODO fused line doubling from Costello 2009, Grewal 2012, Aranha 2013
  line_eval_double(line, T)
  line.line_update(P)
  T.double()

func line_add*[C](
       line: var Line,
       T: var ECP_SWei_Proj[Fp2[C]],
       Q: ECP_SWei_Aff[Fp2[C]], P: ECP_SWei_Aff[Fp[C]]) =
  ## Addition step of the Miller loop
  ## T and Q in G2, P in G1
  ##
  ## Compute lt,q(P)
  # TODO fused line addition from Costello 2009, Grewal 2012, Aranha 2013
  line_eval_add(line, T, Q)
  line.line_update(P)
  # TODO: mixed addition
  var QProj {.noInit.}: ECP_SWei_Proj[Fp2[C]]
  QProj.projectiveFromAffine(Q)
  T += QProj
