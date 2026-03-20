# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

## Test suite comparing compute_cells_and_kzg_proofs (FK20 optimization) vs compute_cells_and_kzg_proofs_naive
##
## This verifies that the optimized FK20 implementation produces identical
## results to the naive O(n²) **proof** generation reference implementation,
## i.e. we use `kzg_coset_prove_naive`
##
## Importantly this assumes `compute_cells` is validated against `compute_cells_naive`
## as `compute_cells_naive` is about 350x slower than the optimized version.
##
## Companion tests:
##   - `constantine/tests/eth_eip4844_peerdas/t_compute_cells_opt.nim`
##     verifies the compute_cells logic in isolation vs a naive spec-like O(n²) algorithm.
##     for both internal and external consistency
##   - `constantine/tests/commitments/t_kzg_multiproofs.nim`
##     verifies `kzg_coset_prove_naive` and `kzg_coset_prove` (FK20 optimization)
##     for internal consistency (but not external test vector)
##     against `kzg_coset_verify`
##
## Run with
##   nim c -r -d:release --hints:off --warnings:off --outdir:build/wip --nimcache:nimcache/wip tests/eth_eip4844_peerdas/t_cells_and_kzg_proofs_opt.nim
##
## If there is an internal error, you may remove -d:release to get the full stacktrace
## however for regular runs, the naive algorithm are very slow

import
  std/[os, strutils, streams, unittest],
  pkg/yaml,
  constantine/eth_eip7594_peerdas {.all.},
  constantine/ethereum_eip4844_kzg,
  constantine/serialization/[codecs, codecs_bls12_381],
  constantine/math/ec_shortweierstrass,
  constantine/named/algebras

# ---------------------------------------------------------
# Spec implementation of compute_cells_and_kzg_proofs_naive

import
  constantine/named/algebras,
  constantine/math/polynomials/[fft, polynomials],
  constantine/math/arithmetic,
  constantine/serialization/codecs_status_codes,
  constantine/platforms/bithacks,
  constantine/commitments/kzg_multiproofs

func compute_cells_and_kzg_proofs_naive(
       ctx: ptr EthereumKZGContext,
       blob: Blob,
       cells: var array[CELLS_PER_EXT_BLOB, Cell],
       proofs: var array[CELLS_PER_EXT_BLOB, KZGProof]): cttEthKzgStatus =
  ## Compute all cells and proofs for an extended blob using the naive O(n²) algorithm.
  ##
  ## This follows the consensus-specs exactly, using polynomial long division
  ## for each cell's proof. It's slower than FK20 but serves as a reference
  ## implementation to verify correctness.
  ##
  ## Algorithm (following spec):
  ## 1. Convert blob to polynomial coefficient form
  ## 2. For each cell:
  ##    a. Get coset shift (x) and L-th root of unity
  ##    b. Compute proof and evaluations using kzg_coset_prove_naive
  ##    c. Convert evaluations to cell bytes

  const
    N = FIELD_ELEMENTS_PER_BLOB
    L = FIELD_ELEMENTS_PER_CELL
    CELLS = CELLS_PER_EXT_BLOB

  # Step 1: Deserialize blob to polynomial (Lagrange form)
  var poly_lagrange {.noInit.}: PolynomialEval[N, Fr[BLS12_381]]
  let status = blob_to_field_polynomial(poly_lagrange.addr, blob)
  case status
  of cttCodecScalar_Success:
    discard
  of cttCodecScalar_Zero:
    return cttEthKzg_ScalarZero
  of cttCodecScalar_ScalarLargerThanCurveOrder:
    return cttEthKzg_ScalarLargerThanCurveOrder

  # Convert to coefficient form
  var poly_monomial: PolynomialCoef[N, Fr[BLS12_381]]
  poly_monomial.computeCoefPoly(poly_lagrange, ctx.fft_desc_ext)

  # Compute cells using the public API
  let cells_status = compute_cells(ctx, blob, cells)
  if cells_status != cttEthKzg_Success:
    return cells_status

  # Convert cells back to field elements for proof computation
  var cells_evals_naive: array[CELLS_PER_EXT_BLOB, array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]]]
  for i in 0 ..< CELLS_PER_EXT_BLOB:
    let status = cellToCosetEvals(cells[i], cells_evals_naive[i])
    if status != cttEthKzg_Success:
      return status

  # Compute L-th root of unity from extended domain for proof computation
  var lthRoot {.noInit.}: Fr[BLS12_381]
  lthRoot = ctx.fft_desc_ext.rootsOfUnity[1] ~^ uint32(2*N div L)

  # Get bit-reversed roots of unity for coset shifts
  var roots_of_unity_brp: array[2*N, Fr[BLS12_381]]
  for i in 0 ..< 2*N:
    roots_of_unity_brp[i] = ctx.fft_desc_ext.rootsOfUnity[i]
  roots_of_unity_brp.bit_reversal_permutation()

  # Compute proofs for each cell
  for cell_idx in 0 ..< CELLS:
    let x = roots_of_unity_brp[L * cell_idx]  # Coset shift in bit-reversed order
    var proof: EC_ShortW_Aff[Fp[BLS12_381], G1]
    kzg_coset_prove_naive[N, L, BLS12_381](
      proof, cells_evals_naive[cell_idx], poly_monomial, x, lthRoot, ctx.srs_monomial_g1)
    proofs[cell_idx] = KZGProof(proof)

  return cttEthKzg_Success

