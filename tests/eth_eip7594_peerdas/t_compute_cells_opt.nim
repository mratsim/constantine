# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

## Test suite comparing compute_cells (half-FFT optimization) vs compute_cells_naive
##
## This verifies that the optimized half-FFT implementation produces identical
## results to the naive O(n²) reference implementation.
##
## Run with
##   nim c -r -d:release --hints:off --warnings:off --outdir:build/wip --nimcache:nimcache/wip tests/eth_eip7594_peerdas/t_compute_cells_opt.nim
##
## If there is an internal error, you may remove -d:release to get the full stacktrace
## however for regular runs, the naive algorithm are very slow

import
  # Standard library
  std/[os, strutils, streams, unittest],
  # 3rd party
  pkg/yaml,
  # Internals
  constantine/eth_eip7594_peerdas {.all.},
  constantine/ethereum_eip4844_kzg,
  constantine/serialization/codecs,
  # Shared test utilities
  ../testutils/eth_consensus_utils
# ---------------------------------------------------------
# Spec implementation of compute cells ~340x slower than prod

import
  constantine/named/algebras,
  constantine/math/polynomials/polynomials,
  constantine/math/arithmetic,
  constantine/serialization/codecs_status_codes,
  constantine/platforms/bithacks

func zeroPad[N, ExtN: static int, Field](
       dst: var PolynomialCoef[ExtN, Field],
       src: PolynomialCoef[N, Field]) =
  ## Zero-pad polynomial coefficients from size N to size ExtN.
  ## ExtN must be >= N.
  ##
  ## @param dst: Output polynomial with extended size
  ## @param src: Input polynomial with original size
  static:
    doAssert ExtN >= N, "Extended size must be >= original size"

  for i in 0 ..< N:
    dst.coefs[i] = src.coefs[i]
  for i in N ..< ExtN:
    dst.coefs[i].setZero()

func compute_cells_naive(
       ctx: ptr EthereumKZGContext,
       blob: Blob,
       cells: var array[CELLS_PER_EXT_BLOB, Cell]): cttEthKzgStatus =
  ## Compute all cells for an extended blob using the naive O(n²) algorithm.
  ## This follows the consensus-specs exactly and serves as the reference
  ## implementation for test vector validation.
  ##
  ## Algorithm (following spec exactly):
  ## 1. Convert blob to polynomial (evaluation form)
  ## 2. Convert to coefficient form via IFFT
  ## 3. Zero-pad to extended domain (8192 coefficients)
  ## 4. For each cell, evaluate polynomial at bit-reversed roots of unity
  ##    KEY DETAIL: Cells are defined over BIT-REVERSED roots of unity!
  ##    coset_k = {w_br[k*L], w_br[k*L+1], ..., w_br[k*L+L-1]}
  ##    where w_br[i] = bit_reversed_roots_of_unity[i]
  ## 5. Convert cells to bytes
  ##
  ## Complexity: O(n²) - evaluates polynomial at each point individually
  ## Performance: ~370x slower than half-FFT optimization

  const
    N = FIELD_ELEMENTS_PER_BLOB
    L = FIELD_ELEMENTS_PER_CELL
    CELLS = CELLS_PER_EXT_BLOB

  # Step 1: Deserialize blob to polynomial (evaluation form)
  var polynomial {.noInit.}: PolynomialEval[N, Fr[BLS12_381]]
  let status = blob_to_field_polynomial(polynomial.addr, blob)
  case status
  of cttCodecScalar_Success:
    discard
  of cttCodecScalar_Zero:
    return cttEthKzg_ScalarZero
  of cttCodecScalar_ScalarLargerThanCurveOrder:
    return cttEthKzg_ScalarLargerThanCurveOrder

  # Step 2: Convert to coefficient form via IFFT
  var poly_coeff_N: PolynomialCoef[N, Fr[BLS12_381]]
  poly_coeff_N.lagrangeInterpolate(polynomial, ctx.fft_desc_ext)

  # Step 3: Zero-pad to extended domain (8192 coefficients)
  var poly_coeff_ext: PolynomialCoef[2*N, Fr[BLS12_381]]
  poly_coeff_ext.zeroPad(poly_coeff_N)

  # Step 4: Compute cells by evaluating at bit-reversed roots of unity
  # CRITICAL: This is the key detail that makes test vectors pass!
  # Each cell's evaluations are at consecutive bit-reversed roots of unity.
  var cells_evals: array[CELLS, array[L, Fr[BLS12_381]]]

  const ext_size = 2 * N
  const bits = log2_vartime(uint32 ext_size)

  for i in 0 ..< CELLS:
    for j in 0 ..< L:
      let br_idx = reverse_bits(uint32(i * L + j), bits)
      let z = ctx.fft_desc_ext.rootsOfUnity[br_idx]
      evalPolyAt(cells_evals[i][j], poly_coeff_ext, z)

  # Step 5: Convert cells to bytes
  for i in 0 ..< CELLS:
    cosetEvalsToCell(cells_evals[i], cells[i])

  return cttEthKzg_Success

# ---------------------------------------------------------

func isSequence(node: YamlNode): bool =
  node.kind == ySequence

proc parseCells(expected: YamlNode): seq[Cell] =
  ## Deserialize cells from YAML output.
  if not expected.isSequence():
    return @[]
  result = newSeq[Cell]()
  for elem in expected.elems:
    var cell{.noInit.}: Cell
    cell.fromHex(elem.content)
    result.add(cell)

const test_case = "compute_cells_case_valid_2"

suite "EIP-7594 PeerDAS - compute_cells [" & test_case & "]":
  let ctx = getTrustedSetup()

  test "compute_cells_naive vs test vector":
    ## Verify compute_cells_naive matches official test vectors
    const TestFile =
      currentSourcePath.rsplit(DirSep, 1)[0] /
      ".." / ".." / "tests" / "protocol_ethereum_eip7594_fulu_peerdas" /
      "compute_cells" / "kzg-mainnet" /
      test_case / "data.yaml"

    let testData = loadVectors(TestFile)

    let blobHex = testData["input"]["blob"].content
    var blob = new(array[BYTES_PER_BLOB, byte])
    blob[].fromHex(blobHex)

    var cells: array[CELLS_PER_EXT_BLOB, Cell]
    let status = compute_cells_naive(ctx, blob[], cells)

    doAssert status == cttEthKzg_Success, "compute_cells_naive failed: " & $status
    let expectedCells = testData["output"].parseCells()
    doAssert @cells == expectedCells, "compute_cells_naive doesn't match test vector"
    echo "  ✅ compute_cells_naive matches test vector"

  test "compute_cells vs test vector":
    ## Verify optimized compute_cells matches official test vectors
    const TestFile =
      currentSourcePath.rsplit(DirSep, 1)[0] /
      ".." / ".." / "tests" / "protocol_ethereum_eip7594_fulu_peerdas" /
      "compute_cells" / "kzg-mainnet" /
      test_case / "data.yaml"

    let testData = loadVectors(TestFile)

    let blobHex = testData["input"]["blob"].content
    var blob = new(array[BYTES_PER_BLOB, byte])
    blob[].fromHex(blobHex)

    var cells_opt: array[CELLS_PER_EXT_BLOB, Cell]

    let status = compute_cells(ctx, blob[], cells_opt)

    doAssert status == cttEthKzg_Success, "compute_cells failed: " & $status
    let expectedCells = testData["output"].parseCells()
    doAssert @cells_opt == expectedCells, "compute_cells doesn't match test vector"

    echo "  ✅ compute_cells (half-FFT) matches test vector"

  ctx.trusted_setup_delete()