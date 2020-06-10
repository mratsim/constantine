# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[unittest, times],
  # Internals
  ../constantine/config/[common, curves],
  ../constantine/arithmetic,
  ../constantine/io/[io_bigints, io_ec],
  ../constantine/elliptic/[ec_weierstrass_projective, ec_scalar_mul],
  # Test utilities
  ./support/ec_reference_scalar_mult

proc test(
       id: int,
       EC: typedesc[ECP_SWei_Proj],
       Px, Py: string,
       scalar: string,
       Qx, Qy: string
     ) =

  test "test " & $id:
    var P: EC
    let pOK = P.fromHex(Px, Py)
    doAssert pOK

    var Q: EC
    let qOK = Q.fromHex(Qx, Qy)

    let exponent = EC.F.C.matchingBigInt.fromHex(scalar)
    var exponentCanonical: array[(exponent.bits+7) div 8, byte]
    exponentCanonical.exportRawUint(exponent, bigEndian)

    var
      impl = P
      reference = P
      scratchSpace: array[1 shl 4, EC]

    impl.scalarMulGeneric(exponentCanonical, scratchSpace)
    reference.unsafe_ECmul_double_add(exponentCanonical)

    doAssert: bool(Q == reference)
    doAssert: bool(Q == impl)

suite "Scalar Multiplication: BLS12_381 implementation (and unsafe reference impl) vs SageMath":
  # Generated via sage sage/testgen_bls12_381.sage
  test(
    id = 1,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "f21eda282230f72b855d48055e68ab3825da87831fa5147a64fa071bade4c26bddd45e8b602e62df4d907414a6ec1b4",
    Py = "531b38866cb35c19951f4a1ac62242f11fa714a1b99c6116a630fa75e7f4407fcd1ae9770a821c5899a777d341c915a",
    scalar = "f7e60a832eb77ac47374bc93251360d6c81c21add62767ff816caf11a20d8db",
    Qx = "18d7ca3fb93d7300a0484233f3bac9bca00b45595a4b9caf66aa0b2237f6fd51559a24a634f3876451332c5f754438b2",
    Qy = "edbb203999303fc99ef04368412da4b3555f999c703b425dedff3fdc799317c292751c46275b27990c53d933de2db63"
  )

  test(
    id = 2,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "9ca8e33d8a330b04b052af6cf44bf2ed08cc93d83a4eb48cbb0cabfe02ffb2ef910df44862b271354352f15b70e45b5",
    Py = "102f6d07ef45f51de9a4ecef5ec34eae16833f4761c2ddfbe2b414173c3580721135e5bbb74269ab85ba83cb03020d9b",
    scalar = "5f10367bdae7aa872d90b5ac209321ce5a15181ce22848d032a8d452055cbfd0",
    Qx = "a50d49e3d8757f994aae312dedd55205687c432bc9d97efbe69e87bef4256b87af1b665a669d06657cda6ff01ee42df",
    Qy = "160d50aaa21f9d5b4faada77e4f91d8d4f152a0fcca4d30d271d74b20c1bba8638128f99f52d9603d4a24f8e27219bcd"
  )

  test(
    id = 3,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "173c28687d23de83c950131e548485e8e09d4053d32b814d13b618ee4159e8b61bf6320148ddabcedf2b04d3c9787cd4",
    Py = "277f935b4e0a90155915960c617f395dcadead1c7297cf92916add07308fc3f0493aa6dabf31d1f15953f56ac37d3d9",
    scalar = "4c321d72220c098fc0fd52306de98f8be9446bf854cf1e4d8dbae62375d18faf",
    Qx = "16259e878b5921bbe1e5672cccea0f29fedbb93b8ce1bae4d4b602b6dd5708c6d4e5d82ff92868828c46fd333aadf82d",
    Qy = "16d09713f4fe5705f2e3491aa9a1d5827fb3b280f5a1fdde0b01a2b75f5803d528d5f5603cc0e9da29d6a07b8e14df7c"
  )

  test(
    id = 4,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "177d32dfa6e97daf5ea8aee520bc5c33b7bee37cba114fda52dd948030ad81abdffbdda402c930791e1048ad531b2c80",
    Py = "14e9f915698dadd2220586a8bcc921b1f855273c3c0e41a88569e5a9fd2a4e886eeff9a7a11b02ec286987c5a52d55ce",
    scalar = "1738857afb76c55f615c2a20b44ca90dcb3267d804ec23fddea431dbee4eb37f",
    Qx = "a4bfcfc65eb16562752f5c164349ef673477e19fe020de84eddbc2958f6d40bbbba39fc67ee8c8fdf007922fec97f79",
    Qy = "106ccd382d15773e6097f8ea6f012cbec15184d6f4ea08bac2842ed419f0e555f1a43f7434b2e017f9e02971d07eb59d"
  )

  test(
    id = 5,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "1bc38e70e62770489063d3b7a3bebbc6735ab8dc389576ff03272c2883045aa051d74f8407920530b4c719b140cda81",
    Py = "bd24e4fb09ed4098d61e3d2cb456f03d7818ded79dfba9cfe7956829797b12e10f1766c46c1a2e1cf2957295124c782",
    scalar = "19c47811813444020c999a2b263940b5054cf45bb8ad8e086ff126bfcd5507e1",
    Qx = "b310d4688f2c9f8cd4c030b62ed27341f4c71341fe9c56858a949a2d51670eb6ebe1339163bdb833e692b0ee0cf4e92",
    Qy = "c92300561e1acb1e1ae6a1b75f83b9d2d2cb5f07c3f8ea945990ceb75e7ea12c4aec115227c13a05be92f5caed9268e"
  )

  test(
    id = 6,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "48cddafaca93d33caf910a7a6f74dc3489d53da9fa2f940b70b6dcf538cc08da1a369809ab86a8ee49cead0ed6bfef6",
    Py = "173f8dfb384aea011bed89aaca625085dc2940d0775e5f2647fc7574ce822643d0d7b1b39e9a51b9f5a0dca7486bddd0",
    scalar = "43ffcda71e45a3e90b7502d92b30a0b06c54c95a91aa21e0438677b1c2714ecb",
    Qx = "ef1e4967a3eb19318a66d092eada9810bebf301c168cea7c73fad9d98f7d4c2bde1071fd142c3da90830509f22a82b5",
    Qy = "da537922dcb6bf79e4d09237c1a3c5804e3a83b6f18ccb26991d50d77c81bef76139fa73d39c684c7c1616151b1058b"
  )

  test(
    id = 7,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "9d56cb273bdeef945078066192b74d2f3077f00f5bd1a50b338c44f7c640005a614f9c6fc89cb4678140b2a721c69a8",
    Py = "107b42b9a0c22b9e9cd2191b90fede2ab280532ea26806338a5b28533cf9431bde1a8010677a5078c63482953d4f2451",
    scalar = "64ad0d6c36dba5368e71f0010aebf860288f54611e5aaf18082bae7a404ebfd8",
    Qx = "e0c78d1e1ed993fdeb14e4872965bc90014aa39c728c457a720bf3123ebcdcb17ac553a619b9b7073ada436565d4bb4",
    Qy = "c2d9ba441ed90bae4f1597da90e434f1668fda320e4fa04cddcdce0eacb3bc54185d5f7cde826f5bd0e3d59b2424906"
  )

  test(
    id = 8,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "150a83a868fa6a74dbc5658445ea99ec47009572f303ce1d3c76370804c5a8c26d40c8b4b35a6585612d704c5fb090cb",
    Py = "31e73ed0aedebcf0b58d60c16f2e5ddd2d4eb2a6e34177939efcca0767cde241966b5950c3333c62ccddee51de26fe6",
    scalar = "b0ac3d0e685583075aa46c03a00859dfbec24ccb36e2cae3806d82275adcc03",
    Qx = "9c5e69fbd492a64e5811af7cc69e42bc14d8626f6d384d3f479d8e06c20ec5f460a1e3839f33899b4a9e0ada876ac6e",
    Qy = "16990d7d308897c74b87368f847df3ac0bb6609091c8d39b22d5778a4229f0bb92fea385d27db41e237dcfb0d05bd0e7"
  )

  test(
    id = 9,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "69498486a06c18f836a8e9ed507bbb563d6d03545e03e08f628e8fbd2e5d098e58950071d516ffd044d92b3a8b07184",
    Py = "18a169f06fc94f40cd131bdcd23e48e95b1276c0c8daacf56c3a5e278e89ee1094c94aa516113aa4a2455da149f0f989",
    scalar = "23941bb3c3659423d6fdafb7cff52e0e02de0ac91e64c537c6203d64905b63d0",
    Qx = "482e085550f5e514dd98f2d9b119c284ac165514d228c8f7a179f2b442968984873223af2255a499dc931c63543c0ba",
    Qy = "151ce80ca51dd09243d2b1a7937096d6b7494e89190da5ab7604cd913dc4105c871e48c815fefadee2906b8b401e7e71"
  )

  test(
    id = 10,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "98cc20aa561769b7ee569304503a94752e236bba52938fed7f3093d5867f65361dc8b48c83bd7db490c26736196e20e",
    Py = "10a68394358903122bd649bd30b473f4d3b4f0830bfe7da1c48ae87d9429d8fd26f5b4be8d8fd8e4214017044696da29",
    scalar = "4203156dcf70582ea8cbd0388104f47fd5a18ae336b2fed8458e1e4e74d7baf5",
    Qx = "18ff1dfd96799b7d0bffaa7480121c3a719047815ae41419f1bd1fdd593288bed8827b3d9e45a3a1e01bf7d603b5ba0",
    Qy = "49b95ca2c0f75dfb15fc07e5692d23f8eb38cb1cc9c48cd0e93a80adbff135a3945cc7a5d53d2b7510d6ee7cf97308d"
  )
