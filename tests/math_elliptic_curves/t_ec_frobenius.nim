# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.


import
  # Standard library
  std/[times, unittest],
  # Internals
  constantine/platforms/abstractions,
  constantine/named/algebras,
  constantine/math/[arithmetic, extension_fields],
  constantine/math/io/[io_bigints, io_ec],
  constantine/math/elliptic/[ec_shortweierstrass_affine, ec_shortweierstrass_projective, ec_scalar_mul],
  constantine/math/endomorphisms/frobenius,
  # Tests
  helpers/prng_unsafe,
  ./t_ec_template

echo "\n------------------------------------------------------\n"

# Random seed for reproducibility
var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "frobenius xoshiro512** seed: ", seed

proc test(
       id: int,
       EC: typedesc[EC_ShortW_Prj],
       Px0, Px1, Py0, Py1: string,
       Qx0, Qx1, Qy0, Qy1: string
     ) =

  test "test " & $EC & " - " & $id:
    var P: EC
    let pOK = P.fromHex(Px0, Px1, Py0, Py1)
    doAssert pOK

    var Q: EC
    let qOK = Q.fromHex(Qx0, Qx1, Qy0, Qy1)

    var R{.noInit.}: EC

    R.frobenius_psi(P)
    doAssert: bool(R == Q)

