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
  constantine/math/polynomials/[fft_fields, fft_ec],
  constantine/math/polynomials/polynomials,
  # Trusted setup (for roots of unity)
  constantine/commitments_setups/ethereum_kzg_srs {.all.},
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
  let scale = log2_vartime(uint32 size)
  let omega = ctt_eth_kzg4844_fr_pow2_roots_of_unity[scale]
  
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