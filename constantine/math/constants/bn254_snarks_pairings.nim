# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/abstractions,
  ../config/curves,
  ../io/io_bigints,
  ../extension_fields,
  ../pairings/cyclotomic_subgroups,
  ../isogenies/frobenius

# Slow generic implementation
# ------------------------------------------------------------

# The bit count must be exact for the Miller loop
const BN254_Snarks_pairing_ate_param* = block:
  # BN Miller loop is parametrized by 6u+2
  BigInt[65].fromHex"0x19d797039be763ba8"

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

func cycl_exp_by_curve_param*(
       r: var Fp12[BN254_Snarks], a: Fp12[BN254_Snarks],
       invert = BN254_Snarks_pairing_ate_param_isNeg) =
  ## f^u with u the curve parameter
  ## For BN254_Snarks f^0x44e992b44a6909f1
  # https://github.com/mmcloughlin/addchain
  # Addchain weighted by Fp12 mul and cyclotomic square cycle costs
  # addchain search -add 3622 -double 1696 "0x44e992b44a6909f1"
  var # Hopefully the compiler optimizes away unused Fp12
      # because those are huge
    x10       {.noInit.}: Fp12[BN254_Snarks]
    x100      {.noInit.}: Fp12[BN254_Snarks]
    x1000     {.noInit.}: Fp12[BN254_Snarks]
    x10000    {.noInit.}: Fp12[BN254_Snarks]
    x10001    {.noInit.}: Fp12[BN254_Snarks]
    x10011    {.noInit.}: Fp12[BN254_Snarks]
    x10100    {.noInit.}: Fp12[BN254_Snarks]
    x11001    {.noInit.}: Fp12[BN254_Snarks]
    x100010   {.noInit.}: Fp12[BN254_Snarks]
    x100111   {.noInit.}: Fp12[BN254_Snarks]
    x101001   {.noInit.}: Fp12[BN254_Snarks]

  x10       .cyclotomic_square(a)
  x100      .cyclotomic_square(x10)
  x1000     .cyclotomic_square(x100)
  x10000    .cyclotomic_square(x1000)
  x10001    .prod(x10000, a)
  x10011    .prod(x10001, x10)
  x10100    .prod(x10011, a)
  x11001    .prod(x1000, x10001)
  x100010   .cyclotomic_square(x10001)
  x100111   .prod(x10011, x10100)
  x101001   .prod(x10, x100111)

  r.cycl_sqr_repeated(x100010, 6)
  r *= x100
  r *= x11001
  r.cycl_sqr_repeated(7)
  r *= x11001

  r.cycl_sqr_repeated(8)
  r *= x101001
  r *= x10
  r.cycl_sqr_repeated(6)
  r *= x10001

  r.cycl_sqr_repeated(8)
  r *= x101001
  r.cycl_sqr_repeated(6)
  r *= x101001
  r.cycl_sqr_repeated(10)

  r *= x100111
  r.cycl_sqr_repeated(6)
  r *= x101001
  r *= x1000

  if invert:
    r.cyclotomic_inv()

func isInPairingSubgroup*(a: Fp12[BN254_Snarks]): SecretBool =
  ## Returns true if a is in GT subgroup, i.e. a is an element of order r
  ## Warning ⚠: Assumes that a is in the cyclotomic subgroup
  # Implementation: Scott, https://eprint.iacr.org/2021/1130.pdf
  #   A note on group membership tests for G1, G2 and GT
  #   on BLS pairing-friendly curves
  #   P is in the G1 subgroup iff a^p == a^(6u²)
  var t0{.noInit.}, t1{.noInit.}: Fp12[BN254_Snarks]
  t0.cycl_exp_by_curve_param(a)   # a^p
  t1.cycl_exp_by_curve_param(t0)  # a^(p²)
  t0.square(t1) # a^(2p²)
  t0 *= t1      # a^(3p²)
  t0.square()   # a^(6p²)

  t1.frobenius_map(a)

  return t0 == t1