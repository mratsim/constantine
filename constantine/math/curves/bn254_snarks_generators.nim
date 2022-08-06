# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/curves,
  ../elliptic/ec_shortweierstrass_affine,
  ../io/[io_fields, io_extfields]

{.used.}

# Generators
# -----------------------------------------------------------------
# https://github.com/ethereum/EIPs/blob/master/EIPS/eip-197.md

# The group G_1 is defined on the curve Y^2 = X^3 + 3 over the field F_p 
# with p = 21888242871839275222246405745257275088696311157297823662689037894645226208583
# with generator P1 = (1, 2).
const BN254_Snarks_generator_G1* = ECP_ShortW_Aff[Fp[BN254_Snarks], G1](
  x: Fp[BN254_Snarks].fromHex"0x1",
  y: Fp[BN254_Snarks].fromHex"0x2"
)

# The group G_2 is defined on the curve Y^2 = X^3 + 3/(i+9)
# over a different field F_p^2 = F_p[i] / (i^2 + 1) (p is the same as above) 
# with generator
# P2 = (
#   11559732032986387107991004021392285783925812861821192530917403151452391805634 * i +
#   10857046999023057135944570762232829481370756359578518086990519993285655852781,
#   4082367875863433681332203403145435568316851327593401208105741076214120093531 * i +
#   8495653923123431417604973247489272438418190587263600148770280649306958101930
# )
const BN254_Snarks_generator_G2* = ECP_ShortW_Aff[Fp2[BN254_Snarks], G2](
  x: Fp2[BN254_Snarks].fromHex(
    "0x1800DEEF121F1E76426A00665E5C4479674322D4F75EDADD46DEBD5CD992F6ED",
    "0x198E9393920D483A7260BFB731FB5D25F1AA493335A9E71297E485B7AEF312C2"
  ),
  y: Fp2[BN254_Snarks].fromHex(
    "0x12C85EA5DB8C6DEB4AAB71808DCB408FE3D1E7690C43D37B4CE6CC0166FA7DAA",
    "0x90689D0585FF075EC9E99AD690C3395BC4B313370B38EF355ACDADCD122975B"
  )
)
