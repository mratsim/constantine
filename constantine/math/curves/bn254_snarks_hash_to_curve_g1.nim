# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/curves,
  ../io/io_fields

{.used.}

# Hash-to-Curve Shallue-van de Woestijne BN254_Snarks G1 map
# -----------------------------------------------------------------
# Spec:
# - https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-14#appendix-F.1

const BN254_Snarks_h2c_svdw_G1_Z* = Fp[BN254_Snarks].fromHex( 
  "0x1")
const BN254_Snarks_h2c_svdw_G1_curve_eq_rhs_Z* = Fp[BN254_Snarks].fromHex( 
  "0x4")
const BN254_Snarks_h2c_svdw_G1_minus_Z_div_2* = Fp[BN254_Snarks].fromHex( 
  "0x183227397098d014dc2822db40c0ac2ecbc0b548b438e5469e10460b6c3e7ea3")
const BN254_Snarks_h2c_svdw_G1_z3* = Fp[BN254_Snarks].fromHex( 
  "0x16789af3a83522eb353c98fc6b36d713d5d8d1cc5dffffffa")
const BN254_Snarks_h2c_svdw_G1_z4* = Fp[BN254_Snarks].fromHex( 
  "0x10216f7ba065e00de81ac1e7808072c9dd2b2385cd7b438469602eb24829a9bd")
