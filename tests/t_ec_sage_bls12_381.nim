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
  ../constantine/towers,
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


proc test(
       id: int,
       EC: typedesc[ECP_SWei_Proj],
       Px0, Px1, Py0, Py1: string,
       scalar: string,
       Qx0, Qx1, Qy0, Qy1: string
     ) =

  test "test " & $id:
    var P: EC
    let pOK = P.fromHex(Px0, Px1, Py0, Py1)
    doAssert pOK

    var Q: EC
    let qOK = Q.fromHex(Qx0, Qx1, Qy0, Qy1)

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
    # endo.scalarMulGLV(exponent) # TODO GLV+GLS on G2

    doAssert: bool(Q == reference)
    doAssert: bool(Q == impl)
    # doAssert: bool(Q == endo)

suite "Scalar Multiplication G2: BLS12-381 implementation vs SageMath" & " [" & $WordBitwidth & "-bit mode]":
  # Generated via sage sage/testgen_bls12_381.sage
  test(
    id = 1,
    EC = ECP_SWei_Proj[Fp2[BLS12_381]],
    Px0 = "989f16bcb9da60ef72383e6134ba194f57e30109806304336c0c995e2857ed20bf5b6e03d6fe1424332e9c666cbd10a",
    Px1 = "16692643cb5e7466e3730d3ea775c7741ac34d670b3be685761a7d6ab722a2673ce374ddab87b7c4d2675ba2199f9121",
    Py0 = "931e416488bef7cb4a053e4bd86ef44818bc03a5be5b04606b2a4dc1d139a3a452f5f7172f24eeaad84702b73b155bb",
    Py1 = "192c3e2a6619473216b7bb2447448cdbeb9f7e3c9486b0a05aadf6dcd91d7cb275a5d84c1a362628efffbc8711a62a67",
    scalar = "1f7bef2a74f3bf8ac0225a9edfa514bb5666b15e7be3e929059f2ef75f0035a6",
    Qx0 = "110c9c96525cccb2c9045ab5bc1d2c5629b06e225cd63802d2f81c7ee7920483a74653e44289dfe5e69b979b049badad",
    Qx1 = "189cb0e86e6b8886911107969afc8e807f9abbe20ab7063bddefa2fbfc85bc4e851598daeada33b8e1be6dd430fb9c0c",
    Qy0 = "91d2176e98a4122466ac0d6c19c6de17b5b27f30dd760b8f644b17291f050ccfe8c1d47462052e95fd9a7aca90a78e1",
    Qy1 = "25c5b7fe0fbf854f5e3af9146dfc706113de79eee220ede03491fcbadb47a89ee7179b6db8b06619e0369ec2a2e80fd"
  )

  test(
    id = 2,
    EC = ECP_SWei_Proj[Fp2[BLS12_381]],
    Px0 = "1677db8e7f654fa225ad1fae79177a9ebf72dd2c1c731a4abd0ab80b2225bf0bb99cc998bc43dd3b1f75f8ff977111ba",
    Px1 = "b1b3cd03ed2e49475c371fbe24e64bd97a89b28a4e7103c0203951e12763497d1c1d142de1a018fe5bd7edb57b9a88f",
    Py0 = "a8ec2afc4424099cef745c6636a9db54ed11f83e98a3e7537349bea1146733d0d2d223e09492912e9b866c88c76a6b7",
    Py1 = "33f45142e67aaa076379eb6c09b35509279f8b68d545729c22a51593db1d08ae1874a9b29b85a968af279c752f5b73a",
    scalar = "b500f1fa8ffa8d1c0aa7d65054a9aaa0d9ed2fff83b40516def10b03cc80026",
    Qx0 = "75d6b24552b5d3ae5937d17717c492160a32b01245e1351caca5e8ab9f973b356bdc1776c06c86d50924574cbcbcd04",
    Qx1 = "c35b4d49b562727eda2212c6740a5a0c39343c213338c97cc9a9b3cf75624e45fb02830863f32cea6d37ddcea3dcabb",
    Qy0 = "9c4107fce5315f306a70658e74f470b86ac863314efd118dca3c0c4ddd7391a5eef6999d024d927b1b1c690205a171d",
    Qy1 = "124fc330b4e7d361c4c90d9e39933b3c635e6a5d7a98e73ace3a2c55cc6360e5e80b5828b3fb17aaba4bd18da5316a7a"
  )

  test(
    id = 3,
    EC = ECP_SWei_Proj[Fp2[BLS12_381]],
    Px0 = "55d8f0f0af28084eb7050b403b1d10513931ca3245c047f21c51f9648b7573237f75c8617750cf8d3aea96b858893ad",
    Px1 = "125272cdaeac32cb5f255c3ef073630ae80c43c3413e8a22ede153368b44b1e8cb98100304ebc621c49096b26f6f9c11",
    Py0 = "67dce3c5bf2a9ff812436f25920d207f7b32b6392ea5b2288f759c813486ff0b97f95bbdb2a6efb487bc369ee1f4a4",
    Py1 = "118ded28f46124289428802b5d97f7445d7efdd74db9b3a89597718c34b6433916110c86aa025a45d7e34e056ecad1dc",
    scalar = "3638a1f09b542c9c14706bddf9bd411747489f3d398a5c286d28f3a950e33406",
    Qx0 = "8c045276467c6ecbc26816d7639f196cdd129d7a7e8cee8d3c787aabc95959360b2e2f9f8f63e2db8b76ed228fb6e83",
    Qx1 = "181b41e88accd20a6a05deef15997b14c1cdd17ad0ac75ce0f95e48b773095853aee0808f8fb4dd5c29757656c521232",
    Qy0 = "178b8034e50e6bffbbac00717d7ef96f027e1c0e07b850174e20034c3a89f0e1f41108449f2c3e7be0d637936f84202a",
    Qy1 = "19dae3659e65fcae08b2fd620178b4d78e9099a78f5fc9db941a9456de9eed2e4a208570adc296b43e4297b238aadbf9"
  )

  test(
    id = 4,
    EC = ECP_SWei_Proj[Fp2[BLS12_381]],
    Px0 = "13b3476e05a61f9c273046d68dc0aff412695115189caa49964c3d794fb99dd153ec357bb553150ce7a3d6a5d3fa89fb",
    Px1 = "3453cfc3fff2d649db5141e76b0248acd9e1593138b44e5e4da516a3c0ee5f1cef8bbc2611fa8969eaa5bb3534544ed",
    Py0 = "1054487252835dfc8ce3e8845ab420e6b746353f70e2447e32d92b6816f94ad2e245d3484cf2fb984e6e3f7c8c786d07",
    Py1 = "14c4f0b21d5381d7c50f8b02f5bad3af23b76729fe12b42b33bdfae87cb0fa452a447096a29c9ca8f951d24f02d9fdd7",
    scalar = "6448f296d9b1a8d81319a0b789df04c587c6165776ccf39f50a354204aabe0da",
    Qx0 = "15201587a5a6644f04c8818e70da24f8ed94403bc8f69e4a26923646c86faaea7e5538079ad870e4928484f682101e49",
    Qx1 = "17eec094b4ffa3b28e2a07069107b1ca3efb458d09fa719baf7229d1ed30cd137ca7c1897f84b4ba26aac99b7a5628fe",
    Qy0 = "19d32d85db24064e48ee7d1348df69e4f409f8f43e34f9d2f37077929975199049bcc5a1cf86358f539f034d14c882f2",
    Qy1 = "122226ac41a6f2de2347a59657d707092c6becb7fc4991695631cfa9f2caaed9cee9701562fb99c2a85bd56122305bd3"
  )

  test(
    id = 5,
    EC = ECP_SWei_Proj[Fp2[BLS12_381]],
    Px0 = "a16c8f0c124b0a76e53900b8e1b0cb0aa7b4280656ecebbd4cfdd8a09a40a06be8844081b3d359791391d7985a73078",
    Px1 = "a639f83aa058b7a2f8e8c6272c1d03d72d37061b9586e965dd3cf2839baf2575caa276871aa8263cb56a27fc02c209d",
    Py0 = "1c722e4e7e4784327296624871326f84de14e034f6a523eaaaa6e4352e22b9956ce2fede2d771a4d29b13d24742850b",
    Py1 = "109fe8ea84c839a4877120495cef7c054f37192fd87b4ff44ec9581230904ec7e4b90dbd767040c74137ab9963d005b6",
    scalar = "150caebc321c53c0658c5cecb45e564620b57bfbad0f5d5a277be71a184937b7",
    Qx0 = "121d86aa00cec80f3e00437247902d97ef5d4867d3ae725170c1f29a9f2837c07f0fe778a9ff30f8911b84b3203cb8c2",
    Qx1 = "f08808972239bde0fd4b8d498a92d08fa1d5f5b87d8a3f5f5b2c9a467745784e01defc5b55325f5707c532639b81d4c",
    Qy0 = "19b484b4a366edfb6e7c3fde7e607928ed0b8a138568bbcdfd55bce47baf070759229df7a7a2b386693f23a4664cb478",
    Qy1 = "92527a036c8ce2f4a592681a2f35db20917b5709c42da7c6e987c8f592837a3dfbc596667d033c8a313ac1ac28be8e1"
  )

  test(
    id = 6,
    EC = ECP_SWei_Proj[Fp2[BLS12_381]],
    Px0 = "9315bb59e19f21e198f30d32a876b0f922ac4c444977f4ca0a6f8f07f7a6c6353d197ff0213cb835d2685675e931250",
    Px1 = "4c3ce432c9e6f542d0a54593eeccfe923f679e448fd81b98aa28f542b5cef88ea4c822ddc8f78fb64a2e9695ea7c85",
    Py0 = "e0027be110ad0f7e1d2415fffb1ded7567cb37f106c9ad5eced2aa38b9e44742c8cb5f3b1c73d935bb51a86df733ac8",
    Py1 = "1275ba7b78e3063c0efe7b9a9ce5b64c713530071c52da0ec8496f47cf8546f83e50faddea736a1d495ee324ec2c290b",
    scalar = "138ecc47a9d5b6cf2a052731b8f016734614949862a9f2be703935a5e0cd43bd",
    Qx0 = "7a7508613526ef10773c9bb6b61310647a0401988ca80bb116748e7db49148db455c5032abc985545d8e082f3445e72",
    Qx1 = "15b0a9ebfb75288e5efd5defc731bbff2d90722dfd6560284078d2886fd2254e27329be5cbe85276dcfa653f2c768337",
    Qy0 = "134961d307616db7353ceb6ad61dee0fb579ebfc4256dccc8c0da35af93db90a84f87cc8cb8c14a8cb524e3dbc8efa46",
    Qy1 = "d672894cc2a42dab3fc420de576c96f3585eb77e037fc3b0b2cc74c6a0e4a197b8a55dc525022289f6cad381c9adadf"
  )

  test(
    id = 7,
    EC = ECP_SWei_Proj[Fp2[BLS12_381]],
    Px0 = "17d02c0921a613211e805a053056f3c32ca517c60220f2a71ff5fb4db0a2645b2fc75edbcc224ec6cd0935074e1a665",
    Px1 = "3ca6158f4cff81eec3a4ce63c3250f6e7dffb9657d7d6b12c49e011ba983e425a9543a4cfda9bf27e57237d7ef2aa28",
    Py0 = "11997fbd203fd972944490bec60ddb023f16e9895fffb93548ad284b3593dd70bcfd6f1efe665f30efd102339f6e59b6",
    Py1 = "84336a1eb009f9173d1c4d2d74b3df6bdd05194208a81a068f1296d26049974014d8b39f5d66ea97ed8cffe177bcfe1",
    scalar = "5668a2332db27199dcfb7cbdfca6317c2ff128db26d7df68483e0a095ec8e88f",
    Qx0 = "1690a2bd0da82c969a43f71ec908921a65b87459eb516e16f27bc43118acb1b5bb5b91c9eeca7afacb4aa2ff5097160f",
    Qx1 = "16ae56ed58e06176173246ecb865f797219f420675e49a789979be0a032108e159fa72a885222f18a4142ee808cab4e1",
    Qy0 = "a44729556da9f1d4adf297e4f4b8de53274bf2d42257ea387185ea245bdabc7fc554b866c14b5100dcd0faf4ddf4079",
    Qy1 = "e94f2652d0bc97087a04e4d9ab638f8b43e99b214f120d08ebb64a401ad6ab1c538d1524540fc37c76601ecc3425529"
  )

  test(
    id = 8,
    EC = ECP_SWei_Proj[Fp2[BLS12_381]],
    Px0 = "7fd385cc4200ad11b1983a9399007cec30ea7de4aebaa3d65347f0566634372d89c0744c95639db223c72d994de816",
    Px1 = "83ce6c36676aa56e2cd615d5617df16514cdf0d2ca11eea21f429649cf65010acd466c93e51e68088bdc16aef189472",
    Py0 = "6407f7f0da8ebf27813e1f1b7339f694d0d134a281aa58855d7d102e2364900b89033904799e3b4d0dcda7946dc9f5a",
    Py1 = "14d1947a7c6ce9e4f146637ba5cab3aa7a50579288f2df221dce1c0ee930c48a9f164b405b72b44c45c971608b1b97d",
    scalar = "45b4bca2f783bba42b2d41a8d00f4c5f18a78738a5678fc3707523e7c62dafcb",
    Qx0 = "b961dddb0fc6b6bdec4119fbfa6c7be6e568fe2ab1ec9d52442ac947f5e99172eef578af5001bcffc293d35b95a5958",
    Qx1 = "13f2abd7f650404eaceeff3f834b3b8f20ed0fb05a4962d9e5798cddae5d107231655b61af5fce76403ff80dc7efebf3",
    Qy0 = "2e45d6e716abe3daed8dba4fd2c030cecd2a3aadf33902d01492d221ac7704d095857a70397aedea783c0cda1624c4f",
    Qy1 = "99785f9572b79e79defdf4cba35e248bd454521227dc7fdaf34d3bfb124a179b219dc69d1521f2c2af9ec0a7b82b0df"
  )

  test(
    id = 9,
    EC = ECP_SWei_Proj[Fp2[BLS12_381]],
    Px0 = "1874fee7c4d207403afb01b5a2d15260e3eb1edd6ee5c3dff6c36dd652c1c34dd2e387671c8663204667e0334699cd43",
    Px1 = "8abd6d2f87e58696a5c1a1d59c852d5a38c4c862f14d5bbf7db139dc7f9d6b19301fdae3c237fe77114b53c2b5a38b0",
    Py0 = "14d126e9f035c55dedf47bb9c784e32866effc223fd450b8415c55b1d7b082ebbcd984d5329d3a3ab400955b908447b0",
    Py1 = "7d41e011283732bdbc704f90d2f41735a7b17362ca0e0b12ca9eacd6a2f1f478bc09922aa7c3c77ef00a5e975a31bc4",
    scalar = "6083671fcc66dc084ad73eba100830555fcfcc5eccaa6acb27cda0d3fa8d6f64",
    Qx0 = "9f62bc139137190c2a04b8334679cd8830a6f9a7fde746397129b5518ef61ac907b39a39200834870dab6f579766cc3",
    Qx1 = "f24da37709b5949766a6fccb28a316ed885c47be935044367fd7418a672e3193f68cffbf7052a33227faa8e453c5e00",
    Qy0 = "410ddc02ae4c5f4cd264252a3f3ee720c9cfce1dd1b844076fa9fa55e4f9802a95e8fd130010b6d9a5ed6011239e9ce",
    Qy1 = "15004542a02d1439838bdb579cba1a4f3258b14d998e4c3e198b9e27c5799c8e1b5a059f731d6380510bb9ff4d6bce00"
  )

  test(
    id = 10,
    EC = ECP_SWei_Proj[Fp2[BLS12_381]],
    Px0 = "171597b604848dac1eea6908b849ed35ab1ea768683ff4cbf299c64da208953c7b95db0e7a514a31b3ea64ffd6bd634",
    Px1 = "1679d3ec65d141fd38c8eeffdce9200d250f38e1dd3a714685d4b01ae677d7ac5c7dd452c768cdfc55249e8352c9f27e",
    Py0 = "c16d445bf20a50baa06f0dba778a013e02c3c619a8b434ec463f79a9c5ec1a069c66bded745420bc5ebccc46ba0cc3e",
    Py1 = "158281e1c97208e3d1388bf85b96fe75072b9ff5f628cb84e8f837ad587b414be3900be35e4df46fd0b4d517ed73a144",
    scalar = "644dc62869683f0c93f38eaef2ba6912569dc91ec2806e46b4a3dd6a4421dad1",
    Qx0 = "e4b186929f609e5d36451d6b62736c0bd7d4e6ed9d7ed14d33cfd715cec150e2f27224756d9f70cf78e72bb41b0ee12",
    Qx1 = "1290bc5038c3ed9ed393e27edc9202751c3533ad2320802f951573f0d6da960572ce57481ab4bcf18c1525e52fd4f4e1",
    Qy0 = "46260daa3ab7f1a855223127450b1963bb594930b59fd627b17275aca76533e9aab01253b5b9d5be2ac18eafbe39ea8",
    Qy1 = "8b2a1941c24f3c0d7a9920f14d4e3066ed0d36839d524494db34e31f386b2523b33dfe1455e04018ef46e44e2ee6886"
  )