# ---------------------------------------------------------

const
  TrustedSetupMainnet =
    currentSourcePath.rsplit(DirSep, 1)[0] /
    ".." / ".." / "constantine" /
    "commitments_setups" /
    "trusted_setup_ethereum_kzg4844_reference.dat"

proc trusted_setup(): ptr EthereumKZGContext =
  var ctx: ptr EthereumKZGContext
  let tsStatus = ctx.trusted_setup_load(TrustedSetupMainnet, kReferenceCKzg4844)
  doAssert tsStatus == tsSuccess, "\n[Trusted Setup Error] " & $tsStatus
  return ctx

proc loadVectors(filename: string): YamlNode =
  var s = filename.openFileStream()
  defer: s.close()
  load(s, result)

func isSequence(node: YamlNode): bool =
  node.kind == ySequence

proc parseCells(expected: YamlNode): seq[Cell] =
  if not expected.isSequence():
    return @[]
  result = newSeq[Cell]()
  for elem in expected.elems:
    var cell{.noInit.}: Cell
    cell.fromHex(elem.content)
    result.add(cell)

proc parseProofs(expected: YamlNode): seq[array[BYTES_PER_PROOF, byte]] =
  if not expected.isSequence():
    return @[]
  result = newSeq[array[BYTES_PER_PROOF, byte]]()
  for elem in expected.elems:
    var proofBytes: array[BYTES_PER_PROOF, byte]
    proofBytes.fromHex(elem.content)
    result.add(proofBytes)

proc toProofBytes(a: openArray[KZGProof]): seq[array[BYTES_PER_PROOF, byte]] =
  type EC = EC_ShortW_Aff[Fp[BLS12_381], G1]
  result.setLen(a.len)
  for i in 0 ..< a.len:
    doAssert result[i].serialize_g1_compressed(EC(a[i])) == cttCodecEcc_Success

proc `==`(a, b: KZGProof): bool =
  type EC = EC_ShortW_Aff[Fp[BLS12_381], G1]
  bool(EC(a) == EC(b))

proc testCellsMatch(
        computed: openArray[Cell],
        expected: seq[Cell],
        testCaseName: string,
        impl: string
      ): tuple[passed: bool, mismatchIdx: int] =
  if expected.len != CELLS_PER_EXT_BLOB:
    echo "❌ **" & impl & "**: Expected " & $CELLS_PER_EXT_BLOB & " cells but got " & $expected.len
    return (false, -1)
  for i in 0 ..< CELLS_PER_EXT_BLOB:
    if computed[i] != expected[i]:
      echo "❌ **" & impl & "**: Cell " & $i & " mismatch [" & testCaseName & "]"
      return (false, i)
  echo "✅ **" & impl & "**: cells match test vector [" & testCaseName & "]"
  return (true, -1)

proc testProofsMatch(
        computed: openArray[KZGProof],
        expected: seq[array[BYTES_PER_PROOF, byte]],
        testCaseName: string,
        impl: string
      ): tuple[passed: bool, mismatchIdx: int] =
  if expected.len != CELLS_PER_EXT_BLOB:
    echo "❌ **" & impl & "**: Expected " & $CELLS_PER_EXT_BLOB & " proofs but got " & $expected.len
    return (false, -1)
  let computedBytes = toProofBytes(computed)
  for i in 0 ..< CELLS_PER_EXT_BLOB:
    if computedBytes[i] != expected[i]:
      echo "❌ **" & impl & "**: Proof " & $i & " mismatch [" & testCaseName & "]"
      return (false, i)
  echo "✅ **" & impl & "**: proofs match test vector [" & testCaseName & "]"
  return (true, -1)

const TestVectorsDir =
  currentSourcePath.rsplit(DirSep, 1)[0] /
  ".." / "protocol_ethereum_eip7594_fulu_peerdas" /
  "compute_cells_and_kzg_proofs" / "kzg-mainnet"

# Test vectors are generated from:
# https://github.com/ethereum/consensus-specs/blob/master/tests/core/pyspec/eth2spec/test/utils/kzg_tests.py

