import
  unittest,
  constantine/math/arithmetic,
  constantine/math/io/[io_fields, io_bigints],
  constantine/named/[algebras, properties_fields, properties_curves],
  constantine/math/elliptic/[ec_shortweierstrass_affine, ec_shortweierstrass_jacobian, ec_scalar_mul, ec_multi_scalar_mul, ec_scalar_mul_vartime],
  constantine/math/polynomials/[fft_fields, fft]

## NOTE: This test must be compiled with `-d:CTT_TEST_CURVES`

suite "FFT Tests (finite fields)":
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
    var fftDesc = FFTDescriptor[F].init(order, Gen)
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
      check (output[i] == expected[i]).bool

    # Perform inverse FFT
    var inverse_output = newSeq[F](order)
    let inverse_status = fftDesc.ifft_vartime(inverse_output, output)
    check (inverse_status == FFTS_Success).bool

    # Check if we get back the original input
    for i in 0 ..< order:
      check (inverse_output[i] == input[i]).bool

  test "FFT over finite field Fr[BN254_Snarks]":
    type F = Fr[BN254_Snarks]

    const order = 4
    var fftDesc = FFTDescriptor[F].init(order)
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

    template toFr(s: string): untyped = F.fromBig(matchingOrderBigInt(BN254_Snarks).fromHex(s, bigEndian))
    let expected = @[
      toFr "0x000000000000000000000000000000000000000000000000000000000000000a",
      toFr "0x00000000000000016789af3a83522eb1969386a2f88c094a419fe246c11f9394",
      toFr "0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593efffffff",
      toFr "0x30644e72e131a02850c6967bfe2f29ab91a061a5812d67470242134d2ee06c69"
    ]

    for i in 0 ..< output.len:
      check (output[i] == expected[i]).bool

    # Perform inverse FFT
    var inverse_output = newSeq[F](order)
    let inverse_status = fftDesc.ifft_vartime(inverse_output, output)
    check (inverse_status == FFTS_Success).bool

    # Check if we get back the original input
    for i in 0 ..< order:
      check (inverse_output[i] == input[i]).bool
