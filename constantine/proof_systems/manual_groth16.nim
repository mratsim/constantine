import ./constraint_systems/r1cs_circom_parser,
       ./constraint_systems/zkey_binary_parser,
       ./constraint_systems/wtns_binary_parser

import ../math/[arithmetic, extension_fields],
       ../math/io/[io_bigints, io_fields, io_ec, io_extfields],
       ../platforms/abstractions,
       ../named/[algebras, properties_fields, properties_curves],
       ../math/elliptic/[ec_shortweierstrass_affine, ec_shortweierstrass_jacobian, ec_scalar_mul, ec_multi_scalar_mul, ec_scalar_mul_vartime],
       ../named/zoo_generators,
       ../csprngs/sysrand

import ../math/polynomials/[fft_fields, fft_lut]

from std / math import log2

import ./groth16_utils

type
  Groth16Prover[Name: static Algebra] = object
    ## XXX: In the future the below should be typed objects that are already unmarshalled!
    zkey: Zkey[Name]
    wtns: Wtns[Name]
    r1cs: R1CS
    # secret random values `r`, `s` for the proof
    r: Fr[Name]
    s: Fr[Name]

proc init*[Name: static Algebra](G: typedesc[Groth16Prover[Name]], zkey: Zkey[Name], wtns: Wtns[Name], r1cs: R1CS): Groth16Prover[Name] =
  result = Groth16Prover[Name](
    zkey: zkey,
    wtns: wtns,
    r1cs: r1cs,
    r: randomFieldElement(Fr[Name]), ## XXX: do we want to do this in `init`?
    s: randomFieldElement(Fr[Name])
  )

proc calcAp[Name: static Algebra](ctx: Groth16Prover[Name], wt: seq[Fr[Name]]): EC_ShortW_Jac[Fp[Name], G1] =
  # A_p is defined as
  # A_p = α_1 + (Σ_i [W]_i · A_i) + [r] · δ_1
  # A_p = alpha1 + sum(A[i] * witness[i] for i in range(zkey.g16h.nVars)) + r * delta1
  # where of course in principle `α_1` is `g_1^{α}` etc.
  let g16h = ctx.zkey.g16h

  let alpha1 = g16h.alpha1
  let delta1 = g16h.delta1

  # Declare `A_p` for the result
  var A_p: EC_ShortW_Jac[Fp[Name], G1]

  # Compute the terms independent of the witnesses
  A_p = alpha1.getJacobian + ctx.r * delta1
  echo A_p.toHex()

  let As = ctx.zkey.A
  doAssert As.len == wt.len
  for i in 0 ..< As.len:
    A_p += wt[i] * As[i]

  # Via MSM
  var A_p_msm: EC_ShortW_Jac[Fp[Name], G1]
  A_p_msm.multiScalarMul_vartime(wt, As)
  A_p_msm += alpha1.getJacobian + ctx.r * delta1

  doAssert (A_p == A_p_msm).bool

  result = A_p

proc calcBp[Name: static Algebra](ctx: Groth16Prover[Name], wt: seq[Fr[Name]]): EC_ShortW_Jac[Fp2[Name], G2] =
  # B_p = beta2 + sum(B2[i] * witness[i] for i in range(zkey.g16h.nVars)) + s * delta2
  # B_p = β_2 + (Σ_i [W]_i · B2_i) + [s] · δ_2
  # where of course in principle `β_1` is `g_1^{β}` etc.
  let g16h = ctx.zkey.g16h

  let beta2 = g16h.beta2
  let delta2 = g16h.delta2

  # Declare `B_p` for the result
  var B_p: EC_ShortW_Jac[Fp2[Name], G2]

  # Compute the terms independent of the witnesses
  B_p = beta2.getJacobian + ctx.s * delta2

  let Bs = ctx.zkey.B2
  doAssert Bs.len == wt.len
  # could compute via MSM
  for i in 0 ..< Bs.len:
    B_p += wt[i] * Bs[i]

  result = B_p

proc calcB1[Name: static Algebra](ctx: Groth16Prover[Name], wt: seq[Fr[Name]]): EC_ShortW_Jac[Fp[Name], G1] =
  let g16h = ctx.zkey.g16h

  let beta1 = g16h.beta1
  let delta1 = g16h.delta1
  result = beta1.getJacobian + ctx.s * delta1

  # Get the B1 data
  let Bs = ctx.zkey.B1
  doAssert Bs.len == wt.len
  for i in 0 ..< Bs.len:
    result += wt[i] * Bs[i]

