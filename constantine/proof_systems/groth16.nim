import ./constraint_systems/r1cs_circom_parser,
       ./constraint_systems/zkey_binary_parser,
       ./constraint_systems/wtns_binary_parser

import ../math/[arithmetic, extension_fields],
       ../math/io/[io_bigints, io_fields, io_ec, io_extfields],
       ../platforms/abstractions,
       ../named/[algebras, properties_fields, properties_curves],
       ../math/elliptic/[ec_shortweierstrass_affine, ec_shortweierstrass_jacobian, ec_scalar_mul, ec_multi_scalar_mul, ec_scalar_mul_vartime],
       ../named/zoo_generators

import ../math/polynomials/[fft_fields, fft_lut]

from std / math import log2

import ./groth16_utils

# Export so users can parse files
export r1cs_circom_parser, zkey_binary_parser, wtns_binary_parser
export groth16_utils
export arithmetic, extension_fields, abstractions,
       io_bigints, io_fields, io_ec, io_extfields,
       ec_shortweierstrass_affine, ec_shortweierstrass_jacobian

type
  Groth16Prover*[Name: static Algebra] = object
    zkey*: Zkey[Name]
    wtns*: Wtns[Name]
    r1cs*: R1CS
    # secret random values `r`, `s` for the proof
    r: Fr[Name]
    s: Fr[Name]

  ## A type to hold the final Groth16 proof, `π(g₁^A, g₁^C, g₂^B)`
  Groth16Proof*[Name: static Algebra] = object
    A*: EC_ShortW_Aff[Fp[Name], G1]
    B*: EC_ShortW_Aff[Fp2[Name], G2]
    C*: EC_ShortW_Aff[Fp[Name], G1]

proc init*[Name: static Algebra](G: typedesc[Groth16Prover[Name]], zkey: Zkey[Name], wtns: Wtns[Name], r1cs: R1CS): Groth16Prover[Name] =
  result = Groth16Prover[Name](
    zkey: zkey,
    wtns: wtns,
    r1cs: r1cs
  )

proc calcAp[Name: static Algebra](ctx: Groth16Prover[Name], wt: seq[Fr[Name]]): EC_ShortW_Jac[Fp[Name], G1] {.noinit.} =
  # A_p is defined as:
  # `A_p = α₁ + (Σ_i [W]_i · A_i) + [r] · δ₁`
  # or closer to code:
  # `A_p = α₁ + sum([witness[i]] · A[i] for i in range(zkey.g16h.nVars)) + [r] · δ₁`
  # where of course in principle `α₁` is `g₁^{α}` etc.
  let g16h = ctx.zkey.g16h

  let alpha1 = g16h.alpha1
  let delta1 = g16h.delta1

  # Compute the terms independent of the witnesses
  let As = ctx.zkey.A
  doAssert As.len == wt.len
  var A_p {.noinit.}: EC_ShortW_Jac[Fp[Name], G1]
  # Calculate `Σ_i [W]_i · A_i` via MSM
  A_p.multiScalarMul_vartime(wt, As)
  # Add the independent terms, `α₁ + [r] · δ₁`
  A_p += alpha1.getJacobian + ctx.r * delta1

  result = A_p

proc calcBp[Name: static Algebra](ctx: Groth16Prover[Name], wt: seq[Fr[Name]]): EC_ShortW_Jac[Fp2[Name], G2] {.noinit.} =
  # B_p is defined as:
  # `B_p = β₂ + (Σ_i [W]_i · B2_i) + [s] · δ₂`
  # or closer to code:
  # `B_p = β₂ + sum([witness[i]] · B2[i] for i in range(zkey.g16h.nVars)) + [s] · δ₂`
  # where of course in principle `β₁` is `g₁^{β}` etc.
  let g16h = ctx.zkey.g16h

  let beta2 = g16h.beta2
  let delta2 = g16h.delta2

  let Bs = ctx.zkey.B2
  doAssert Bs.len == wt.len
  # Calculate `Σ_i [W]_i · B2_i` via MSM
  var B_p {.noinit.}: EC_ShortW_Jac[Fp2[Name], G2]
  B_p.multiScalarMul_vartime(wt, Bs)
  # Add the terms independent of the witnesses, `β₂ + [s] · δ₂`
  B_p += beta2.getJacobian + ctx.s * delta2

  result = B_p

