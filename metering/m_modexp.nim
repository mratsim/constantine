# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/metering/[reports, tracer],
  constantine/ethereum_evm_precompiles,
  constantine/platforms/abstractions

let input = [
    # Length of base (1)
    uint8 0x00,
          0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,

    # Length of exponent (1)
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,

    # Length of modulus (121)
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x79,

    # Base
    0x33,

    # Exponent
    0x07,

    # Modulus
    0x04, 0xea, 0xbb, 0x12, 0x55, 0x88, 0xd7, 0x3c, 0xad, 0x22, 0xea, 0x2b, 0x4a, 0x77, 0x6e, 0x9d,
    0x4d, 0xfc, 0x13, 0xa8, 0x1b, 0xf9, 0x0c, 0x0d, 0x37, 0xe8, 0x4e, 0x8b, 0xeb, 0xb2, 0xa5, 0x48,
    0x8b, 0x2c, 0x87, 0x6d, 0x13, 0x51, 0x75, 0xeb, 0x97, 0xc6, 0x13, 0xd9, 0x06, 0xce, 0x8b, 0x53,
    0xd0, 0x02, 0x68, 0xb8, 0xd6, 0x12, 0xab, 0x8b, 0x15, 0x0c, 0xef, 0x0a, 0xd0, 0x3b, 0x73, 0xd2,
    0xdb, 0x9d, 0x2a, 0xa5, 0x23, 0x70, 0xdc, 0x26, 0x55, 0x80, 0xca, 0xf2, 0xc0, 0x18, 0xe3, 0xe3,
    0x1b, 0xad, 0xd5, 0x22, 0xdd, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x1c, 0x05, 0x71, 0x52, 0x7c, 0x3a, 0xb0, 0x77,
  ]

var r = newSeq[byte](121)

resetMetering()

let status = eth_evm_modexp(r, input)
doAssert status == cttEVM_Success

const flags = if UseASM_X86_64 or UseASM_X86_32: "UseAssembly" else: "NoAssembly"
reportCli(Metrics, flags)
