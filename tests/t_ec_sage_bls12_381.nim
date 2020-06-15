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
  ../constantine/elliptic/[ec_weierstrass_projective, ec_scalar_mul, ec_endomorphism_accel],
  # Test utilities
  ./support/ec_reference_scalar_mult

echo "\n------------------------------------------------------\n"

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

    let exponent = BigInt[EC.F.C.getCurveOrderBitwidth()].fromHex(scalar)
    var exponentCanonical: array[(exponent.bits+7) div 8, byte]
    exponentCanonical.exportRawUint(exponent, bigEndian)

    var
      impl = P
      reference = P
      endo = P
      scratchSpace: array[1 shl 4, EC]

    impl.scalarMulGeneric(exponentCanonical, scratchSpace)
    reference.unsafe_ECmul_double_add(exponentCanonical)
    endo.scalarMulGLV(exponent)

    doAssert: bool(Q == reference)
    doAssert: bool(Q == impl)
    doAssert: bool(Q == endo)

suite "Scalar Multiplication (cofactor cleared): BLS12_381 implementation vs SageMath" & " [" & $WordBitwidth & "-bit mode]":
  # Generated via sage sage/testgen_bls12_381.sage
  test(
    id = 1,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "f9679bb02ee7f352fff6a6467a5e563ec8dd38c86a48abd9e8f7f241f1cdd29d54bc3ddea3a33b62e0d7ce22f3d244a",
    Py = "50189b992cf856846b30e52205ff9ef72dc081e9680726586231cbc29a81a162120082585f401e00382d5c86fb1083f",
    scalar = "f7e60a832eb77ac47374bc93251360d6c81c21add62767ff816caf11a20d8db",
    Qx = "c344f3bcc86df380186311fa502b7943a436a629380f8ee1960515522eedc58fe67ddd47615487668bcf12842c524d8",
    Qy = "189e0c154f2631ad26e24ca73d84fb60a21d385fe205df04cf9f2f6fc0c3aa72afe9fbea71a930fa71d9bbfddb2fa571"
  )

  test(
    id = 2,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "17d71835ff84f150fabf5c77ac90bf7f6249143abd1f5d8a46a76f243d424d82e1e258fc7983ba8af97a2462adebe090",
    Py = "d3e108ee1332067cbe4f4193eae10381acb69f493b40e53d9dee59506b49c6564c9056494a7f987982eb4069512c1c6",
    scalar = "5f10367bdae7aa872d90b5ac209321ce5a15181ce22848d032a8d452055cbfd0",
    Qx = "21073bee733a07b15d83afcd4e6ee11b01e6137fd5ad4589c5045e12d79a9a9490a3ebc59f30633a60fc3635a3c1e51",
    Qy = "eb7a97a9d3dfff1667b8fa559bdcdf37c7767e6afb8ca93ad9dd44feb93761e10aa2c4c1a79728a21cd4a6f705398b5"
  )

  test(
    id = 3,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "f92c9572692e8f3d450483a7a9bb4694e3b54c9cd09441a4dd7f579b0a6984e47f8090c31c172b33d87f3de186d6b58",
    Py = "286ede4cb2ae19ead4932d5550c5d3ec8ce3a3ada5e1ed6d202e93dd1b16d3513f0f9b62adc6323f18e272a426ee955",
    scalar = "4c321d72220c098fc0fd52306de98f8be9446bf854cf1e4d8dbae62375d18faf",
    Qx = "4bb385e937582ae32aa7ba89632fcef2eace3f7b57309d979cf35298a430de9ef4d9ac5ba2335c1a4b6e7e5c38d0036",
    Qy = "1801154d3a7b0daea772345b7f72a4c88c9677743f267da63490dad4dece2ecc9ec02d4d4d063086ee5d356aa2db914e"
  )

  test(
    id = 4,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "ec23ff3435b8ebd5e8e0a879d432e11eb974161664b1341fd28f1ffc4c228bf6ada2ae4a565f18c9b66f67a7573502d",
    Py = "10c4b647be08db0b49b75320ae891f9f9c5d7bb7c798947e800d681d205d1b24b12e4dfa993d1bd16851b00356627cc1",
    scalar = "1738857afb76c55f615c2a20b44ca90dcb3267d804ec23fddea431dbee4eb37f",
    Qx = "dc7ae7801152918ee3c13590407b4242a80d0b855a0bf585d3dc30719601d2d5d9e01e99ae735003ecb7c20ef48265",
    Qy = "142c01a6aa390426a4ce2f36df43f86442732c35d4e05e5b67f3623832944f0ea5a29138624cb939330652a3cfb282b5"
  )

  test(
    id = 5,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "df127083c2a5ef2388b02af913c0e4002a52a82db9e5ecbf23ee4f557d3b61c91ebcfe9d4973070b46bc5ea6897bca1",
    Py = "318960aeea262ec23ffdd42ec1ba72ae6fa2186a1e2a0fc2659073fb7b5adfb50d581a4d998a94d1accf78b1b3a0163",
    scalar = "19c47811813444020c999a2b263940b5054cf45bb8ad8e086ff126bfcd5507e1",
    Qx = "5f93c42fd76a29063efa2ee92607e0b3ae7edc4e419b3914661e5162d6beaeb96a34d2007ff817bc102651f61dca8d1",
    Qy = "18dde8666bb1d0a379719d7d1b1512de809b70e49d9553303274ea872e56f7f39da551d6bcb7c57ae88ec7dc1fb354a4"
  )

  test(
    id = 6,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "101123de23c0f240c583c2368c4118dc942db219c55f58cf54acd500c1fcfa06f651ad75319ebf840cbdb6bddea7fde4",
    Py = "5268587d4b844b0708e0336d1bbf48da185aaf5b948eccc3b565d00a856dd55882b9bb31c52af0e275b168cb35eb7b0",
    scalar = "43ffcda71e45a3e90b7502d92b30a0b06c54c95a91aa21e0438677b1c2714ecb",
    Qx = "f9871b682c1c76c7f4f0a7ca57ad876c10dc108b65b76987264873278d9f54db95101c173aed06d07062efc7d47ca0c",
    Qy = "20d9628d611e72a4251a1f2357d4f53e68e4915383b6a0d126273d216b1a8c5e2cb7b2688ad702ef1682f4c5228fcd9"
  )

  test(
    id = 7,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "1457ba1bae6eb3afae3261941c65c93e3ae7d784907d15b8d559100da5e13fd29e4a4d6e3103b781a95237b7b2d80a8e",
    Py = "6a869a47cb48d01e7d29660932afd7617720262b55de5f430b8aa3d74f9fd2b9d3a07ce192425da58014764fc9532cd",
    scalar = "64ad0d6c36dba5368e71f0010aebf860288f54611e5aaf18082bae7a404ebfd8",
    Qx = "93e540e26190e161038d985d40f2ab897cbc2346be7d8f2b201a689b59d4020a8740e252606f2f79ba0e121ccc9976d",
    Qy = "10568d68f1b993aa1eded3869eda14e509f1cb4d8553bdf97feee175467cea4c0c1316fdb4e5a68440ad04b96b2d3bfc"
  )

  test(
    id = 8,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "2615f843e8fe68d4c337bcf83b2cf13cbae638edd0740f1eac520dc2146afa3b8d36c540878c1d207ef913634b1e593",
    Py = "1787d6eeeceb6e7793073f0bbe7bae522529c126b650c43d5d41e732c581a57df1bfb818061b7b4e6c9145da5df2c43e",
    scalar = "b0ac3d0e685583075aa46c03a00859dfbec24ccb36e2cae3806d82275adcc03",
    Qx = "d95ed29c2e15fd2205d83a71478341d6022deb93af4d49f704437678a72ce141d2f6043aa0e34e26f60d17e16b97053",
    Qy = "b37cbded112c84116b74ff311b10d148f3e203cb88d4a011b096c74cd2bfdb27255727de4aa8299ae10b32d661d48a7"
  )

  test(
    id = 9,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "10bc0c4e1ed87246a9d4d7d38546369f275a245f6e1d3b882e8c9a7f05bc6ee8ff97a96a54084c2bef15ed8bfefb1465",
    Py = "1782377e5f588576b5ab42fea224e88873dda957202f0c6d72ce8728c2d58dc654be77226fbda385d5f269354e4a176a",
    scalar = "23941bb3c3659423d6fdafb7cff52e0e02de0ac91e64c537c6203d64905b63d0",
    Qx = "83f1e7e8bd963c1ccd837dae7bc9336531aaf0aee717537a9a7e2712e220f74cdb73a99f331c0eb6b377be3dafc211f",
    Qy = "cd87773d072b1305dfc85c2983aecae2ab316e5e8f31306c32d58d6ce2e431b12685d18c58b6a35ad2113c5b689eeb"
  )

  test(
    id = 10,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "be4f9f721d98a761a5562bd80ea06f369e9cbb7d33bbb2f0191d4b77d0fd2a10c4083b54157b525f36c522ca3a6ca09",
    Py = "166c315ecdd20acb3c5efcc7e038b17d0b37a06ffbf77873f15fc0cd091a1e4102a8b8bf5507919453759e744391b04d",
    scalar = "4203156dcf70582ea8cbd0388104f47fd5a18ae336b2fed8458e1e4e74d7baf5",
    Qx = "c72bc7087cd22993b7f6d2e49026abfde678a384073ed373b95df722b1ab658eb5ae42211e5528af606e38b59511bc6",
    Qy = "96d80593b42fe44e64793e490b1257af0aa26b36773aac93c3686fdb14975917cf60a1a19e32623218d0722dbb88a85"
  )
