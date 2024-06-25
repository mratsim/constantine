# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # stdlib
  std/unittest,
  # Internals
  constantine/platforms/abstractions,
  constantine/math/extension_fields,
  constantine/named/algebras,
  constantine/math/io/io_extfields,
  constantine/math/extension_fields

# ###############################################################
#
#   Edge cases highlighted by property-based testing or fuzzing
#
# ###############################################################

# Fuzzing failure #114: Fp12 BN254 Mul and add/sub are consistent
# Highlighted by the Long01Seq skewed RNG
# with random seeds
# - 1611183150
# - 1611267611
# - 1611393788
# - 1611420927
# - 1611402369

proc test114(factor: int, a: Fp12[BN254_Snarks]): bool =
  var sum{.noInit.}, one{.noInit.}, f{.noInit.}: Fp12[BN254_Snarks]
  one.setOne()

  if factor < 0:
    sum.neg(a)
    f.neg(one)
    for i in 1 ..< -factor:
      sum -= a
      f -= one
  else:
    sum = a
    f = one
    for i in 1 ..< factor:
      sum += a
      f += one

  var r{.noInit.}: Fp12[BN254_Snarks]

  r.prod(a, f)

  result = bool(r == sum)

  if not result:
    echo "Failure for"
    echo "==================="
    echo "r:   ", r.toHex()
    echo "-------------------"
    echo "sum: ", sum.toHex()
    echo "-------------------"
    debug:
      echo "r (raw montgomery):  ", $r
      echo "-------------------"
      echo "sum (raw montgomery):", $sum
      echo "-------------------"
    echo "\n\n"

# Requires a Fp -> Fp2 -> Fp4 -> Fp12 towering
var t114_cases: seq[tuple[factor: int, a: Fp12[BN254_Snarks]]]

t114_cases.add (
  # seed 1611183150
  -13,
  Fp12[BN254_Snarks].fromHex(
    "0x0000000000ffffffffffffffff3f00c00100000000fcffff0700000000000000",
    "0x0000000000ffffffffffff7f000000e0ffff03000000fcff07e0ffffff9fffff",
    "0x0080ffffffffff1f00f00080ffffffffffffffffffffffffffffffffffffffff",
    "0x0c0a77c19a07df2f666ea36f7899461c0a78ec28b5d70b3dd35d430dc58f0d9d",
    "0x000007fc00000000000000000000003ffffffffffff1ffffff8000000001ffff",
    "0x000000c0ffffffdfffffffff0100feffff03c0ffffffffffffffff3f00000000",
    "0x000000000000000000000080ffffffffff3f0000f0dfff0f80ffffffffff0700",
    "0x0000000000000000000000000000000000000000000000000000000000000000",
    "0x0e0a77c199c7df2f666ee36f7879422c0a78ed28f5c70b3dd2dd448dc58eed9d",
    "0x0e0a77a19a07df2f866ea36f7839462c0a78eb28f5d70b3dd3dd438dc58f0d9c",
    "0x000000000000000000000000003fc0000003f80000000000000007ffffffffff",
    "0x0000001fff0000000000000000038000003ffffffffffff800000000000ff000"
  )
)

var x = Fp12[BN254_Snarks].fromHex(
    "0x30644e72d431a029b85045b68b4e4e9d8a816a915b98ca99e1208c16d87cfd47",
    "0x30644e72d431a029b8504c4381814cf0978e43916864f199d5b38c16dd5cfd54",
    "0x29d74e72e131ab96ac203f298181585d97816a916871ca8d3c208c16d87cfd54",
    "0x250924f6b2602b3eada2ca30e63cd209d5e1ac3465db981134c5c8a859b04423",
    "0x3063e6a6e131a029b85045b68181551d97816a916927ca8d42a08c16d862fd54",
    "0x306444a5e131a1c9b85045c37474655da4509d916871ca8d3c2095e3d87cfd47",
    "0x30644e72e131a029b8503f298181585da14e6a852d11d6c3af208c16d889a247",
    "0x0000000000000000000000000000000000000000000000000000000000000000",
    "0x0b0924f6b5a02b3ead9f8a30e7dd0539d5e19f3126ab98113b45b52859b1e423",
    "0x0b092696b2602b3d0da2ca30eb1cd139d5e1b93125db98112e45c22859b04430",
    "0x30644e72e131a029b85045b67e44985d974dd2916871ca8d3c202416d87cfd54",
    "0x30644cd2ee31a029b85045b68153d85d94416a916871caf53c208c16d7adcd47"
  )

