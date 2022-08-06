# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/curves,
  ../io/io_extfields

{.used.}

# Hash-to-Curve Shallue-van de Woestijne BN254_Snarks G2 map
# -----------------------------------------------------------------
# Spec:
# - https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-14#appendix-F.1

const BN254_Snarks_h2c_svdw_G2_Z* = Fp2[BN254_Snarks].fromHex( 
  "0x0",
  "0x1"
)
const BN254_Snarks_h2c_svdw_G2_curve_eq_rhs_Z* = Fp2[BN254_Snarks].fromHex( 
  "0x2b149d40ceb8aaae81be18991be06ac3b5b4c5e559dbefa33267e6dc24a138e5",
  "0x9713b03af0fed4cd2cafadeed8fdf4a74fa084e52d1852e4a2bd0685c315d1"
)
const BN254_Snarks_h2c_svdw_G2_minus_Z_div_2* = Fp2[BN254_Snarks].fromHex( 
  "0x0",
  "0x183227397098d014dc2822db40c0ac2ecbc0b548b438e5469e10460b6c3e7ea3"
)
const BN254_Snarks_h2c_svdw_G2_z3* = Fp2[BN254_Snarks].fromHex( 
  "0x1248cccf0e2a72383dec3a1621130a65c0eb5d826ca664d3f4fce46f983efce6",
  "0x220de2a91cc408cf05ff76bf76fb88febaac1173cab9c8ebc03c7f9dc5569f10"
)
const BN254_Snarks_h2c_svdw_G2_z4* = Fp2[BN254_Snarks].fromHex( 
  "0x294f62301de5ae301a38098f4f5570e5bfc5e456aa54a6aa847fafc89357f76f",
  "0xc96f95a3ebfe711190ea3d3e76a7f0df14d60686e6cb1930d8fc08b259726c"
)