proc buildABC[Name: static Algebra](ctx: Groth16Prover[Name], wt: seq[Fr[Name]]): tuple[A, B, C: seq[Fr[Name]]] =
  # Extract required data using accessors
  let
    coeffs = ctx.zkey.coeffs
    g16h = ctx.zkey.g16h
    domainSize = g16h.domainSize
    nCoeff = coeffs.num

  # Initialize output sequences
  var
    outBuffA = newSeq[Fr[Name]](domainSize)
    outBuffB = newSeq[Fr[Name]](domainSize)
    outBuffC = newSeq[Fr[Name]](domainSize)

  template toPUA[Name](x: seq[Name]): untyped = cast[ptr UncheckedArray[Name]](addr x[0])

  var outBuf = [toPUA outBuffA, toPUA outBuffB]

  # Build A and B polynomials
  for i in 0 ..< nCoeff:
    let
      m = coeffs.cs[i].matrix
      c = coeffs.cs[i].section
      s = coeffs.cs[i].index
      coef = coeffs.cs[i].value
    assert s.int < wt.len
    outBuf[m][c] = outBuf[m][c] + coef * wt[s]

  # Compute C polynomial
  for i in 0 ..< domainSize:
    ## XXX: Here this product yields numbers in SnarkJS I cannot reproduce
    outBuffC[i].prod(outBuffA[i], outBuffB[i])

  result = (outBuffA, outBuffB, outBuffC)

proc transform[Name: static Algebra](args: seq[Fr[Name]], inc: Fr[Name]): seq[Fr[Name]] =
  ## Applies (multiplies) increasing powers of `inc` to each element
  ## of `args`, i.e.
  ##
  ## `{ a[0], a[1]·inc, a[2]·inc², a[3]·inc³, ... }`.
  ##
  ## In our case `inc` is usually a root of unity of the power given by
  ## `log2( FFT order ) + 1`.
  result = newSeq[Fr[Name]](args.len)
  var cur = Fr[Name].fromUint(1.uint64)
  for i in 0 ..< args.len:
    result[i] = args[i] * cur
    cur *= inc

proc itf[Name: static Algebra](arg: seq[Fr[Name]]): seq[Fr[Name]] =
  ## inverse FFT -> transform -> forward FFT
  ##
  ## Equivalent to SnarkJS (same for A and C):
  ## ```js
  ##    const buffB = await Fr.ifft(buffB_T, "", "", logger, "IFFT_B");
  ##    const buffBodd = await Fr.batchApplyKey(buffB, Fr.e(1), inc);
  ##    const buffBodd_T = await Fr.fft(buffBodd, "", "", logger, "FFT_B");
  ## ```
  let buffA = ifft_vartime(arg)

  let power = log2(arg.len.float).int # arg is power of 2
  let inc = scaleToRootOfUnity(Name)[power + 1]
  let buffAodd = buffA.transform(inc)

  result = fft_vartime(buffAodd)

proc calcCp[Name: static Algebra](ctx: Groth16Prover[Name], A_p, B1_p: EC_ShortW_Jac[Fp[Name], G1], wt: seq[Fr[Name]]): EC_ShortW_Jac[Fp[Name], G1] =
  #  # Compute C_p
  #  C_p = sum(C[i] * witness[i] for i in range(zkey.g16h.nVars))
  #  C_p += A_p * s + r * B_p - r * s * delta1
  #  C_p += sum(H[i] * (witness[i] * witness[j]) for i, j in r1cs.constraints)

  let abc = buildABC[Name](ctx, wt)

  let fftD = FFTDescriptor[Fr[Name]].init(abc[0].len * 2)

  let A = itf(abc[0])
  let B = itf(abc[1])
  let C = itf(abc[2])

  # combine A, B, C again
  var jabc = newSeq[Fr[Name]](A.len)
  for i in 0 ..< jabc.len:
    jabc[i] = A[i] * B[i] - C[i]

  # Get the C data
  let Cs = ctx.zkey.C
  # Get private witnesses
  let g16h = ctx.zkey.g16h
  ## XXX: Why is `nPublic` `1` when `Cs.len` ends up as `4` and `nVars` is `6`?
  echo "LEN ? ", Cs.len, " total witnesses? ", wt.len, " public? ", g16h.nPublic, " total? ", g16h.nVars

  var priv = newSeqOfCap[Fr[Name]](wt.len)
  let nPub = g16h.nVars.int - Cs.len # g16h.nPublic.int
  for i in nPub ..< g16h.nVars.int:
    priv.add wt[i]

  doAssert Cs.len == priv.len, " Cs: " & $Cs.len & ", priv: " & $priv.len
  var cw: EC_ShortW_Jac[Fp[Name], G1]
  for i in 0 ..< Cs.len:
    cw += priv[i] * Cs[i]

  let Hs = ctx.zkey.H
  doAssert Hs.len == jabc.len
  var resH: EC_ShortW_Jac[Fp[Name], G1]
  for i in 0 ..< Hs.len:
    resH += jabc[i] * Hs[i]

  let delta1 = g16h.delta1
  # Declare `C_p` for the result
  var C_p: EC_ShortW_Jac[Fp[Name], G1]
  C_p = ctx.s * A_p + ctx.r * B1_p - (ctx.r * ctx.s) * delta1 + cw + resH
  result = C_p

