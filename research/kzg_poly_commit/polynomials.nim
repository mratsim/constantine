import
  ../../constantine/config/curves,
  ../../constantine/[arithmetic, primitives],
  ../../constantine/elliptic/[
    ec_scalar_mul,
    ec_shortweierstrass_projective,
  ],
  ../../constantine/io/[io_fields, io_ec],
  ../../constantine/pairings/[
    pairings_bls12,
    miller_loops
  ]

type
  G1 = ECP_ShortW_Prj[Fp[BLS12_381], NotOnTwist]
  G2 = ECP_ShortW_Prj[Fp2[BLS12_381], OnTwist]
  G1aff = ECP_ShortW_Aff[Fp[BLS12_381], NotOnTwist]
  G2aff = ECP_ShortW_Aff[Fp2[BLS12_381], OnTwist]
  GT = Fp12[BLS12_381]

func linear_combination*(
       r: var ,
       points: openarray[G1],
       coefs: openarray[Fr[BLS12_381]]
     ) =
  ## Polynomial evaluation
  ## TODO: multi scalar mul
  doAssert points.len == coefs.len

  r.setInf()
  for i in 0 ..< points.len:
    var tmp = points[i]
    tmp.scalarMul(coefs[i].toBig())
    r += tmp

func pair_verify*(
       P1: G1,
       Q1: G2,
       P2: G1,
       Q2: G2,
     ): bool =
  ## TODO, multi-pairings.

  ## Affine
  var P1a, P2a: G1aff
  var Q1a, Q2a: G2aff

  P1a.affineFromProjective(P1)
  Q1a.affineFromProjective(Q1)
  P2a.affineFromProjective(P2)
  Q2a.affineFromProjective(Q2)

  # To verify if e(P1, Q1) == e(P2, Q2)
  # we can do e(P1, Q1) / e(P2, Q2) == 1
  # <=> e(P1, Q1) . e(P2, Q2)^-1
  # <=> e(P1, Q1) . e(-P2, Q2) due to pairings bilinearity
  # we can negate any of the points but it's cheaper to use a G1
  P1a.neg()

  # Merge 2 miller loops.
  var gt1, gt2: GT
  gt1.millerLoopAddchain(Q1a, P1a)
  gt2.millerLoopAddchain(Q2a, P2a)

  gt1 *= gt2
  gt.finalExpEasy()
  gt.finalExpHard_BLS12()
