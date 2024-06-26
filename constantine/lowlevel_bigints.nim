# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
    ./platforms/abstractions,
    ./math/io/io_bigints

# ############################################################
#
#            Low-level named Finite Fields API
#
# ############################################################

# Warning ⚠️:
#     The low-level APIs have no stability guarantee.
#     Use high-level protocols which are designed according to a stable specs
#     and with misuse resistance in mind.

{.push raises: [].} # No exceptions allowed in core cryptographic operations
{.push inline.}

# Base types
# ------------------------------------------------------------

export abstractions

# BigInt
# ------------------------------------------------------------

func unmarshalBE*(dst: var BigInt, src: openarray[byte]): bool =
  ## Return true on success
  ## Return false if destination is too small compared to source
  return dst.unmarshal(src, bigEndian)

func marshalBE*(dst: var openarray[byte], src: BigInt): bool =
  ## Return true on success
  ## Return false if destination is too small compared to source
  return dst.marshal(src, bigEndian)
