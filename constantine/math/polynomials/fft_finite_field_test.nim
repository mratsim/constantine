import
  unittest,
  constantine/math/arithmetic,
  constantine/math/io/io_fields,
  #constantine/math/elliptic/ec_shortweierstrass,
  #constantine/named/zoo_generators,
  constantine/named/[algebras, properties_fields, properties_curves],
  constantine/math/elliptic/[ec_shortweierstrass_affine, ec_shortweierstrass_jacobian, ec_scalar_mul, ec_multi_scalar_mul, ec_scalar_mul_vartime],
  #constantine/math/constants/zoo_fields,
  #constantine/math/constants/zoo_subgroups,
  #constantine/protocols/bls_signatures,
  # Assume the FFT implementations are in these modules:
  ./fft_fields,
  ./fft
  #fft_elliptic_curve

type
  EC = EC_ShortW_Jac[Fp[BLS6_6], G1]

suite "FFT Tests":
  test "FFT over Finite Field Fp[Fake13]":

    type F = Fp[Fake13]

    # Fr[Fake13] is GF(13)
    let order = 4  # We'll use a small order for the test
    # `5` is a generator for the order `4`, because `5^4 mod 13 = 1`:
    # `5^0 mod 13 = 1 `
    # `5^1 mod 13 = 5 `
    # `5^2 mod 13 = 12`
    # `5^3 mod 13 = 8 `
    # `5^4 mod 13 = 1 `
    let Gen = F.fromUInt(5'u64)
    var fftDesc = FFTDescriptor[Fp[Fake13]].init(order, Gen)
    defer: fftDesc.delete()

    # Input values
    # Describes Polynomial:
    # P(x) = a₀ + a₁·x + a₂·x² + a₃·x³
    # P(x) = 1 + 2·x + 3·x² + 4·x³
    var input = @[F.fromInt(1), F.fromInt(2), F.fromInt(3), F.fromInt(4)]
    var output = newSeq[F](order)

    # Perform forward FFT
    # The forward FFT returns the evaluation of polynomial P(x) at the
    # roots of unity based on `Gen`
    let status = fftDesc.fft_vartime(output, input)
    check (status == FFTS_Success).bool

    # Expected output (calculated manually or with a known-good implementation)
    let expected = @[
      # let `g(i) = 5^i mod 13` # where `5` is the generator, i.e. `5^4 mod 13 = 1`
      F.fromUInt(10'u64),  # P(g(0)) = (1 + 2·1  + 3·1²  + 4·1³ ) mod 13 = 10
      F.fromUInt(1'u64),   # P(g(1)) = (1 + 2·5  + 3·5²  + 4·5³ ) mod 13 = 1
      F.fromUInt(11'u64),  # P(g(2)) = (1 + 2·12 + 3·12² + 4·12³) mod 13 = 11
      F.fromUInt(8'u64)    # P(g(3)) = (1 + 2·8  + 3·8²  + 4·8³ ) mod 13 = 8
    ]

    for i in 0 ..< output.len:
      echo "Output: ", output[i].toHex()
      echo "Expect: ", expected[i].toHex()
      check (output[i] == expected[i]).bool

    # Perform inverse FFT
    var inverse_output = newSeq[F](order)
    let inverse_status = fftDesc.ifft_vartime(inverse_output, output)
    check (inverse_status == FFTS_Success).bool

    # Check if we get back the original input
    for i in 0 ..< order:
      echo "Inverse results in: ", inverse_output[i].toDecimal()
      check (inverse_output[i] == input[i]).bool

  test "FFT over finite field Fr[BN254_Snarks]":
    type F = Fr[BN254_Snarks]

    const order = 4
    var fftDesc = FFTDescriptor[Fr[BN254_Snarks]].init(order)
    defer: fftDesc.delete()


    echo fftDesc.rouGen.toHex()

    # Input values
    # Describes Polynomial:
    # P(x) = a₀ + a₁·x + a₂·x² + a₃·x³
    # P(x) = 1 + 2·x + 3·x² + 4·x³
    var input = @[F.fromInt(1), F.fromInt(2), F.fromInt(3), F.fromInt(4)]
    var output = newSeq[F](order)

    # Perform forward FFT
    # The forward FFT returns the evaluation of polynomial P(x) at the
    # roots of unity based on `Gen`
    let status = fftDesc.fft_vartime(output, input)
    check (status == FFTS_Success).bool

    for i in 0 ..< output.len:
      echo "Output: ", output[i].toHex()
      #echo "Expect: ", expected[i].toHex()
      #check (output[i] == expected[i]).bool

    # Perform inverse FFT
    var inverse_output = newSeq[F](order)
    let inverse_status = fftDesc.ifft_vartime(inverse_output, output)
    check (inverse_status == FFTS_Success).bool

    # Check if we get back the original input
    for i in 0 ..< order:
      echo "Inverse results in: ", inverse_output[i].toDecimal()
      check (inverse_output[i] == input[i]).bool


## XXX: Also broken! Same as `fft.nim` main part!
#  test "FFT over Elliptic Curve EC[Fp[BLS6_6], G1]":
#    proc getROU(): Fr[BLS6_6] =
#      result = Fr[BLS6_6].fromUint(3'u32)
#
#    proc getGenG1(): EC =
#      let fx = Fp[BLS6_6].fromUint(13'u32)
#      let fy = Fp[BLS6_6].fromUint(15'u32)
#      var gen {.noinit.}: EC_ShortW_Aff[Fp[BLS6_6], G1]
#      gen.x = fx
#      gen.y = fy
#      result = gen.getJacobian()
#
#
#    let order = 4  # We'll use a small order for the test
#    var fftDesc = ECFFTDescriptor[EC].new(order, getROU())
#    defer: fftDesc.delete()
#
#    # Input values (multiples of the generator point)
#    var input = newSeq[EC](order)
#    let generator = getGenG1() #BLS6_6.getGenerator("G1")
#    for i in 0 ..< order:
#      input[i].scalarMul(Fr[BLS6_6].fromInt((i + 1).uint), generator)
#
#    var output = newSeq[EC](order)
#
#    # Perform forward EC-FFT
#    let status = fftDesc.fft_vartime(output, input)
#    check(status == FFTS_Success)
#
#    # Expected output (calculated manually or with a known-good implementation)
#    # Note: This would depend on the specific curve parameters and roots of unity used
#    # For this test, we'll just check some properties instead of exact values
#
#    # Check that the output points are on the curve
#    for point in output:
#      check(point.isOnCurve())
#
#    # Perform inverse EC-FFT
#    var inverse_output = newSeq[EC](order)
#    let inverse_status = fftDesc.ifft_vartime(inverse_output, output)
#    check(inverse_status == FFTS_Success)
#
#    # Check if we get back the original input
#    for i in 0 ..< order:
#      check(inverse_output[i] == input[i])
#
