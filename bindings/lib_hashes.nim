# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                          Hashes
#
# ############################################################

import constantine/zoo_exports

# Modify per-module prefix if needed
# ----------------------------------------
# static:
#   prefix_sha256 = prefix_ffi & "sha256_"

import constantine/hashes

func sha256_hash(digest: var array[32, byte], message: openArray[byte], clearMem: bool) {.libPrefix: "ctt_".} =
  ## Compute the SHA-256 hash of message
  ## and store the result in digest.
  ## Optionally, clear the memory buffer used.

  # There is an extra indirect function call as we use a generic `hash` concept but:
  # - the indirection saves space (instead of duplicating `hash`)
  # - minimal overhead compared to hashing time
  # - Can be tail-call optimized into a goto jump instead of call/return
  # - Can be LTO-optimized
  sha256.hash(digest, message, clearMem)
