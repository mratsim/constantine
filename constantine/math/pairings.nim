# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./config/curves,
  ./pairing/[pairing_bn, pairing_bls12],
  ./extension_fields

func pairing*[C](gt: var Fp12[C], P, Q: auto) {.inline.} =
  when family(C) == BarretoNaehrig:
    pairing_bn(gt, P, Q)
  elif family(C) == BarretoLynnScott:
    pairing_bls12(gt, P, Q)
  else:
    {.error: "Pairing not implemented for " & $C.}