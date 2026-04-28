import
  constantine/named/algebras,
  constantine/math/[ec_shortweierstrass, extension_fields],
  constantine/math/polynomials/polynomials,
  constantine/math/arithmetic/finite_fields,
  constantine/math/io/io_fields,
  ../math_polynomials/fft_utils

type
  BLS12_381_G1_Aff* = EC_ShortW_Aff[Fp[BLS12_381], G1]
  BLS12_381_G1_Jac* = EC_ShortW_Jac[Fp[BLS12_381], G1]
  BLS12_381_G2_Aff* = EC_ShortW_Aff[Fp2[BLS12_381], G2]
  BLS12_381_G2_Jac* = EC_ShortW_Jac[Fp2[BLS12_381], G2]

  TrustedSetup*[N, L, maxWidth: static int] = object
    # CDS = 2 * N/L
    testPoly*{.align: 64.}: PolynomialCoef[N, Fr[BLS12_381]]
    testPolyBig*{.align: 64.}: PolynomialCoef[N, BigInt[255]]
    powers_of_tau_G1*{.align: 64.}: PolynomialCoef[N, BLS12_381_G1_Aff]
    powers_of_tau_G2*{.align: 64.}: PolynomialCoef[L+1, BLS12_381_G2_Aff]
    omegaForFFT*: Fr[BLS12_381]
      ## Generator root for FFT descriptor (CDS-th root)

    rootsOfUnity*: PolyEvalRootsDomain[maxWidth, Fr[BLS12_381], kNaturalOrder]
      ## Generator root for verification (maxWidth-th root)


func computePowersOfTauG1[N: static int](powers_of_tau: var array[N, BLS12_381_G1_Aff], secret: Fr[BLS12_381]) =
  var prev {.noInit.}: BLS12_381_G1_Jac
  prev.setGenerator()
  powers_of_tau[0].affine(prev)
  let secretBig = secret.toBig()
  for i in 1 ..< N:
    var next {.noInit.}: BLS12_381_G1_Jac
    next.scalarMul_vartime(secretBig, prev)
    powers_of_tau[i].affine(next)
    prev = next

func computePowersOfTauG2[N: static int](powers_of_tau: var array[N, BLS12_381_G2_Aff], secret: Fr[BLS12_381]) =
  var prev {.noInit.}: BLS12_381_G2_Jac
  prev.setGenerator()
  powers_of_tau[0].affine(prev)
  let secretBig = secret.toBig()
  for i in 1 ..< N:
    var next {.noInit.}: BLS12_381_G2_Jac
    next.scalarMul_vartime(secretBig, prev)
    powers_of_tau[i].affine(next)
    prev = next

proc gen_setup*(N, L, maxWidth: static int; tauHex: string): TrustedSetup[N, L, maxWidth] =
  ## Generate a test trusted setup for FK20 multiproofs.
  ##
  ## @param N        polynomial size (coefficient form), must satisfy `N mod L == 0` and `N >= 8`
  ## @param L        cell size (number of evaluations per coset proof); CDS = 2*N/L
  ## @param maxWidth full FFT/verification domain size (power of 2)
  ## @param tauHex   hex string for the secret τ
  ## @return         TrustedSetup with testPoly, testPolyBig, powers_of_tau_G1, powers_of_tau_G2,
  ##                 omegaForFFT (CDS-th root) and rootsOfUnity (maxWidth domain)
  ##
  ## Note: Both poly and powers_of_tau are in coefficient form (monomial basis),
  ## matching c-kzg FK20 tests. Ethereum KZG uses evaluation form (Lagrange basis)
  ## for blobs, but FK20 algorithm operates on coefficient form.

  static:
    doAssert N mod L == 0
    doAssert N >= 8, "Test polynomial pattern requires N >= 8"
  const CDS = 2 * (N div L)

  # Polynomial coefficients: [1, 2, 3, 4, 7, 7, 7, 7, 13, 13, ...]
  # FK20 needs field elements (for FFT), MSM needs BigInt (for scalar mult)
  result.testPoly.coefs[0].fromUint(1)
  result.testPoly.coefs[1].fromUint(2)
  result.testPoly.coefs[2].fromUint(3)
  result.testPoly.coefs[3].fromUint(4)
  for i in 4 ..< 8:
    result.testPoly.coefs[i].fromUint(7)
  for i in 8 ..< N:
    result.testPoly.coefs[i].fromUint(13)

  # Convert to BigInt for kzg_commit MSM
  result.testPolyBig.coefs.asUnchecked().batchFromField(result.testPoly.coefs.asUnchecked(), N)

  # Powers of tau - SRS is [G, τG, τ²G, ...]
  # Note: tau is "toxic waste" - not exposed after trusted setup
  var tau: Fr[BLS12_381]
  tau.fromHex(tauHex)
  result.powers_of_tau_G1.coefs.computePowersOfTauG1(tau)
  result.powers_of_tau_G2.coefs.computePowersOfTauG2(tau)

  # Domain setup using fft_utils for proper root computation
  # - omegaForFFT: CDS-th root used for FFT descriptor creation
  # - rootsOfUnity: precomputed maxWidth-th roots of unity (natural order)
  #   used as the full evaluation domain in verification
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

  result.rootsOfUnity = computeRootsOfUnity(Fr[BLS12_381], maxWidth)
