# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                    Constantine library
#
# ############################################################

{.push warning[UnusedImport]: off.}

import
  constantine/threadpool,
  ./lib_hashes,
  ./lib_curves,
  constantine/csprngs,
  # Protocols
  constantine/ethereum_bls_signatures,
  constantine/ethereum_bls_signatures_parallel,
  constantine/commitments_setups/ethereum_kzg_srs,
  constantine/ethereum_eip4844_kzg,
  constantine/ethereum_eip4844_kzg_parallel,

  constantine/ethereum_evm_precompiles,

  # Ensure globals like proc from kernel32.dll are populated at library load time
  ./lib_autoload
