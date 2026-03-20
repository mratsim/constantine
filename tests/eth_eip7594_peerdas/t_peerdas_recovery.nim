# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/[os, random, algorithm, strutils, options],
  constantine/named/algebras,
  constantine/math/[arithmetic, ec_shortweierstrass],
  constantine/math/io/io_fields,
  constantine/platforms/[bithacks, views],
  constantine/ethereum_eip4844_kzg,
  constantine/eth_eip7594_peerdas

const TrustedSetupMainnet =
  currentSourcePath.rsplit(DirSep, 1)[0] /
  ".." / ".." / "constantine" /
  "commitments_setups" /
  "trusted_setup_ethereum_kzg4844_reference.dat"

proc trusted_setup*(): ptr EthereumKZGContext =
  var ctx: ptr EthereumKZGContext
  let tsStatus = ctx.trusted_setup_load(TrustedSetupMainnet, kReferenceCKzg4844)
  doAssert tsStatus == tsSuccess, "\n[Trusted Setup Error] " & $tsStatus
  echo "Trusted Setup loaded successfully"
  return ctx

func build_test_blob*(): Blob =
  for i in 0 ..< FIELD_ELEMENTS_PER_BLOB:
    let start = i * BYTES_PER_FIELD_ELEMENT
    var chunk: array[32, byte]
    let val = uint64(i)
    for j in 0 ..< 8:
      chunk[31 - j] = (val shr (8 * j)).byte
    for j in 8 ..< 32:
      chunk[31 - j] = 0
    for j in 0 ..< 32:
      result[start + j] = chunk[j]

proc test_recover_from_64_cells*(ctx: ptr EthereumKZGContext) =
  echo "Testing recovery from exactly 64 cells (minimum threshold)..."

  let blob = build_test_blob()
  echo "  Blob created"

  var cells: array[CELLS_PER_EXT_BLOB, Cell]
  let status = ctx.compute_cells(cells, blob)
  echo "  compute_cells status: ", status
  doAssert status == cttEthKzg_Success

  var available_indices: seq[CellIndex]
  var available_cells: seq[Cell]
  for i in 0 ..< CELLS_PER_EXT_BLOB:
    if i < CELLS_PER_EXT_BLOB div 2:
      available_indices.add(CellIndex(i))
      available_cells.add(cells[i])
  echo "  Available cells: ", available_indices.len

  var recovered_cells: array[CELLS_PER_EXT_BLOB, Cell]
  var recovered_proofs: array[CELLS_PER_EXT_BLOB, KZGProof]

  echo "  Calling recover_cells_and_kzg_proofs..."
  let recover_status = ctx.recover_cells_and_kzg_proofs(
    recovered_proofs,
    recovered_cells,
    available_cells,
    available_indices
  )
  doAssert recover_status == cttEthKzg_Success

  for i in 0 ..< CELLS_PER_EXT_BLOB:
    doAssert recovered_cells[i] == cells[i],
      "Recovered cell " & $i & " does not match original"

  echo "  ✓ Recovery from 64 cells PASSED"

proc test_recover_from_65_cells*(ctx: ptr EthereumKZGContext) =
  echo "Testing recovery from 65 cells (above threshold)..."

  let blob = build_test_blob()

  var cells: array[CELLS_PER_EXT_BLOB, Cell]
  let status = ctx.compute_cells(cells, blob)
  doAssert status == cttEthKzg_Success

  var available_indices: seq[CellIndex]
  var available_cells: seq[Cell]
  available_indices.add(CellIndex(0))
  available_cells.add(cells[0])
  for i in 1 ..< CELLS_PER_EXT_BLOB:
    if i < 65:
      available_indices.add(CellIndex(i))
      available_cells.add(cells[i])

  var recovered_cells: array[CELLS_PER_EXT_BLOB, Cell]
  var recovered_proofs: array[CELLS_PER_EXT_BLOB, KZGProof]

  let recover_status = ctx.recover_cells_and_kzg_proofs(
    recovered_proofs,
    recovered_cells,
    available_cells,
    available_indices
  )
  doAssert recover_status == cttEthKzg_Success

  for i in 0 ..< CELLS_PER_EXT_BLOB:
    doAssert recovered_cells[i] == cells[i],
      "Recovered cell " & $i & " does not match original"

  echo "  ✓ Recovery from 65 cells PASSED"

