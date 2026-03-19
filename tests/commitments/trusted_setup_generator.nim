import
  constantine/named/algebras,
  constantine/math/[ec_shortweierstrass, extension_fields],
  constantine/math/polynomials/polynomials,
  constantine/math/arithmetic/finite_fields,
  constantine/math/io/io_fields

type
  EC_G1_Aff* = EC_ShortW_Aff[Fp[BLS12_381], G1]
  EC_G1_Jac* = EC_ShortW_Jac[Fp[BLS12_381], G1]
  EC_G2_Jac* = EC_ShortW_Jac[Fp2[BLS12_381], G2]
  EC_G2_Aff* = EC_ShortW_Aff[Fp2[BLS12_381], G2]

  TrustedSetup*[N, L, maxWidth: static int] = object
    # CDS = 2 * N/L
    poly*{.align: 64.}: PolynomialCoef[N, Fr[BLS12_381]]
    polyBig*{.align: 64.}: PolynomialCoef[N, BigInt[255]]
    powers_of_tau_G1*{.align: 64.}: PolynomialCoef[N, EC_G1_Aff]
    powers_of_tau_G2*{.align: 64.}: PolynomialCoef[L+1, EC_G2_Aff]
    circulantDomain*{.align: 64.}: PolyEvalRootsDomain[2 * (N div L), Fr[BLS12_381]]
    omegaMax*: Fr[BLS12_381]

func genPowersOfTauImpl(EC: typedesc, secret: auto, length: int): seq[EC] =
  result.setLen(length)
  var P {.noInit.}: EC
  P.fromAffine(EC.F.C.getGenerator($EC.G))
  result[0] = P
  for i in 1 ..< length:
    P.scalarMul_vartime(secret)
    result[i] = P

func computePowersOfTauG1[N: static int](powers_of_tau: var array[N, EC_G1_Aff], secret: Fr[BLS12_381]) =
  var prev {.noInit.}: EC_G1_Jac
  prev.setGenerator()
  powers_of_tau[0].affine(prev)
  let secretBig = secret.toBig()
  for i in 1 ..< N:
    var next {.noInit.}: EC_G1_Jac
    next.scalarMul_vartime(secretBig, prev)
    powers_of_tau[i].affine(next)
    prev = next

func computePowersOfTauG2[N: static int](powers_of_tau: var array[N, EC_G2_Aff], secret: Fr[BLS12_381]) =
  var prev {.noInit.}: EC_G2_Jac
  prev.setGenerator()
  powers_of_tau[0].affine(prev)
  let secretBig = secret.toBig()
  for i in 1 ..< N:
    var next {.noInit.}: EC_G2_Jac
    next.scalarMul_vartime(secretBig, prev)
    powers_of_tau[i].affine(next)
    prev = next

proc gen_setup*(N, L, maxWidth: static int; tauHex: string): TrustedSetup[N, L, maxWidth] =
  ## Generate test setup for FK20 with given polynomial size N and domain size K2.
  ##
  ## @param N: polynomial size (coefficient form)
  ## @param K2: domain size (must be power of 2, >= 2*N for DA)
  ## @param tauHex: hex string for secret tau
  ## @return: tuple with poly, polyBig (BigInt version), powers_of_tau, tau, tauG2, domain
  ##
  ## Note: Both poly and powers_of_tau are in coefficient form (monomial basis),
  ## matching c-kzg FK20 tests. Ethereum KZG uses evaluation form (Lagrange basis)
  ## for blobs, but FK20 algorithm operates on coefficient form.

  static: doAssert N mod L == 0
  const CDS = 2 * (N div L)

  # Polynomial coefficients: [1, 2, 3, 4, 7, 7, 7, 7, 13, 13, ...]
  # FK20 needs field elements (for FFT), MSM needs BigInt (for scalar mult)
  result.poly.coefs[0].fromUint(1)
  result.poly.coefs[1].fromUint(2)
  result.poly.coefs[2].fromUint(3)
  result.poly.coefs[3].fromUint(4)
  for i in 4 ..< 8:
    result.poly.coefs[i].fromUint(7)
  for i in 8 ..< N:
    result.poly.coefs[i].fromUint(13)

  # Convert to BigInt for kzg_commit MSM
  result.polyBig.coefs.asUnchecked().batchFromField(result.poly.coefs.asUnchecked(), N)

  # Powers of tau - SRS is [G, τG, τ²G, ...]
  # Note: tau is "toxic waste" - not exposed after trusted setup
  var tau: Fr[BLS12_381]
  tau.fromHex(tauHex)
  result.powers_of_tau_G1.coefs.computePowersOfTauG1(tau)
  result.powers_of_tau_G2.coefs.computePowersOfTauG2(tau)

  # Domain setup
  # - circulantDomain: CDS-th root for FFT during FK20 proof generation
  # - omegaMax: maxWidth-th root used for x computation in verification
  #
  # Relationship between parameters:
  #   CDS = 2 * N / L        # Circulant domain size (FFT during proof gen)
  #   maxWidth = CDS * (N div L)  # Full domain size for verification
  #
  # Test configurations:
  # | L | N  | CDS = 2*N/L | maxWidth |
  # |---|----|-------------|----------|
  # | 1 | 16 |     32      |    32    |
  # | 2 | 16 |     16      |    32    |
  # | 4 | 32 |     16      |    64    |
  #
  # When CDS == maxWidth (L=1 case), omegaMax == omega_CDS
  # When CDS < maxWidth (L>1 cases), need different root depending on maxWidth

  result.circulantDomain.rootsOfUnity[0].fromUint(1)
  case CDS
  of 32:
    const omega32 = Fr[BLS12_381].fromHex"0x50e0903a157988bab4bcd40e22f55448bf6e88fb4c38fb8a360c60997369df4e"
    for i in 1 ..< CDS:
      result.circulantDomain.rootsOfUnity[i] = result.circulantDomain.rootsOfUnity[i-1] * omega32
    result.omegaMax = omega32
  of 16:
    const omega16 = Fr[BLS12_381].fromHex"0x20b1ce9140267af9dd1c0af834cec32c17beb312f20b6f7653ea61d87742bcce"
    for i in 1 ..< CDS:
      result.circulantDomain.rootsOfUnity[i] = result.circulantDomain.rootsOfUnity[i-1] * omega16
    when maxWidth == 32:
      let omega32 = Fr[BLS12_381].fromHex"0x50e0903a157988bab4bcd40e22f55448bf6e88fb4c38fb8a360c60997369df4e"
      result.omegaMax = omega32
    else:
      let omega64 = Fr[BLS12_381].fromHex"0x45af6345ec055e4d14a1e27164d8fdbd2d967f4be2f951558140d032f0a9ee53"
      result.omegaMax = omega64
  else:
    raiseAssert("Unsupported circulant domain size: " & $CDS)