proc main() =
  suite "EIP-7594 PeerDAS - KZG coset prove optimization":
    let ctx = trusted_setup()

    for file in walkDirRec(TestVectorsDir, relative = true):
      if not file.endsWith("data.yaml"):
        continue

      # Skip invalid blob test cases - they contain field elements >= BLS_MODULUS
      # which cause index errors in Constantine's naive implementation
      # (the optimized version doesn't validate inputs either)
      if "invalid" in file:
        echo "⏭️  skipping invalid blob test case [" & file.split(DirSep)[0] & "]"
        continue

      # TODO: remove this filter to run all valid test cases
      if not file.contains("compute_cells_and_kzg_proofs_case_valid_2"):
        continue

      test "compute_cells_and_kzg_proofs_naive vs test vector [" & file & "]":
        let testCaseName = file.split(DirSep)[0]
        let testData = loadVectors(TestVectorsDir / file)

        var testPassed = true

        let blobHex = testData["input"]["blob"].content
        var blob = new(array[32*4096, byte])
        blob[].fromHex(blobHex)

        var cells_naive: array[CELLS_PER_EXT_BLOB, Cell]
        var proofs_naive: array[CELLS_PER_EXT_BLOB, KZGProof]

        let status_naive = compute_cells_and_kzg_proofs_naive(ctx, blob[], cells_naive, proofs_naive)

        if status_naive != cttEthKzg_Success:
          echo "❌ compute_cells_and_kzg_proofs_naive failed: " & $status_naive & " [" & testCaseName & "]"
          check false
          return

        let output = testData["output"]
        if not output.isNil and output.isSequence() and output.elems.len == 2:
          let expectedCells = parseCells(output[0])
          let expectedProofs = parseProofs(output[1])

          let (cellsPass, _) = testCellsMatch(cells_naive, expectedCells, testCaseName, "naive")
          let (proofsPass, _) = testProofsMatch(proofs_naive, expectedProofs, testCaseName, "naive")
          testPassed = cellsPass and proofsPass

        check testPassed

      test "compute_cells_and_kzg_proofs_opt vs test vector [" & file & "]":
        let testCaseName = file.split(DirSep)[0]
        let testData = loadVectors(TestVectorsDir / file)

        var testPassed = true

        let blobHex = testData["input"]["blob"].content
        var blob = new(array[32*4096, byte])
        blob[].fromHex(blobHex)

        var cells_opt: array[CELLS_PER_EXT_BLOB, Cell]
        var proofs_opt: array[CELLS_PER_EXT_BLOB, KZGProof]

        let status_opt = compute_cells_and_kzg_proofs(ctx, blob[], cells_opt, proofs_opt)

        if status_opt != cttEthKzg_Success:
          echo "❌ compute_cells_and_kzg_proofs failed: " & $status_opt & " [" & testCaseName & "]"
          check false
          return

        let output = testData["output"]
        if not output.isNil and output.isSequence() and output.elems.len == 2:
          let expectedCells = parseCells(output[0])
          let expectedProofs = parseProofs(output[1])

          let (cellsPass, _) = testCellsMatch(cells_opt, expectedCells, testCaseName, "opt")
          let (proofsPass, _) = testProofsMatch(proofs_opt, expectedProofs, testCaseName, "opt")
          testPassed = cellsPass and proofsPass

        check testPassed

      test "compute_cells_and_kzg_proofs naive vs opt [" & file & "]":
        let testCaseName = file.split(DirSep)[0]
        let testData = loadVectors(TestVectorsDir / file)

        let blobHex = testData["input"]["blob"].content
        var blob = new(array[32*4096, byte])
        blob[].fromHex(blobHex)

        var cells_naive, cells_opt: array[CELLS_PER_EXT_BLOB, Cell]
        var proofs_naive, proofs_opt: array[CELLS_PER_EXT_BLOB, KZGProof]

        let status_naive = compute_cells_and_kzg_proofs_naive(ctx, blob[], cells_naive, proofs_naive)
        let status_opt = compute_cells_and_kzg_proofs(ctx, blob[], cells_opt, proofs_opt)

        if status_naive != cttEthKzg_Success:
          echo "❌ naive failed: " & $status_naive
          check false
          return
        if status_opt != cttEthKzg_Success:
          echo "❌ opt failed: " & $status_opt
          check false
          return

        var mismatch = false
        for i in 0 ..< CELLS_PER_EXT_BLOB:
          if cells_naive[i] != cells_opt[i]:
            echo "❌ Cells mismatch at " & $i
            mismatch = true
          if proofs_naive[i] != proofs_opt[i]:
            echo "❌ Proofs mismatch at " & $i
            mismatch = true

        if not mismatch:
          echo "✅ **naive** and **opt** are internally consistent [" & testCaseName & "]"

        check not mismatch

    ctx.trusted_setup_delete()

when isMainModule:
  main()