proc test_recover_from_all_cells*(ctx: ptr EthereumKZGContext) =
  echo "Testing recovery when all cells available..."

  let blob = build_test_blob()

  var cells: array[CELLS_PER_EXT_BLOB, Cell]
  let status = ctx.compute_cells(cells, blob)
  doAssert status == cttEthKzg_Success

  var available_indices: seq[CellIndex]
  var available_cells: seq[Cell]
  for i in 0 ..< CELLS_PER_EXT_BLOB:
    available_indices.add(CellIndex(i))
    available_cells.add(cells[i])

  var recovered_cells: array[CELLS_PER_EXT_BLOB, Cell]
  var recovered_proofs: array[CELLS_PER_EXT_BLOB, KZGProof]

  let recover_status = ctx.recover_cells_and_kzg_proofs(
    recovered_proofs,
    recovered_cells,
    available_cells,
    available_indices
  )
  doAssert recover_status == cttEthKzg_Success

  for i in 0 ..< CELLS_PER_EXT_BLOB:
    doAssert recovered_cells[i] == cells[i],
      "Recovered cell " & $i & " does not match original"

  echo "  ✓ Recovery from all cells PASSED"

proc test_recover_alternate_indices*(ctx: ptr EthereumKZGContext) =
  echo "Testing recovery with alternate cell indices (0, 2, 4, ...)..."

  let blob = build_test_blob()

  var cells: array[CELLS_PER_EXT_BLOB, Cell]
  let status = ctx.compute_cells(cells, blob)
  doAssert status == cttEthKzg_Success

  var available_indices: seq[CellIndex]
  var available_cells: seq[Cell]
  for i in 0 ..< CELLS_PER_EXT_BLOB:
    if i mod 2 == 0:
      available_indices.add(CellIndex(i))
      available_cells.add(cells[i])

  var recovered_cells: array[CELLS_PER_EXT_BLOB, Cell]
  var recovered_proofs: array[CELLS_PER_EXT_BLOB, KZGProof]

  let recover_status = ctx.recover_cells_and_kzg_proofs(
    recovered_proofs,
    recovered_cells,
    available_cells,
    available_indices
  )
  doAssert recover_status == cttEthKzg_Success

  for i in 0 ..< CELLS_PER_EXT_BLOB:
    doAssert recovered_cells[i] == cells[i],
      "Recovered cell " & $i & " does not match original"

  echo "  ✓ Recovery with alternate indices PASSED"

proc test_too_few_cells_error*(ctx: ptr EthereumKZGContext) =
  echo "Testing that recovery fails with too few cells..."

  let blob = build_test_blob()

  var cells: array[CELLS_PER_EXT_BLOB, Cell]
  let status = ctx.compute_cells(cells, blob)
  doAssert status == cttEthKzg_Success

  var available_indices: seq[CellIndex]
  var available_cells: seq[Cell]
  for i in 0 ..< 63:
    available_indices.add(CellIndex(i))
    available_cells.add(cells[i])

  var recovered_cells: array[CELLS_PER_EXT_BLOB, Cell]
  var recovered_proofs: array[CELLS_PER_EXT_BLOB, KZGProof]

  let recover_status = ctx.recover_cells_and_kzg_proofs(
    recovered_proofs,
    recovered_cells,
    available_cells,
    available_indices
  )
  doAssert recover_status == cttEthKzg_InputsLengthsMismatch

  echo "  ✓ Too few cells error handling PASSED"

proc test_duplicate_indices_error*(ctx: ptr EthereumKZGContext) =
  echo "Testing that recovery fails with duplicate indices..."

  let blob = build_test_blob()

  var cells: array[CELLS_PER_EXT_BLOB, Cell]
  let status = ctx.compute_cells(cells, blob)
  doAssert status == cttEthKzg_Success

  var available_indices: seq[CellIndex]
  var available_cells: seq[Cell]
  for i in 0 ..< 64:
    available_indices.add(CellIndex(i))
    available_cells.add(cells[i])
  available_indices.add(CellIndex(0))
  available_cells.add(cells[0])

  var recovered_cells: array[CELLS_PER_EXT_BLOB, Cell]
  var recovered_proofs: array[CELLS_PER_EXT_BLOB, KZGProof]

  let recover_status = ctx.recover_cells_and_kzg_proofs(
    recovered_proofs,
    recovered_cells,
    available_cells,
    available_indices
  )
  doAssert recover_status == cttEthKzg_InputsLengthsMismatch

  echo "  ✓ Duplicate indices error handling PASSED"

when isMainModule:
  echo "========================================"
  echo "    PeerDAS Recovery Tests"
  echo "========================================\n"

  let ctx = trusted_setup()
  echo ""

  test_recover_from_64_cells(ctx)
  echo ""

  test_recover_from_65_cells(ctx)
  echo ""

  test_recover_from_all_cells(ctx)
  echo ""

  test_recover_alternate_indices(ctx)
  echo ""

  test_too_few_cells_error(ctx)
  echo ""

  test_duplicate_indices_error(ctx)
  echo ""

  ctx.trusted_setup_delete()

  echo "\n========================================"
  echo "    All PeerDAS Recovery Tests PASSED ✓"
  echo "========================================"