suite "ψ (Psi) - Untwist-Frobenius-Twist Endomorphism on G2 vs SageMath" & " [" & $WordBitWidth & "-bit words]":
  # Generated via
  # - sage sage/frobenius_bn254_snarks.sage
  # - sage sage/frobenius_bls12_377.sage
  # - sage sage/frobenius_bls12_381.sage
  test(
    id = 0,
    EC = EC_ShortW_Prj[Fp2[BN254_Snarks], G2],
    Px0 = "598e4c8c14c24c90834f2debedee4db3d31fed98a5134177704bfec14f46cb5",
    Px1 = "c6fffa61daeb7caaf96983e70f164931d958c6820b205cdde19f2fa1eaaa7b1",
    Py0 = "2f5fa252a27df56f5ca2e9c3382c17e531d317d50396f3fe952704304946a5a",
    Py1 = "25f58d3c1a91b83ad645c6cf43f63b5cc36c08d920eaa9c2d7e5a8f8d9f01c6a",
    Qx0 = "14ce20d36d5ad6f84f3f13a4db7dc2e4cc1b568af633f0c1164fbb7804738071",
    Qx1 = "1689941c634aca12aecb1e20e04e9d6b22fc012b534e30436bf0cec03ff0ddde",
    Qy0 = "2eb451e1a4860bcc16a0f898c4fa5b9638975ae20fa3096ed9f3127ca6f0b6de",
    Qy1 = "317e8196e9e77ae0139c6fa6b56f7df1dd88e1f472a6c60e1c1c63065ebc71f"
  )

  test(
    id = 1,
    EC = EC_ShortW_Prj[Fp2[BN254_Snarks], G2],
    Px0 = "21014830dd88a0e7961e704cea531200866c5df46cb25aa3e2aac8d4fec64c6e",
    Px1 = "1db17d8364def10443beab6e4a055c210d3e49c7c3af31e9cfb66d829938dca7",
    Py0 = "1394ab8c346ad3eba14fa14789d3bbfc2deed5a7a510da8e9418580515d27bda",
    Py1 = "1157a26b2639a5258d62577efad8eadffd5814ada3c9b0ce6cae8d29ccafbec9",
    Qx0 = "2099f3e18a043417f28d7eac1ba96856df748201ed667467bb40b14e389e4eb1",
    Qx1 = "2870f4936ec8a10b45b407e493a883da8fb2ebd68dbb35f998bfe7a63d512498",
    Qy0 = "1dfe671f9556e11d771b0a3f0d3884883416866c889ef59cb26a1b9d74c24bb",
    Qy1 = "a348314ec66afb05f015b6f6868e3f483bb03b591d4e53d0c9d9d165b4a9d8"
  )

  test(
    id = 2,
    EC = EC_ShortW_Prj[Fp2[BN254_Snarks], G2],
    Px0 = "46f2a2be9a3e19c1bb484fc37703ff64c3d7379de22249ccf0881037948beec",
    Px1 = "10a5aaae14cb028f4ff4b81d41b712038b9f620a99e208c23504887e56831806",
    Py0 = "2e6c3ebe0f3dada0063dc59f85fe2264dc3502bf65206336106a8d39d838a7b2",
    Py1 = "1fc7d880dc104e05dfdc7f8b96a6c1f2486c6228d13a0f04d4e10b15f0c77e96",
    Qx0 = "284e28ea45121a3ec0fffd4b8d3f0c470eff76c914e6fc7527f6035cc2a4bf12",
    Qx1 = "6dd235191328f1a7245b968396a04e3f6a569491bd6bdc651092cbb95ff65c9",
    Qy0 = "24823a8704bb36a2f014c93ba78a2152e8f90ebd19e9196a4f61b15b04409fcc",
    Qy1 = "303d0b6bf9db34bdf3beb16dcdbff3a0822b6f241d27b06b3ac1f8707941b4e1"
  )

  test(
    id = 3,
    EC = EC_ShortW_Prj[Fp2[BN254_Snarks], G2],
    Px0 = "1cf3af1d41e89d8df378aa81463a978c021f27f4a48387e74655ce2cf5c1f298",
    Px1 = "36553e80e5c7c7360c7a2ae6bf1b8f68eb48804fc7eba7d2f56f09e87bbb0b1",
    Py0 = "25f03e551d74b6be3268bf001905dfbe0bcbe43a2d1aac645a3ca8650b52e551",
    Py1 = "2c24c71b843695a003dd5657dba745ce44f7708d9c5c4e0fd1f905751724a57a",
    Qx0 = "2c2381c01df71c0762db9458cc369d43a7b2a4f28861580d543010959a8790c1",
    Qx1 = "15c9e53568fe7c0d260224d5bc179ecd1bc16b09f421ed56609809c5c5c3bf9b",
    Qy0 = "1e5d31d9cda2dd3344a585ffa3273fbed22a1fdf33b45025a480f2e4c07c10ec",
    Qy1 = "a8e13d82a6d1f503ce2437733b55b17452d5cc2ff7219f684f343b9c4b09a81"
  )

  # --------------------------------------------------------------------------

  test(
    id = 0,
    EC = EC_ShortW_Prj[Fp2[BLS12_377], G2],
    Px0 = "112de13b7cd42bccdb005f2d4dc2726f360243103335ef6cf5e217e777554ae7c1deff5ddb5bcbb581fc9f13728a439",
    Px1 = "10d1a8963e5c6854d5e610ece9914f9b5619c27652be1e9ec3e87687d63ed5d45b449bf59c2481e18ac6159f75966ac",
    Py0 = "8aaf3a8660cf0edd6e97a2cd7837af1c63ec89e18f9bf4c64638662a661636b928a4f8097e6a2e8dfa11e13c51b075",
    Py1 = "163eeb32f275bc5e17546382180b0baefeea482d4da1f7d4938670c66167c7912f571ab3e0426266247b102f8351b3c",
    Qx0 = "2ffc357b6f63a3a040b9f1113d1806d35897abcc38fc7617354b9ea834f4c66dcd87e459ab6cafdcdfe2ae44f8bc5",
    Qx1 = "17f1a16aa1cfead79134b075300cb5999015f4314d82656c04871289a476451221adeb202754a4d21a57fb03f5c39aa",
    Qy0 = "1904a3f203c94c832388cda6c10aa38243c44ae61ee31472d9197d9668e37d58cc6f2181004a9520b27bddc7e523e3a",
    Qy1 = "98505fd21506437c605d28f809bd6215431154fa8175f0eaa02928130437e44840acb284f09bf3973350dac32a6dae"
  )

  test(
    id = 1,
    EC = EC_ShortW_Prj[Fp2[BLS12_377], G2],
    Px0 = "2f9318360b53c2d706061f527571e91679e6086a72ce8203ba1a04850f83bb192b29307e9b2d63feb1d23979e3f632",
    Px1 = "3cbab0789968a3a35fa5d2e2326baa40c34d11a4af05a4109350944300ce32eef74dc5e47ba46717bd8bf87604696d",
    Py0 = "14ea84922f76f2681fec869dce26141392975dcdb4f21d5fa8aec06b37bf71ba6249c219ecbaef4a266196dafb4ad19",
    Py1 = "187cac5daa215b608daab087a9c5ba4364424bb4770c4c5e33112efe931c8a87253f90db38948f3094eb71f3ba593e5",
    Qx0 = "3fdbf071e73c2b81d6c3bb7d0deb03460a6fbc13d488644023a16fa0e7bc992f9304f62c37cbd67af0d7f5ef00891c",
    Qx1 = "14c3aa3f9ee2a1a9dfd629611907842444fa49212be5732f5594f26c6bcc455d51ba78f593d344729e1eb1a32646149",
    Qy0 = "150af74166adf3ae9645178b525e3db9d0141c1b39d9259cf17ba066ea71a3b1163a8d1299a4afce6ca4ee5eb2b9ec3",
    Qy1 = "11a869dea20407de3dcfa6288d54edc4afe799c84f8308a7fd9164ea8edcc12d5eda436aafc82cd4ada3b73c9481568"
  )

  test(
    id = 2,
    EC = EC_ShortW_Prj[Fp2[BLS12_377], G2],
    Px0 = "833ca23630be463c388ea6cfcff5b0e3b055065702a84310d2c726aee14d9e140cba05be79b5cb0441816d9e8c8370",
    Px1 = "264a9755524baac8d9e53b0a45789e9dafcb6b453e965061fcfa20bb12a27d9b9417d5277ae2a499b1cfe567d75e2d",
    Py0 = "5b670b9789825e2b48101b5b6e660cf9117e29c521dad54640cb356b674b3946c98cb43909c3495fb6d6d231891b7e",
    Py1 = "8d794bfd3f87b76ef28af168999e89e6b4fe95da0a539e94a0d0215a7abb756c4b479de5d05a950edf720fd0a20d2d",
    Qx0 = "14ab7d6cb634f741384133209d3944cd455ba6abfb7568052f79dedce2a39bbb3a7e4f038a23e8c1b186444997b2f3f",
    Qx1 = "15c2626a4b919778485be345bc044717616ee7b9b97c111c2082cf0f249fc946d0aebd7d523234afd5ee40549a61978",
    Qy0 = "a783f13eeda1f3d58229008ef4b131135cf5363963dbb712be14186d83e281452b1e0a257ab4851feee7efa150247f",
    Qy1 = "11ece9f651b6ca92fe75b277fe3d98ef63cf1a8d467e786be66bb8a705c9cdf2208c715f57540f72b38a3f4cedfc066"
  )

  test(
    id = 3,
    EC = EC_ShortW_Prj[Fp2[BLS12_377], G2],
    Px0 = "14cd89e2e2755ddc086f63fd62e1f9904c3c1497243455c578a963e81b389f04e95ceafc4f47dc777579cdc82eca79b",
    Px1 = "ba8801beba0654f20ccb78783efa7a911d182ec0eb99abe10f9a3d26b46fb7f90552e4ff6beb4df4611a9072be648b",
    Py0 = "12e23bc97d891f2a047bac9c90e728cb89760c812156f96c95e36c40f1c830cf6ecbb5d407b189070d48a92eb461ea6",
    Py1 = "3b5b911592b3b4110f1690afc0c334b15dccb0eaf6d68b4361c19dfad31e55bbdc219e4328026dc31a4ec122235579",
    Qx0 = "151806c45fdb293c57f07e905ea7cbc6f3c9d3803103f7ffec8b499365925f80e63a648a02523e504238ba1417aeef3",
    Qx1 = "159018bfc69cf11ac1666efdace397117d0016e70fdff1f095ea5a5340b8e1d2e2a99ade477c8cd56184994ff8860b4",
    Qy0 = "1756e93f4b477ab09524a52e4a4551f8ffc8216fc29ec04fbdc31a236750535bd91f369171f763f73196cc5d8d1ea52",
    Qy1 = "17aad3c2d6c1918fd733c25be872c445a7afea2191a90b451f85edf7e44a8f9ae4012f7388dad8fc5ccb8e0cb0967b2"
  )

  # --------------------------------------------------------------------------

  test(
    id = 0,
    EC = EC_ShortW_Prj[Fp2[BLS12_381], G2],
    Px0 = "d6904be428a0310dbd6e15a744a774bcf9800abe27536267a5383f1ddbd7783e1dc20098a8e045e3cca66b83f6d7f0f",
    Px1 = "12107f6ef71d0d1e3bcba9e00a0675d3080519dd1b6c086bd660eb2d2bca8f276e283a891b5c0615064d7886af625cf2",
    Py0 = "c592a3546d2d61d671070909e97860822db0a389e351c1744bdbb2c472cf52f3ca3e94068b0b6f3b0121923659131f5",
    Py1 = "f3c8aef3a00761f30948689a45dfa0d48ccda74981147e3e8f4877e1784c6bec49e180be98a139e2ed9dcd36ea31c67",
    Qx0 = "1030dc4b36a818bdafe99b645008e815abe7e75826d62067787cd76e300a1a7a40e7b53d8b4e74fe78e6d9812376d294",
    Qx1 = "17fd5bb7be865765282839efa48fecbcab8be35711d2c878e2d9e874f3328dced52d2a55b1f305f231601f8e700ee6bd",
    Qy0 = "b3359ac6f39e703ceabd522c9e472c60db04086bbd8d446f11c2ebb7fb578dba1b3e064207d26ca17270fc46a008fac",
    Qy1 = "ce5fe60372147ef37f6fb2ce0fbadb1d1e911bacd1d7ffb367183a4ec475fa93552f3016942c5d0838c572d2ae6c32b"
  )

  test(
    id = 1,
    EC = EC_ShortW_Prj[Fp2[BLS12_381], G2],
    Px0 = "112de130b7cd42bccdb005f2d4dc2726f360243103335ef6cf5e217e777554ae7c1deff5ddb5bcbb581fc9f13728a439",
    Px1 = "10d1a89a63e5c6854d5e610ece9914f9b5619c27652be1e9ec3e87687d63ed5d45b449bf59c2481e18ac6159f75966ac",
    Py0 = "11261c8fcb0f4f560479547fe6b2a1c1e8b648d87e54c39f299eba8729294e99b415851d134ca31e8bb861c42e6f1022",
    Py1 = "1674a925228b822022bf721c9be8946825b9776c2c06158b330831856d5e05c5a454271d3ada3cd882cd385e2732db4d",
    Qx0 = "19a679660d4079c1ed073081951e1a6ce2c06efdd16cb782c227badcf412a61692ba9a89fb23c77a00256cc48505e2b2",
    Qx1 = "27442be7b2676bfcda0d655156695f391e6d480b5105b5cd7cee64749bb77b15ce8862d423bfca47f429e0746a5964a",
    Qy0 = "ae1d1f52e7b1445112906d8c7c6c7044f08ddd56c24d054e0cd3f3cbc0591a5164ea362c939b09bbdf3357f31dcd93e",
    Qy1 = "13662a83e7e9b26bbf5df7e1323a09770eb7345435f23207138012be9acfa6b3ee32da7df4830cb1b1cf00ca4bdccce6"
  )

  test(
    id = 2,
    EC = EC_ShortW_Prj[Fp2[BLS12_381], G2],
    Px0 = "2f93183360b53c2d706061f527571e91679e6086a72ce8203ba1a04850f83bb192b29307e9b2d63feb1d23979e3f632",
    Px1 = "3cbab0c789968a3a35fa5d2e2326baa40c34d11a4af05a4109350944300ce32eef74dc5e47ba46717bd8bf87604696d",
    Py0 = "2b8d995b0f2114442b7bbdbe5732fbf94430d6d413e1f388031f3abb956e598cb6764275a75832c1670868c458378b6",
    Py1 = "63743343c86cd84b8396413c23fd851144d607cef8b39a1eeb4dc8d4420739574e0be8c498cc26d74096201f7c40580",
    Qx0 = "1482a7b3dbdd5810c2167cfea50f6fcc076a23d78f9471205f056ce53fc93266a96969f2c627f8da2190760163d69d4e",
    Qx1 = "1106e16aa7dd71959f6a1469de3c5978e6f2177e668faf3d8616ee56a9729b671839754290cece62056ffa9bef7aec55",
    Qy0 = "6826a449ed06645081c1d9212231c4f63c98398a514d2950712bb0f4f9dfd0f83327f8623b2d9f32a9d9d3f891519cf",
    Qy1 = "19424b599275b17e6c8cfdb9c08100a30a64a0b961e91bf2a6ecb5bcd4e698fa4ef823386d488bd368213dc9b23d2ebd"
  )

  test(
    id = 3,
    EC = EC_ShortW_Prj[Fp2[BLS12_381], G2],
    Px0 = "d7d1c55ddf8bd03b7a15c3ea4f8f69aee37bf282d4aac82b7bd1fd47139250b9c708997a7ff8f603e48f0471c2cfe03",
    Px1 = "d145a91934a6ad865d24ab556ae1e6c42decdd05d676b80e53365a6ff7536332859c9682e7200e40515f675415d71a3",
    Py0 = "6de67fa12af93813a42612b1e9449c7b1f160c5de004ec26ea61010e48ba38dcf158d2692f347fdc6c6332bbec7106f",
    Py1 = "8177897afa93cc9aca82eb9df71652ef7360ce3ef484041450ae14b090246f1bb46293d658540c7652df8ac48842c0c",
    Qx0 = "175a00d5aedc82a684a1af83cedb126112af904f9d84c1c2b0175f739a2805f720c9b97454c57e3c09b8231e9fe5ab7b",
    Qx1 = "fbee1da493f45154e2a9bc43b15386757c8dc0db390f9a00f1ccc49ebb14838fa391b8d10b8369294885deb2ae033ed",
    Qy0 = "169027ec8c608a49325edc87b726cec5f768acf48e80bba04d2810a7259d6b834043e65e1775c4d9181aecc4ff1430ec",
    Qy1 = "77ef6850d4a8f181a10196398cd344011a44c50dce00e18578f3526301263492086d44c7c3d1db5b12499b4033116e1"
  )

