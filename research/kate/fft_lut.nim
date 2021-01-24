# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/macros,
  ../../constantine/config/[curves, common],
  ../../constantine/[arithmetic, primitives],
  ../../constantine/io/io_fields

# TODO automate this
# we can precompute everything in Sage
# and auto-generate the file.

const BLS12_381_Fr_primitive_root = 5

func buildRootLUT(F: type Fr): array[32, F] =
  ## [pow(PRIMITIVE_ROOT, (MODULUS - 1) // (2**i), MODULUS) for i in range(32)]

  var exponent {.noInit.}: BigInt[F.C.getCurveOrderBitwidth()]
  exponent = F.C.getCurveOrder()
  exponent -= One

  # Start by the end
  var i = result.len - 1
  exponent.shiftRight(i)
  result[i].fromUint(BLS12_381_Fr_primitive_root)
  result[i].powUnsafeExponent(exponent)

  while i > 0:
    result[i-1].square(result[i])
    dec i

  debugEcho "Fr[BLS12_81] - Roots of Unity:"
  for i in 0 ..< result.len:
    debugEcho "    ", i, ": ", result[i].toHex()
  debugEcho "Fr[BLS12_81] - Roots of Unity -- FIN\n"

let BLS12_381_Fr_ScaleToRootOfUnity* = buildRootLUT(Fr[BLS12_381])

{.experimental: "dynamicBindSym".}
macro scaleToRootOfUnity*(C: static Curve): untyped =
  return bindSym($C & "_Fr_ScaleToRootOfUnity")
