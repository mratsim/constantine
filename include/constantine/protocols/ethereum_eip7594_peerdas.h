/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
#ifndef __CTT_H_ETHEREUM_EIP7594_PEERDAS__
#define __CTT_H_ETHEREUM_EIP7594_PEERDAS__

#include "constantine/protocols/ethereum_eip4844_kzg.h"

#ifdef __cplusplus
extern "C" {
#endif

// Ethereum EIP-7594 PeerDAS constants
// ------------------------------------------------------------------------------------------------

#define CTT_FIELD_ELEMENTS_PER_CELL  64
#define CTT_CELLS_PER_EXT_BLOB       128
#define CTT_BYTES_PER_CELL           (CTT_FIELD_ELEMENTS_PER_CELL * 32)
#define CTT_CELLS_PER_BLOB           64

// Ethereum EIP-7594 PeerDAS types
// ------------------------------------------------------------------------------------------------

typedef struct { byte raw[CTT_BYTES_PER_CELL]; } ctt_eth_kzg_cell;

// Ethereum EIP-7594 PeerDAS Interface
// ------------------------------------------------------------------------------------------------

/** Compute all cells and KZG proofs for an extended blob using the FK20 algorithm.
 *
 *  @param ctx        KZG context (trusted setup)
 *  @param cells      Output: array of 128 cells (caller-allocated)
 *  @param proofs     Output: array of 128 KZG proofs (caller-allocated)
 *  @param blob       Input: the blob to compute cells/proofs for
 *  @return           cttEthKzg_Success on success, error status otherwise
 */
ctt_eth_kzg_status ctt_eth_kzg_compute_cells_and_kzg_proofs(
        const ctt_eth_kzg_context* ctx,
        ctt_eth_kzg_cell* cells,
        ctt_eth_kzg_proof* proofs,
        const ctt_eth_kzg_blob* blob
) __attribute__((warn_unused_result));

/** Verify a batch of cell KZG proofs against their commitments.
 *
 *  @param ctx                KZG context (trusted setup)
 *  @param commitments        Array of commitments (one per cell, may contain duplicates)
 *  @param cell_indices       Array of cell indices (one per cell)
 *  @param cells              Array of cells to verify
 *  @param proofs             Array of KZG proofs to verify
 *  @param num_cells          Number of cells in the batch
 *  @param secure_random_bytes 32 bytes of cryptographically secure random data
 *                             (or Fiat-Shamir derived) to prevent rogue commitment attacks
 *  @return                   cttEthKzg_Success if all proofs valid,
 *                            cttEthKzg_VerificationFailure if any proof invalid,
 *                            other error status for invalid inputs
 */
ctt_eth_kzg_status ctt_eth_kzg_verify_cell_kzg_proof_batch(
        const ctt_eth_kzg_context* ctx,
        const ctt_eth_kzg_commitment* commitments,
        const uint64_t* cell_indices,
        const ctt_eth_kzg_cell* cells,
        const ctt_eth_kzg_proof* proofs,
        size_t num_cells,
        const byte secure_random_bytes[32]
) __attribute__((warn_unused_result));

/** Recover all cells and KZG proofs from a subset of available cells.
 *
 *  Requires at least 64 out of 128 cells (≥50% of the extended blob).
 *
 *  @param ctx              KZG context (trusted setup)
 *  @param recovered_cells  Output: array of 128 recovered cells (caller-allocated)
 *  @param recovered_proofs Output: array of 128 recovered KZG proofs (caller-allocated)
 *  @param cell_indices     Array of indices for the provided cells (sorted, unique)
 *  @param cells            Array of available cells
 *  @param num_cells        Number of available cells (must be in [64, 128])
 *  @note Precondition: The caller must ensure that `cells` and `cell_indices`
 *        arrays are allocated with at least `num_cells` elements, and that
 *        `recovered_proofs` and `recovered_cells` are allocated with exactly
 *        CELLS_PER_EXT_BLOB (128) elements each.
 *        The `cell_indices` array must be sorted in strictly ascending order
 *        with values in [0, CELLS_PER_EXT_BLOB).
 *  @return                 cttEthKzg_Success on success, error status otherwise
 */
ctt_eth_kzg_status ctt_eth_kzg_recover_cells_and_kzg_proofs(
        const ctt_eth_kzg_context* ctx,
        ctt_eth_kzg_cell* recovered_cells,
        ctt_eth_kzg_proof* recovered_proofs,
        const uint64_t* cell_indices,
        const ctt_eth_kzg_cell* cells,
        size_t num_cells
) __attribute__((warn_unused_result));

#ifdef __cplusplus
}
#endif

#endif // __CTT_H_ETHEREUM_EIP7594_PEERDAS__
