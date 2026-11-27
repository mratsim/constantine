# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

## Binary fields
##
## - 𝔽₂⁶⁴ = 𝔽₂[x]/(x⁶⁴ + x⁴ + x³ + x + 1): `GF2_64`
## - 𝔽₂¹²⁸ = 𝔽₂⁶⁴[y]/(y² + xy + 1): `GF2_64x2`, a `QuadraticExt[GF2_64]`
##
## the fields of leanVM, with carry-less multiplication
## through PCLMULQDQ on x86-64 and PMULL on ARM64.

import
  ./binary_fields/[gf2_64, gf2_64x2, io_binary_fields]

export gf2_64, gf2_64x2, io_binary_fields