suite "ψ - psi(psi(P)) == psi2(P) - (Untwist-Frobenius-Twist Endomorphism)" & " [" & $WordBitWidth & "-bit words]":
  const Iters = 8
  proc test(EC: typedesc, randZ: static bool, gen: static RandomGen) =
    for i in 0 ..< Iters:
      let P = rng.random_point(EC, randZ, gen)

      var Q1 {.noInit.}: EC
      Q1.frobenius_psi(P)
      Q1.frobenius_psi(Q1)

      var Q2 {.noInit.}: EC
      Q2.frobenius_psi(P, 2)

      doAssert bool(Q1 == Q2), "\nIters: " & $i & "\n" &
        "P: " & P.toHex() & "\n" &
        "Q1: " & Q1.toHex() & "\n" &
        "Q2: " & Q2.toHex()

  proc testAll(EC: typedesc) =
    test "psi(psi(P)) == psi2(P) for " & $EC:
      test(EC, randZ = false, gen = Uniform)
      test(EC, randZ = true, gen = Uniform)
      test(EC, randZ = false, gen = HighHammingWeight)
      test(EC, randZ = true, gen = HighHammingWeight)
      test(EC, randZ = false, gen = Long01Sequence)
      test(EC, randZ = true, gen = Long01Sequence)

  testAll(EC_ShortW_Prj[Fp2[BN254_Nogami], G2])
  testAll(EC_ShortW_Prj[Fp2[BN254_Snarks], G2])
  testAll(EC_ShortW_Prj[Fp2[BLS12_377], G2])
  testAll(EC_ShortW_Prj[Fp2[BLS12_381], G2])
  testAll(EC_ShortW_Prj[Fp[BW6_761], G2])

