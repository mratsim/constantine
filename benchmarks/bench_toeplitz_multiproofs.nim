# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#       Toeplitz Matrix-Vector Multiplication Benchmarks
#
# ############################################################
#
# Benchmarks for functions from constantine/math/matrix/toeplitz.nim
# Used in FK20 multi-proof computation for PeerDAS
#

import
  # Benchmark infrastructure
  ./bench_blueprint,
  # Toeplitz functions
  constantine/math/matrix/toeplitz,
  # FFT descriptors
  constantine/math/polynomials/fft,
  constantine/math/polynomials/polynomials,
  # Trusted setup (for roots of unity)
  constantine/commitments_setups/ethereum_kzg_srs,
  # PRNG
  helpers/prng_unsafe,
  # Math types
  constantine/named/algebras,
  constantine/named/zoo_generators,
  constantine/math/[arithmetic, ec_shortweierstrass],
  constantine/math/io/io_fields,
  # Standard library
  std/[os, strutils, monotimes]

const
  # PeerDAS production parameters
  N = 4096
  L = 64
  CDS = 128
  
  # Test sizes for scaling analysis
  TestSizes = [64, 128, 256]
  
  # Iterations
  ItersSmall = 100   # For fast component ops
  ItersLarge = 10    # For full Toeplitz operations
  ItersScaling = 3   # For scaling analysis
  
  # Random seed
  RngSeed = 42
  
  # Roots of unity (copied from ethereum_kzg_srs for benchmark use)
  ctt_eth_kzg_fr_pow2_roots_of_unity = [
    Fr[BLS12_381].fromHex"0x1",
    Fr[BLS12_381].fromHex"0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000000",
    Fr[BLS12_381].fromHex"0x8d51ccce760304d0ec030002760300000001000000000000",
    Fr[BLS12_381].fromHex"0x345766f603fa66e78c0625cd70d77ce2b38b21c28713b7007228fd3397743f7a",
    Fr[BLS12_381].fromHex"0x20b1ce9140267af9dd1c0af834cec32c17beb312f20b6f7653ea61d87742bcce",
    Fr[BLS12_381].fromHex"0x50e0903a157988bab4bcd40e22f55448bf6e88fb4c38fb8a360c60997369df4e",
    Fr[BLS12_381].fromHex"0x45af6345ec055e4d14a1e27164d8fdbd2d967f4be2f951558140d032f0a9ee53",
    Fr[BLS12_381].fromHex"0x6898111413588742b7c68b4d7fdd60d098d0caac87f5713c5130c2c1660125be",
    Fr[BLS12_381].fromHex"0x4f9b4098e2e9f12e6b368121ac0cf4ad0a0865a899e8deff4935bd2f817f694b",
    Fr[BLS12_381].fromHex"0x95166525526a65439feec240d80689fd697168a3a6000fe4541b8ff2ee0434e",
    Fr[BLS12_381].fromHex"0x325db5c3debf77a18f4de02c0f776af3ea437f9626fc085e3c28d666a5c2d854",
    Fr[BLS12_381].fromHex"0x6d031f1b5c49c83409f1ca610a08f16655ea6811be9c622d4a838b5d59cd79e5",
    Fr[BLS12_381].fromHex"0x564c0a11a0f704f4fc3e8acfe0f8245f0ad1347b378fbf96e206da11a5d36306",
    Fr[BLS12_381].fromHex"0x485d512737b1da3d2ccddea2972e89ed146b58bc434906ac6fdd00bfc78c8967",
    Fr[BLS12_381].fromHex"0x56624634b500a166dc86b01c0d477fa6ae4622f6a9152435034d2ff22a5ad9e1",
    Fr[BLS12_381].fromHex"0x3291357ee558b50d483405417a0cbe39c8d5f51db3f32699fbd047e11279bb6e",
    Fr[BLS12_381].fromHex"0x2155379d12180caa88f39a78f1aeb57867a665ae1fcadc91d7118f85cd96b8ad",
    Fr[BLS12_381].fromHex"0x224262332d8acbf4473a2eef772c33d6cd7f2bd6d0711b7d08692405f3b70f10",
    Fr[BLS12_381].fromHex"0x2d3056a530794f01652f717ae1c34bb0bb97a3bf30ce40fd6f421a7d8ef674fb",
    Fr[BLS12_381].fromHex"0x520e587a724a6955df625e80d0adef90ad8e16e84419c750194e8c62ecb38d9d",
    Fr[BLS12_381].fromHex"0x3e1c54bcb947035a57a6e07cb98de4a2f69e02d265e09d9fece7e0e39898d4b",
    Fr[BLS12_381].fromHex"0x47c8b5817018af4fc70d0874b0691d4e46b3105f04db5844cd3979122d3ea03a",
    Fr[BLS12_381].fromHex"0xabe6a5e5abcaa32f2d38f10fbb8d1bbe08fec7c86389beec6e7a6ffb08e3363",
    Fr[BLS12_381].fromHex"0x73560252aa0655b25121af06a3b51e3cc631ffb2585a72db5616c57de0ec9eae",
    Fr[BLS12_381].fromHex"0x291cf6d68823e6876e0bcd91ee76273072cf6a8029b7d7bc92cf4deb77bd779c",
    Fr[BLS12_381].fromHex"0x19fe632fd3287390454dc1edc61a1a3c0ba12bb3da64ca5ce32ef844e11a51e",
    Fr[BLS12_381].fromHex"0xa0a77a3b1980c0d116168bffbedc11d02c8118402867ddc531a11a0d2d75182",
    Fr[BLS12_381].fromHex"0x23397a9300f8f98bece8ea224f31d25db94f1101b1d7a628e2d0a7869f0319ed",
    Fr[BLS12_381].fromHex"0x52dd465e2f09425699e276b571905a7d6558e9e3f6ac7b41d7b688830a4f2089",
    Fr[BLS12_381].fromHex"0xc83ea7744bf1bee8da40c1ef2bb459884d37b826214abc6474650359d8e211b",
    Fr[BLS12_381].fromHex"0x2c6d4e4511657e1e1339a815da8b398fed3a181fabb30adc694341f608c9dd56",
    Fr[BLS12_381].fromHex"0x4b5371495990693fad1715b02e5713b5f070bb00e28a193d63e7cb4906ffc93f"
  ]



