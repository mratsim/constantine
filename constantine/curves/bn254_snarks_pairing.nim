# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/[curves, type_bigint],
  ../io/io_bigints,
  ../towers,
  ../pairing/cyclotomic_fp12

# Slow generic implementation
# ------------------------------------------------------------

# The bit count must be exact for the Miller loop
const BN254_Snarks_pairing_ate_param* = block:
  # BN Miller loop is parametrized by 6u+2
  # +2 to bitlength so that we can mul by 3 for NAF encoding
  BigInt[65+2].fromHex"0x19d797039be763ba8"

const BN254_Snarks_pairing_ate_param_isNeg* = false

const BN254_Snarks_pairing_finalexponent* = block:
  # (p^12 - 1) / r
  BigInt[2790].fromHex"0x2f4b6dc97020fddadf107d20bc842d43bf6369b1ff6a1c71015f3f7be2e1e30a73bb94fec0daf15466b2383a5d3ec3d15ad524d8f70c54efee1bd8c3b21377e563a09a1b705887e72eceaddea3790364a61f676baaf977870e88d5c6c8fef0781361e443ae77f5b63a2a2264487f2940a8b1ddb3d15062cd0fb2015dfc6668449aed3cc48a82d0d602d268c7daab6a41294c0cc4ebe5664568dfc50e1648a45a4a1e3a5195846a3ed011a337a02088ec80e0ebae8755cfe107acf3aafb40494e406f804216bb10cf430b0f37856b42db8dc5514724ee93dfb10826f0dd4a0364b9580291d2cd65664814fde37ca80bb4ea44eacc5e641bbadf423f9a2cbf813b8d145da90029baee7ddadda71c7f3811c4105262945bba1668c3be69a3c230974d83561841d766f9c9d570bb7fbe04c7e8a6c3c760c0de81def35692da361102b6b9b2b918837fa97896e84abb40a4efb7e54523a486964b64ca86f120"

# Addition chain
# ------------------------------------------------------------
#
# u = 0x44e992b44a6909f1
# Ate BN |6u+2|
# hex: 0x19d797039be763ba8
# bin: 0x11001110101111001011100000011100110111110011101100011101110101000
#
# We don't define an addition chain for the Miller loop
# it would requires saving accumulators to actually save
# operations compared to NAF, and can we combine the saved EC[Fp2] accumulators?

func pow_u*(r: var Fp12[BN254_Snarks], a: Fp12[BN254_Snarks], invert = BN254_Snarks_pairing_ate_param_isNeg) =
  ## f^u with u the curve parameter
  ## For BN254_Snarks f^0x44e992b44a6909f1
  when false:
    cyclotomic_exp(
      r, a,
      BigInt[63].fromHex("0x44e992b44a6909f1"),
      invert
    )
  else:
    var # Hopefully the compiler optimizes away unused Fp12
        # because those are huge
      x10       {.noInit.}: Fp12[BN254_Snarks]
      x11       {.noInit.}: Fp12[BN254_Snarks]
      x100      {.noInit.}: Fp12[BN254_Snarks]
      x110      {.noInit.}: Fp12[BN254_Snarks]
      x1100     {.noInit.}: Fp12[BN254_Snarks]
      x1111     {.noInit.}: Fp12[BN254_Snarks]
      x10010    {.noInit.}: Fp12[BN254_Snarks]
      x10110    {.noInit.}: Fp12[BN254_Snarks]
      x11100    {.noInit.}: Fp12[BN254_Snarks]
      x101110   {.noInit.}: Fp12[BN254_Snarks]
      x1001010  {.noInit.}: Fp12[BN254_Snarks]
      x1111000  {.noInit.}: Fp12[BN254_Snarks]
      x10001110 {.noInit.}: Fp12[BN254_Snarks]

    x10       .cyclotomic_square(a)
    x11       .prod(x10, a)
    x100      .prod(x11, a)
    x110      .prod(x10, x100)
    x1100     .cyclotomic_square(x110)
    x1111     .prod(x11, x1100)
    x10010    .prod(x11, x1111)
    x10110    .prod(x100, x10010)
    x11100    .prod(x110, x10110)
    x101110   .prod(x10010, x11100)
    x1001010  .prod(x11100, x101110)
    x1111000  .prod(x101110, x1001010)
    x10001110 .prod(x10110, x1111000)

    var
      r15 {.noInit.}: Fp12[BN254_Snarks]
      r16 {.noInit.}: Fp12[BN254_Snarks]
      r17 {.noInit.}: Fp12[BN254_Snarks]
      r18 {.noInit.}: Fp12[BN254_Snarks]
      r20 {.noInit.}: Fp12[BN254_Snarks]
      r21 {.noInit.}: Fp12[BN254_Snarks]
      r22 {.noInit.}: Fp12[BN254_Snarks]
      r26 {.noInit.}: Fp12[BN254_Snarks]
      r27 {.noInit.}: Fp12[BN254_Snarks]
      r61 {.noInit.}: Fp12[BN254_Snarks]

    r15.cyclotomic_square(x10001110)
    r15 *= x1001010
    r16.prod(x10001110, r15)
    r17.prod(x1111, r16)
    r18.prod(r16, r17)

    r20.cyclotomic_square(r18)
    r20 *= r17
    r21.prod(x1111000, r20)
    r22.prod(r15, r21)

    r26.cyclotomic_square(r22)
    r26.cyclotomic_square()
    r26 *= r22
    r26 *= r18

    r27.prod(r22, r26)

    r61.prod(r26, r27)
    r61.cycl_sqr_repeated(17)
    r61 *= r27
    r61.cycl_sqr_repeated(14)
    r61 *= r21

    r = r61
    r.cycl_sqr_repeated(16)
    r *= r20

    if invert:
      r.cyclotomic_inv()