t114_cases.add (
  # seed 1611267611
  -7,
  Fp12[BN254_Snarks].fromHex(
    "0x0000000000000000000000000000000000000000000000000000000000000000",
    "0x0e0477c19a07de6e666ea46eb77947290a786a28f5c70b3dd35d4486c58f0cdc",
    "0x00fffffffffffffffffffffff80000000003ffffffffffffc0000000007fffff",
    "0x00ffff00000080ffffffffffffffffffffff1f00000000000000000000c03f00",
    "0x00000000c0ff00c0ff07000000000000000000000000000000feffffffffffff",
    "0x000000000007ffffffffff000000e003f83fffffe0000000001ffff803ffc000",
    "0x0000003fffffffffffffffffffffffffffff801fffffffc01f00000007ffffff",
    "0x00000000003fffffffe00000000000ffffffe08003fff800007fffffffffffff",
    "0x0e0a57c19a47dfaf666ea36f787945ac8a78eb28f5c70b3dd2dd438dc58f0d9d",
    "0x0000000000feffffffffff1f0000000000000000000080ffff03f8ffffffffff",
    "0x000000f87f0000c0ffffffffffffffffffffffffffffffffffffff07fcffffff",
    "0x01fffffffe0000000001fcffffffffffffffffc003ffffff8001ffffffffffff"
  )
)

t114_cases.add (
  # seed 1611393788
  -15,
  Fp12[BN254_Snarks].fromHex(
    "0x0e0a77c192085f2f666e63777879462c0a78eb08f5c70b3dd35d438dd58f0d9c",
    "0x0fffe03ffe0000000000000000001fffffff0000000fffffe0000fffffffffff",
    "0x000000000003ffffffffffff00000000000000000000000000000ffffffeffff",
    "0x00f0ffffffff3f0000f0ffffffffff0700000000000000000000600000001f00",
    "0x0f9bb18c1ece5fd647afba4d7e7ea7a0687ebd6a978e3572c3df73e9278306b8",
    "0x00e0ff3f00f0ffffffffff010000000080ffffffffffffffffffff000000ffff",
    "0x0000000000000000000000000000000000000000000000000000000000000000",
    "0x0dca77c19a07e02f6666a56f7878462c0a792b28f5c6cb3dd35d438dcd8f0d80",
    "0x0e0a76c19a07df2f6e6ea36f7879462c0a78eb28f5c70b3dd359438dc59f0d7d",
    "0x0e0a77c11a07df2f666ea36f8075462c0a78eb28f5c70b3dd35d538dc58f0dac",
    "0x0e0a77819a083f2f766e9b6f7879462c0a78eb28f5c70b3dd35d438dc592119c",
    "0x000000000ffffffffffffe000000003ffffc0000000000000000000000000000"
  )
)

t114_cases.add (
  # seed 1611420927
  -25,
  Fp12[BN254_Snarks].fromHex(
    "0x0000000000ffffc00000000000000fffffffffffffffffffff00007fffe003ff",
    "0x00000000ffff1fc0ffffff1ff8ffffffffffff00fc010000feffffffff0300f0",
    "0x000000000000001800000000e00300feffffffffffff1f00f0ffffffffffffff",
    "0x0e0a75c1da07df2f666ea36f7879461c0a78ec28f5c70b35d35d438dc590ed9d",
    "0x0e09f6c19a085f30666f846f7780c72c097feb29f5c70b3cd65dc48d44900cbc",
    "0x0000000001ffffe7e0000000000000003fffffffffffff000000000001fff800",
    "0x0000000000000000000000000000000000000000000000000000000000000000",
    "0x0e09b6c28b07df2f666ea36f7879462c0a780ae9f5c70b3dd35c638cc48f0da3",
    "0x0e0a77c19a07df2f666da46f7879462c0a78eb2976c60a7cd35d438eb68f0c9d",
    "0x0007f00007fffff00000000000000003ffffffff8000000fffffc001ffffffff",
    "0x0e0a77c19a07df2f666ea36f7879462c0a68ec28f5c70b3dd35c438dcd4f0e1c",
    "0x1ffffffffffffffffffffffffffffff000000000000000000fc000ffffffffff"
  )
)

t114_cases.add (
  # seed 1611402369
  -10,
  Fp12[BN254_Snarks].fromHex(
    "0x0000000000000000000000000000000000000000000000000000000000000000",
    "0x00000000000020000007fffff800000000000001ffffffffffffffffffffe000",
    "0x0000000000000000000000f8fffffffffffffff7ffffffffffff1f0000000200",
    "0x0000030000000003fffc00000000003ffffffe000000000000ffc00000000000",
    "0x0e0a76e09a07df2f666ea3705881432c0a78e828f5c70b3d125e348d058f0cbc",
    "0x0000000f01fffc7fffffffffffffffffffffffe000000000000fffffc0000000",
    "0x0e0a77c0b907e02c666ea36f77f8462c0a78eb28f5c70b3e545d438dc58f0d9c",
    "0x0e0a77a19a07df2f668ea36f78793a2c0a78eb2875c74b3dd355438dc59f0d9c",
    "0x0e0a75c19a07df31662ea36f7879462c0a78eb28f5c70c1dd361438dc58f0d9c",
    "0x00000000000000000000000000feffff00001c000007e0ffffffffff07000000",
    "0x00001ffffffff000007fffffffff0000007f000000000000ffffffffffffffff",
    "0x0e0996c19a08d02e756ea36f7879462c0a78eb28f5c70b3dd43dc28dc58f0d9d"
  )
)

suite "Fuzzing failure #114: Fp12 BN254 Mul and add/sub are consistent":
  test $t114_cases.len & " failure cases are now successful":
    for i in 0..<t114_cases.len:
      check: test114(t114_cases[i].factor, t114_cases[i].a)
