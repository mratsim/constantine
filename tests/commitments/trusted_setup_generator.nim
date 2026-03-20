import
  constantine/named/algebras,
  constantine/math/[ec_shortweierstrass, extension_fields],
  constantine/math/polynomials/polynomials,
  constantine/math/arithmetic/finite_fields,
  constantine/math/io/io_fields,
  ../math_polynomials/fft_utils

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
    omegaForFFT*: Fr[BLS12_381]
      ## Generator root for FFT descriptor (CDS-th root)
    omegaMax*: Fr[BLS12_381]
      ## Generator root for verification (maxWidth-th root)

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

  # Domain setup using fft_utils for proper root computation
  # - omegaForFFT: CDS-th root used for FFT descriptor creation
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
  # Roots are computed programmatically using fft_utils.getRootOfUnityForScale

  let scaleCDS = int(log2_vartime(uint CDS))
  result.omegaForFFT = getRootOfUnityForScale(Fr[BLS12_381], scaleCDS)

  let scaleMax = int(log2_vartime(uint maxWidth))
  result.omegaMax = getRootOfUnityForScale(Fr[BLS12_381], scaleMax)