type
  EC_G1 = EC_ShortW_Jac[Fp[BLS12_381], G1]
  F = Fr[BLS12_381]

proc generateTestPoly(size: int): seq[F] =
  ## Generate random polynomial of given size
  var rng: RngState
  rng.seed(RngSeed + uint32(size))  # Different seed per size
  
  result.setLen(size)
  rng.random_unsafe(result)

proc createFFTDescriptors(size: int): tuple[frDesc: FrFFT_Descriptor[F], ecDesc: ECFFT_Descriptor[EC_G1]] =
  ## Create FFT descriptors for given size
  const roots = ctt_eth_kzg_fr_pow2_roots_of_unity
  
  let scale = log2_vartime(uint32 size)
  let omega = ctt_eth_kzg_fr_pow2_roots_of_unity[scale]
  
  result.frDesc = FrFFT_Descriptor[F].new(order = size, generatorRootOfUnity = omega)
  result.ecDesc = ECFFT_Descriptor[EC_G1].new(order = size, generatorRootOfUnity = omega)

proc report(op: string, size: int, startTime, stopTime: MonoTime, 
            startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stopTime-startTime) div iters)
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    echo &"{op:<60} size {size:>5}    {throughput:>15.3f} ops/s     {ns:>9} ns/op     {(stopClk - startClk) div iters:>9} CPU cycles"
  else:
    echo &"{op:<60} size {size:>5}    {throughput:>15.3f} ops/s     {ns:>9} ns/op"

template bench(op: string, size: int, iters: int, body: untyped): untyped =
  measure(iters, startTime, stopTime, startClk, stopClk, body)
  report(op, size, startTime, stopTime, startClk, stopClk, iters)

proc benchMakeCirculantMatrix_PeerDAS(poly: openArray[F], iters: int) =
  ## Build circulant matrices for all 64 offsets (PeerDAS size)
  ## Total time / 64 = per-offset cost
  
  var coeffs: array[CDS, F]
  let stride = L  # 64
  
  bench("makeCirculantMatrix_peerDAS", CDS, iters):
    for offset in 0 ..< L:
      makeCirculantMatrix(coeffs.toOpenArray(0, CDS-1), poly, offset, stride)

proc benchMakeCirculantMatrix_VaryingOffset(poly: openArray[F], 
                                            offsets: openArray[int], 
                                            iters: int) =
  ## Test circulant construction for specific offsets
  
  var coeffs: array[CDS, F]
  
  for offset in offsets:
    bench(&"makeCirculantMatrix_offset{offset}", CDS, iters):
      makeCirculantMatrix(coeffs.toOpenArray(0, CDS-1), poly, offset, L)

proc benchToeplitzMatVecMulPreFFT_Size128(circulant: openArray[F], 
                                          vFft: openArray[EC_G1], 
                                          frDesc: FrFFT_Descriptor[F], 
                                          ecDesc: ECFFT_Descriptor[EC_G1], 
                                          iters: int) =
  ## Core FK20 multiplication: size 128, no accumulation
  
  var output: array[CDS, EC_G1]
  
  bench("toeplitzMatVecMulPreFFT_size128", CDS, iters):
    let status = toeplitzMatVecMulPreFFT(
      output.toOpenArray(0, CDS-1),
      circulant,
      vFft,
      frDesc,
      ecDesc,
      accumulate = false
    )
    doAssert status == FFT_Success

proc benchToeplitzMatVecMulPreFFT_Accumulate(circulant: openArray[F], 
                                             vFft: openArray[EC_G1], 
                                             frDesc: FrFFT_Descriptor[F], 
                                             ecDesc: ECFFT_Descriptor[EC_G1], 
                                             iters: int) =
  ## With accumulation (accumulate=true)
  
  var output: array[CDS, EC_G1]
  # Initialize output
  for i in 0 ..< CDS:
    output[i].setNeutral()
  
  bench("toeplitzMatVecMulPreFFT_accumulate", CDS, iters):
    let status = toeplitzMatVecMulPreFFT(
      output.toOpenArray(0, CDS-1),
      circulant,
      vFft,
      frDesc,
      ecDesc,
      accumulate = true
    )
    doAssert status == FFT_Success