suite "ψ²(P) - [t]ψ(P) + [p]P = Inf" & " [" & $WordBitWidth & "-bit words]":
  const Iters = 10
  proc trace(Name: static Algebra): auto =
    # Returns (abs(trace), isNegativeSign)
    when Name == BN254_Snarks:
      # x = "0x44E992B44A6909F1"
      # t = 6x²+1
      return (BigInt[127].fromHex"0x6f4d8248eeb859fbf83e9682e87cfd47", false)
    elif Name == BN254_Nogami:
      # x = "-0x4080000000000001"
      # t = 6x²+1
      return (BigInt[127].fromHex"0x61818000000000030600000000000007", false)
    elif Name == BLS12_377:
      # x = 3 * 2^46 * (7 * 13 * 499) + 1
      # x = 0x8508c00000000001
      # t = x+1
      return (BigInt[64].fromHex"8508c00000000002", false)
    elif Name == BLS12_381:
      # x = "-(2^63 + 2^62 + 2^60 + 2^57 + 2^48 + 2^16)"
      # t = x+1
      return (BigInt[64].fromHex"0xd20100000000ffff", true)
    elif Name == BW6_761:
      # x = 3 * 2^46 * (7 * 13 * 499) + 1
      # x = 0x8508c00000000001
      # t = x^5 - 3*x^4 + 3*x^3 - x + 3 + cofactor_trace*r
      # t = 0x15d8f58f3501dbec1ab2f9cb6145aeecb55fc0d440cb48f058490fb40986940170b5d44300000007467a800000000010
      return (BigInt[381].fromHex"0x15d8f58f3501dbec1ab2f9cb6145aeecb55fc0d440cb48f058490fb40986940170b5d44300000007467a800000000010", false)
    else:
      {.error: "Not implemented".}

  proc test(EC: typedesc, randZ: static bool, gen: static RandomGen) =
    let trace = trace(EC.getName())

    for i in 0 ..< Iters:
      let P = rng.random_point(EC, randZ, gen)

      var r {.noInit.}, psi2 {.noInit.}, tpsi {.noInit.}, pP {.noInit.}: EC

      psi2.frobenius_psi(P, 2)
      tpsi.frobenius_psi(P)
      tpsi.scalarMulGeneric(trace[0]) # Cofactor not cleared, invalid for GLS
      if trace[1]: # negative trace
        tpsi.neg()
      pP = P
      pP.scalarMulGeneric(EC.F.getModulus()) # Multiply beyond curve order, invalid for GLS

      # ψ²(P) - [t]ψ(P) + [p]P = InfinityPoint
      r.diff(psi2, tpsi)
      r += pP

      doAssert bool(r.isNeutral())

  proc testAll(EC: typedesc) =
    test "ψ²(P) - [t]ψ(P) + [p]P = Inf for " & $EC:
      test(EC, randZ = false, gen = Uniform)
      test(EC, randZ = true, gen = Uniform)
      test(EC, randZ = false, gen = HighHammingWeight)
      test(EC, randZ = true, gen = HighHammingWeight)
      test(EC, randZ = false, gen = Long01Sequence)
      test(EC, randZ = true, gen = Long01Sequence)

  testAll(EC_ShortW_Prj[Fp2[BN254_Nogami], G2])
  testAll(EC_ShortW_Prj[Fp2[BN254_Snarks], G2])
  testAll(EC_ShortW_Prj[Fp2[BLS12_377], G2])
  testAll(EC_ShortW_Prj[Fp2[BLS12_381], G2])
  testAll(EC_ShortW_Prj[Fp[BW6_761], G2])