proc prove[Name: static Algebra](ctx: Groth16Prover[Name]): tuple[A: EC_ShortW_Jac[Fp[Name], G1],
                                                                  B: EC_ShortW_Jac[Fp2[Name], G2],
                                                                  C: EC_ShortW_Jac[Fp[Name], G1]] =
  #[
  XXX: fix up notation here!
  r = random_scalar_field_element()
  s = random_scalar_field_element()

  # Compute A_p
  A_p = alpha1 + sum(A[i] * witness[i] for i in range(zkey.g16h.nVars)) + r * delta1

  # Compute B_p
  B_p = beta2 + sum(B2[i] * witness[i] for i in range(zkey.g16h.nVars)) + s * delta2

  # Compute C_p
  C_p = sum(C[i] * witness[i] for i in range(zkey.g16h.nVars))
  C_p += A_p * s + r * B_p - r * s * delta1
  C_p += sum(H[i] * (witness[i] * witness[j]) for i, j in r1cs.constraints)

  proof = (A_p, B_p, C_p)
  ]#

  let wt = ctx.wtns.witnesses

  let A_p  = ctx.calcAp(wt)
  let B2_p = ctx.calcBp(wt)
  let B1_p = ctx.calcB1(wt)
  let C_p  = ctx.calcCp(A_p, B1_p, wt)

  result = (A: A_p, B: B2_p, C: C_p)

when isMainModule:

  const T = BN254_Snarks

  let wtns = parseWtnsFile("/home/basti/org/constantine/moonmath/circom/three_fac_js/witness.wtns")
    .toWtns[:T]()
  let zkey = parseZkeyFile("/home/basti/org/constantine/moonmath/snarkjs/three_fac/three_fac_final.zkey")
    .toZkey[:T]()
  let r1cs = parseR1csFile("/home/basti/org/constantine/moonmath/circom/three_fac.r1cs")
    .toR1CS


  let g16h = zkey.g16h
  ## NOTE: We *expect* all these to be 0, because they are the respective moduli for
  ## `Fp` and `Fr`!
  ## XXX: move to a test case
  echo "q = ", toFp[T](g16h.q, false).toDecimal()
  echo "r = ", toFr[T](g16h.r, false).toDecimal()
  echo "wtns r = ", toFr[T](wtns.header.r, false).toDecimal()

  var ctx = Groth16Prover[T].init(zkey, wtns, r1cs)

  ## Note: We will now calculate the proof using a fixed, non secret set of points
  ## r, s (or r, t) ∈ 𝔽r in order to compare with a calculation of `snarkjs`. We
  ## hacked in a print of the secret it randomly sampled.
  # The 'secret' constants from
  ## XXX: Move to a test case!
  const rSJ = @[
    byte 143,  55, 118,  73,  42, 115,  60,  77,
    95, 209,  41, 144, 250, 137, 138,  71,
    176, 242, 186, 232, 179,  30,  88, 255,
    198, 161, 182, 150, 220, 149,  33,  19
  ]
  const sSJ = @[
    byte 213, 105, 105,  27, 129, 249, 139, 158,
    221,  68,  37, 163,  59,  71,  19, 108,
    60, 153, 183, 156,  25, 148,  37,   9,
    85, 205, 250, 246, 132, 142, 244,  36
  ]

  # construct the random element `r` from snarkjs "secret" r
  let r = toFr[BN254_Snarks](rSJ)
  # and `s`
  let s = toFr[BN254_Snarks](sSJ)

  ctx.r = r
  ctx.s = s

  let (A_p, B2_p, C_p) = ctx.prove()

  echo "\n==============================\n"
  echo "A_p#16 = ", A_p.toHex()
  echo "A_p#10 = ", A_p.toDecimal()
  echo "------------------------------"
  echo "B_p#16 = ", B2_p.toHex()
  echo "B_p#10 = ", B2_p.toDecimal()
  echo "------------------------------"
  echo "C_p#16 = ", C_p.toHex()
  echo "C_p#10 = ", C_p.toDecimal()

  ## SnarkJS yields:
  ##
  ## `snarkjs groth16 prove three_fac_final.zkey ../../circom/three_fac_js/witness.wtns proof.json public.json`
  ##
  #[
{
 "pi_a": [
  "5525629793372463776337933283524928112323589665400780041477380790923758613749",
  "21229177076048503863699135039723099340209138028149442778064006577287317302601",
  "1"
 ],
 "pi_b": [
  [
   "10113559933709853115219982658131344715329670532374721861173670433756614595086",
   "748111067660143353202076805159132563350177510079329482395824347599610874338"
  ],
  [
   "14193926223452546125681093394065339196897041249946578591171606543100010486627",
   "871256420758854731396810855688710623510558493821614150596755347032202324148"
  ],
  [
   "1",
   "0"
  ]
 ],
 "pi_c": [
  "18517653609733492682442099361591955563405567929398531111532682405176646276349",
  "17315036348446251361273519572420522936369550153340386126725970444173389652255",
  "1"
 ],
 "protocol": "groth16",
 "curve": "bn128"
}
  ]#
