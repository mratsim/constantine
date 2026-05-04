import
  # Internals
  constantine/platforms/abstractions,
  constantine/named/[algebras, zoo_subgroups],
  constantine/math/[arithmetic, extension_fields],
  constantine/math/elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_jacobian,
    ec_shortweierstrass_batch_ops,
    ec_multi_scalar_mul,
    ec_multi_scalar_mul_precomp
  ],
  # Debugging
  constantine/math/io/[io_bigints, io_ec],
  # Test utilities
  helpers/prng_unsafe


{.push raises: [].}

type
  BLS12_381_G1_Jac = EC_ShortW_Jac[Fp[BLS12_381], G1]
  BLS12_381_G1_Aff = EC_ShortW_Aff[Fp[BLS12_381], G1]

proc testConfig[N, t, b: static int](label: string, samples: int, seed: uint64) =
  echo "Test: ", label
  var rng: RngState
  rng.seed(seed)

  var basisJac = new array[N, BLS12_381_G1_Jac]
  var basis = new array[N, BLS12_381_G1_Aff]
  for i in 0..<N:
    basisJac[i] = rng.random_unsafe(BLS12_381_G1_Jac)
    # Endomorphism acceleration is only valid if in the prime order subgroup
    # for non-precomp multiScalarMul_vartime
    basisJac[i].clearCofactor()

  basis[].batchAffine_vartime(basisJac[])

  var precomp: PrecomputedMSM[BLS12_381_G1_Jac, N, t, b]
  precomp.init(basis[])

  echo "  Table size: ", tableLen(precomp), " points"

  var scalars = new array[N, BigInt[255]]
  var resultPrecomp, resultRef: BLS12_381_G1_Jac

  for _ in 0..<samples:
    for i in 0..<N:
      scalars[i] = rng.random_unsafe(BigInt[255])

    precomp.msm_vartime(resultPrecomp, scalars[])
    resultRef.multiScalarMul_vartime(scalars[], basis[])

    doAssert bool(resultPrecomp == resultRef)
  echo "  PASSED"

when isMainModule:
  testConfig[4, 4, 3]("N=4, t=4, b=3", samples = 10, seed = 42)
  testConfig[256, 32, 12]("N=256, t=32, b=12 (Verkle)", samples = 5, seed = 42)
  testConfig[128, 128, 12]("N=128, t=128, b=12 (FK20-like)", samples = 3, seed = 42)
  echo "\nAll tests passed!"