proc benchToeplitzMatVecMulPreFFT_NoAccumulate(circulant: openArray[F], 
                                               vFft: openArray[EC_G1], 
                                               frDesc: FrFFT_Descriptor[F], 
                                               ecDesc: ECFFT_Descriptor[EC_G1], 
                                               iters: int) =
  ## Without accumulation (accumulate=false)
  
  var output: array[CDS, EC_G1]
  
  bench("toeplitzMatVecMulPreFFT_noAccumulate", CDS, iters):
    let status = toeplitzMatVecMulPreFFT(
      output.toOpenArray(0, CDS-1),
      circulant,
      vFft,
      frDesc,
      ecDesc,
      accumulate = false
    )
    doAssert status == FFT_Success

proc benchToeplitz_Scaling(sizes: openArray[int], iters: int) =
  ## Scaling analysis for different Toeplitz sizes
  
  for size in sizes:
    let poly = generateTestPoly(size)
    var coeffs = newSeq[F](2 * size)
    
    makeCirculantMatrix(coeffs.toOpenArray(0, 2*size-1), poly, 0, 1)
    
    let descs = createFFTDescriptors(2 * size)
    
    var input = newSeq[EC_G1](size)
    input[0].setGenerator()
    for i in 1 ..< size:
      input[i].mixedSum(input[i-1], BLS12_381.getGenerator("G1"))
    
    var output = newSeq[EC_G1](size)
    
    bench(&"toeplitzMatVecMul_size{size}", size, iters):
      let status = toeplitzMatVecMul(
        output.toOpenArray(0, size-1),
        coeffs.toOpenArray(0, 2*size-1),
        input.toOpenArray(0, size-1),
        descs.frDesc,
        descs.ecDesc
      )
      doAssert status == FFT_Success

proc main() =
  echo "Toeplitz Matrix-Vector Multiplication Benchmarks (FK20)"
  echo "Random polynomial with seed=", RngSeed
  echo ""
  
  separator(145)
  echo "Circulant Matrix Construction"
  separator(145)
  
  let polyFull = generateTestPoly(N)  # Use full N=4096 poly for PeerDAS circulant
  echo ""
  
  benchMakeCirculantMatrix_PeerDAS(polyFull.toOpenArray(0, N-1), ItersLarge)
  echo ""
  
  let offsets = [0, 1, 32, 63]
  benchMakeCirculantMatrix_VaryingOffset(polyFull.toOpenArray(0, N-1), offsets, ItersLarge)
  echo ""
  
  separator(145)
  echo "Toeplitz MatVecMul (PeerDAS Size)"
  separator(145)
  
  # Setup for size 128 benchmarks
  let descs128 = createFFTDescriptors(CDS)
  var circulant128 = newSeq[F](CDS)
  makeCirculantMatrix(circulant128.toOpenArray(0, CDS-1), polyFull.toOpenArray(0, N-1), 0, L)
  
  var v128 = newSeq[EC_G1](CDS)
  v128[0].setGenerator()
  for i in 1 ..< CDS:
    v128[i].mixedSum(v128[i-1], BLS12_381.getGenerator("G1"))
  
  # For PreFFT benchmarks, FFT the vector directly (no zero-extension needed)
  var vFft128 = newSeq[EC_G1](CDS)
  discard ec_fft_nr(descs128.ecDesc, vFft128.toOpenArray(0, CDS-1), v128.toOpenArray(0, CDS-1))
  
  benchToeplitzMatVecMulPreFFT_Size128(circulant128.toOpenArray(0, CDS-1), vFft128.toOpenArray(0, CDS-1), descs128.frDesc, descs128.ecDesc, ItersLarge)
  echo ""
  
  benchToeplitzMatVecMulPreFFT_Accumulate(circulant128.toOpenArray(0, CDS-1), vFft128.toOpenArray(0, CDS-1), descs128.frDesc, descs128.ecDesc, ItersLarge)
  echo ""
  
  benchToeplitzMatVecMulPreFFT_NoAccumulate(circulant128.toOpenArray(0, CDS-1), vFft128.toOpenArray(0, CDS-1), descs128.frDesc, descs128.ecDesc, ItersLarge)
  echo ""
  
  echo "  [Skipping toeplitzMatVecMul_Full - FK20 uses PreFFT version]"
  echo ""
  
  separator(145)
  echo "Scaling Analysis"
  separator(145)
  benchToeplitz_Scaling(TestSizes, ItersScaling)
  echo ""
  
  separator(145)
  echo "Notes"
  separator(145)
  echo "- All benchmarks use random polynomials (seed=42)"
  echo "- PeerDAS parameters: N=4096, L=64, CDS=128"
  echo "- Accumulation mode shows sum_vartime overhead"
  echo "- Full toeplitzMatVecMul includes vector FFT"

when isMainModule:
  main()