proc calcB1[Name: static Algebra](ctx: Groth16Prover[Name], wt: seq[Fr[Name]]): EC_ShortW_Jac[Fp[Name], G1] {.noinit.} =
  let g16h = ctx.zkey.g16h

  let beta1 = g16h.beta1
  let delta1 = g16h.delta1
  result = beta1.getJacobian + ctx.s * delta1

  # Get the B1 data
  let Bs = ctx.zkey.B1
  doAssert Bs.len == wt.len
  var B1_p {.noinit.}: EC_ShortW_Jac[Fp[Name], G1]
  B1_p.multiScalarMul_vartime(wt, Bs)
  # Add the independent terms, `β₁ + [s] · δ₁`
  B1_p += beta1.getJacobian + ctx.s * delta1

  result = B1_p


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
    var cf {.noinit.}: Fr[Name]
    cf.prod(coef, wt[s])
    outBuf[m][c].sum(outBuf[m][c], cf)

  # Compute C polynomial
  for i in 0 ..< domainSize:
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
    result[i].prod(args[i], cur)
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

proc calcCp[Name: static Algebra](ctx: Groth16Prover[Name],
                                  A_p, B1_p: EC_ShortW_Jac[Fp[Name], G1],
                                  wt: seq[Fr[Name]]): EC_ShortW_Jac[Fp[Name], G1] {.noinit.} =
  # C_p is defined as:
  # `C_p = sum([witness[i]] · C[i] for i in range(zkey.g16h.nVars))`
  # `C_p += [s] · A_p + [r] · B_p - [r] · [s] · δ₁`
  # `C_p += sum(([witness[i]] · [witness[j]]) · H[i] for i, j in r1cs.constraints)`

  let abc = buildABC[Name](ctx, wt)

  let fftD = FFTDescriptor[Fr[Name]].init(abc[0].len * 2)

  let A = itf(abc[0])
  let B = itf(abc[1])
  let C = itf(abc[2])

  # combine A, B, C again
  var jabc = newSeq[Fr[Name]](A.len)
  for i in 0 ..< jabc.len:
    jabc[i].prod(A[i], B[i])     # `A_i · B_i`
    jabc[i].diff(jabc[i], C[i])  # `A_i · B_i - C_i`

  # Get the C data
  let Cs = ctx.zkey.C
  # Get private witnesses
  let g16h = ctx.zkey.g16h

  # get all private witnesses. First nPub are public

  ## NOTE: `g16h.nPublic` does not match number of public variables for some reason,
  ## hence we compute it from `(# total witnesses - # coefficients)`
  let nPub = g16h.nVars.int - Cs.len
  var priv = newSeq[Fr[Name]](Cs.len)
  for i in nPub ..< g16h.nVars.int:
    priv[i - nPub] = wt[i]

  # Calculate `[witness[i]] · C[i]` using MSM
  doAssert Cs.len == priv.len, " Cs: " & $Cs.len & ", priv: " & $priv.len
  var cw {.noinit.}: EC_ShortW_Jac[Fp[Name], G1]
  cw.multiScalarMul_vartime(priv, Cs)

  # Calculate `[witness[i]] · [witness[j]] · H[i]` using MSM
  let Hs = ctx.zkey.H
  doAssert Hs.len == jabc.len
  var resH {.noinit.}: EC_ShortW_Jac[Fp[Name], G1]
  resH.multiScalarMul_vartime(jabc, Hs)

  let delta1 = g16h.delta1
  # Declare `C_p` for the result
  var C_p {.noinit.}: EC_ShortW_Jac[Fp[Name], G1]
  # Combine all terms into final result
  C_p = ctx.s * A_p + ctx.r * B1_p - (ctx.r * ctx.s) * delta1 + cw + resH
  result = C_p

proc prove*[Name: static Algebra](ctx: Groth16Prover[Name]): Groth16Proof {.noinit.} =
  ## Generate a proof given the Groth16 prover context data.
  ##
  ## This implies calculating the proof elements `π = (g₁^A, g₁^C, g₂^B)`
  ##
  ## See `calcAp`, `calcBp` and `calcCp` on how these elements are computed.
  # 1. Sample the random field elements `r` and `s` for the proof
  ctx.r = randomFieldElement(Fr[Name])
  ctx.s = randomFieldElement(Fr[Name])
  # 2. get the witness data needed for all proof elements
  let wt = ctx.wtns.witnesses
  # 3. compute the individual proof elements
  let A_p  = ctx.calcAp(wt)
  let B2_p = ctx.calcBp(wt)
  let B1_p = ctx.calcB1(wt)
  let C_p  = ctx.calcCp(A_p, B1_p, wt)

  result = Groth16Proof(A: A_p.getAffine(), B: B2_p.getAffine(), C: C_p.getAffine())