suite "ψ⁴(P) - ψ²(P) + P = Inf (k-th cyclotomic polynomial with embedding degree k=12)" & " [" & $WordBitWidth & "-bit words]":
  const Iters = 10

  proc test(EC: typedesc, randZ: static bool, gen: static RandomGen) =
    for i in 0 ..< Iters:
      let P = rng.random_point(EC, randZ, gen)

      var r {.noInit.}, psi4 {.noInit.}, psi2 {.noInit.}: EC

      psi2.frobenius_psi(P, 2)
      psi4.frobenius_psi(P, 4)
      r.diff(psi4, psi2)
      r += P

      doAssert bool(r.isNeutral())

  proc testAll(EC: typedesc) =
    test "ψ⁴(P) - ψ²(P) + P = Inf for " & $EC:
      test(EC, randZ = false, gen = Uniform)
      test(EC, randZ = true, gen = Uniform)
      test(EC, randZ = false, gen = HighHammingWeight)
      test(EC, randZ = true, gen = HighHammingWeight)
      test(EC, randZ = false, gen = Long01Sequence)
      test(EC, randZ = true, gen = Long01Sequence)

  testAll(EC_ShortW_Prj[Fp2[BN254_Nogami], G2])
  testAll(EC_ShortW_Prj[Fp2[BN254_Snarks], G2])
  testAll(EC_ShortW_Prj[Fp2[BLS12_377], G2])
  testAll(EC_ShortW_Prj[Fp2[BLS12_381], G2])

suite "ψ²(P) - ψ(P) + P = Inf (k-th cyclotomic polynomial with embedding degree k=6)" & " [" & $WordBitWidth & "-bit words]":
  const Iters = 10

  proc test(EC: typedesc, randZ: static bool, gen: static RandomGen) =
    for i in 0 ..< Iters:
      let P = rng.random_point(EC, randZ, gen)

      var r {.noInit.}, psi2 {.noInit.}, psi {.noInit.}: EC

      psi2.frobenius_psi(P, 2)
      psi.frobenius_psi(P)
      r.diff(psi2, psi)
      r += P

      doAssert bool(r.isNeutral())

  proc testAll(EC: typedesc) =
    test "ψ²(P) - ψ(P) + P = Inf " & $EC:
      test(EC, randZ = false, gen = Uniform)
      test(EC, randZ = true, gen = Uniform)
      test(EC, randZ = false, gen = HighHammingWeight)
      test(EC, randZ = true, gen = HighHammingWeight)
      test(EC, randZ = false, gen = Long01Sequence)
      test(EC, randZ = true, gen = Long01Sequence)

  testAll(EC_ShortW_Prj[Fp[BW6_761], G2])
