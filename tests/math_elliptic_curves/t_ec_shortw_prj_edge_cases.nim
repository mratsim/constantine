# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#  Edge cases highlighted by property-based testing or fuzzing
#
# ############################################################

import
  # Standard library
  std/unittest,
  # Internals
  constantine/platforms/abstractions,
  constantine/named/algebras,
  constantine/math/arithmetic,
  constantine/math/extension_fields,
  constantine/math/io/[io_bigints, io_fields, io_extfields],
  constantine/math/elliptic/ec_shortweierstrass_projective

func testAddAssociativity[EC](a, b, c: EC) =
  var tmp1{.noInit.}, tmp2{.noInit.}: EC_ShortW_Prj[Fp2[BLS12_381], G2]

  # r0 = (a + b) + c
  tmp1.sum(a, b)
  tmp2.sum(tmp1, c)
  let r0 = tmp2

  # r1 = a + (b + c)
  tmp1.sum(b, c)
  tmp2.sum(a, tmp1)
  let r1 = tmp2

  # r2 = (a + c) + b
  tmp1.sum(a, c)
  tmp2.sum(tmp1, b)
  let r2 = tmp2

  # r3 = a + (c + b)
  tmp1.sum(c, b)
  tmp2.sum(a, tmp1)
  let r3 = tmp2

  # r4 = (c + a) + b
  tmp1.sum(c, a)
  tmp2.sum(tmp1, b)
  let r4 = tmp2

  # ...

  doAssert bool(r0 == r1)
  doAssert bool(r0 == r2)
  doAssert bool(r0 == r3)
  doAssert bool(r0 == r4)

suite "Short Weierstrass Elliptic Curve - Edge cases [" & $WordBitWidth & "-bit mode]":
  test "EC Add G2 is associative - #60":

    var a, b, c: EC_ShortW_Prj[Fp2[BLS12_381], G2]
    var ax, az, bx, bz, cx, cz: Fp2[BLS12_381]

    ax.fromHex(
      c0 = "0x0e98970ade3ffe2211cb555a47d889ed53a744dc35da27f5bd25d6a4c0931bb32925d8d376afa220afd9202b089e7721",
      c1 = "0x0509eff595efe2d47afecaf025930d2be1f28b55be87abdf1a81676cd233b9adf98a172827ea4b52f295919710e80014"
    )
    az.fromHex(
      c0 = "0x0f3935f4be148bb9c291f4562ac54363e3a82b3fd52dbdcb2281231ddfa3af6a898d48cfdf7e60a718d3b5061d384112",
      c1 = "0x159b8b4aa0a1f09e9beecc5a77340566aeb3160cb62963cf162205fe7f2073956eba23a6381758ff1339b4fc95266d66"
    )

    bx.fromHex(
      c0 = "0x06f7acb144c05d35e73c7af216980b058ddb38a241588c7a480292f8be9f9b1312ab0146744dda43b8f366ff6481780b",
      c1 = "0x0a92a7c2328a3c9b787a6b7a015f692f6163af7314d1296721b88b4e1d605c8525997872c4288c0a404fd0fc645c0928"
    )
    bz.fromHex(
      c0 = "0x0536c3f8eab95080c88e5963773cd164c6afe1d12064dc1a7f89cb03714d78b4e9308449f41aa5ef4d2823d59d0eeb34",
      c1 = "0x0ab1c28bf9856db8770c799f2d9d5aec65d09bbe12f4fe28d896dc651492553d96baab853b72c705da2f7995d0ed5cea"
    )

    cx.fromHex(
      c0 = "0x0ec13a3c32697133a43be9efc46d49e2aaef6d690c1d5645a1bc3aeca8abab0dfa63e3ef89ac1bea9ea82cabbdb5470f",
      c1 = "0x0df8aa37e1828b29c3a21ebf9b72fcc2a0d9f67b62a1c4592161cbc1a849ad5c6991af2a7906609ab5bce4297bc2e312"
    )
    cz.fromHex(
      c0 = "0x05177ec517616c9f154c0861dbc205638396b8af61004bed5166a4dc0ed0c79afa1eb1eef595b3ad925b9a277bbcb9fb",
      c1 = "0x0cf0d2573e26463ab3117a4d27862077a22b2c3e9eeda3098bfa82d1be2bd2149b5b703a8192fdb9d9cc1c0dd3edde54"
    )

    doAssert bool a.trySetFromCoordsXandZ(ax, az)
    doAssert bool b.trySetFromCoordsXandZ(bx, bz)
    doAssert bool c.trySetFromCoordsXandZ(cx, cz)

    testAddAssociativity(a, b, c)

  test "EC Add G2 is associative - #65-1":

    var a, b, c: EC_ShortW_Prj[Fp2[BLS12_381], G2]
    var ax, az, bx, bz, cx, cz: Fp2[BLS12_381]

    ax.fromHex(
      c0 = "0x13d97382a3e097623d191172ec2972f3a4b436e24ae18f8394c9103a37c43b2747d5f7c597eff7bda406000000017ffd",
      c1 = "0x11eca90d537eabf01ead08dce5d4f63822941ce7255cc7bfc62483dceb5d148f23f7bfcaeb7f5ffccd767ff5ffffdffe"
    )
    az.fromHex(
      c0 = "0x15f65ec3fa7ce4935c071a97a256ec6d77ce385370513744df48944613b748b2a8e3bfdb035bfb7a7608ffc00002ff7c",
      c1 = "0x15f646c3fa80e4835bd70a57a196ac6d57ce1653705247455f48983753c758bae9f3800ba3ebeff024c8cbd78002fdfc"
    )

    bx.fromHex(
      c0 = "0x146e5ab3ea40d392d3868086a256ec2d524ce85345c237434ec0904f52d753b1ebf4000bc40c00026607fc000002fffc",
      c1 = "0x15f65ebfb267a4935007168f6256ec6d75c11633705252c55f489857437e08a2ebf3b7a7c40c000275e7fff9f0025ffa"
    )
    bz.fromHex(
      c0 = "0x0da4dec3fa76cb905c071a13a1d2c39906ce502d70085744df48985140be37fa6bd1ffdac407fff27608dfffde60fedc",
      c1 = "0x0df55883b636e29344071a7aa255dc6d25a258126bbe0a455b48985753c4377aeaf3a3f6c40c00027307ffb7ffbdefdc"
    )

    cx.fromHex(
      c0 = "0x11fcc7014aee3c2f1ead04bd25d8996fd29a1d71002e97bdca6d881d13ad1d937ff6ee83c8025feed202fffffbdcfffe",
      c1 = "0x09ee82982d80b1c7bf3e69b228ee461c30bce73d574478841da0bd7941294503292b7809222bfe7d4606f976400244d2"
    )
    cz.fromHex(
      c0 = "0x09ee82982d80b1c7bf3e69b228ee461c30bce73d574478841da0bd7941294503292b7809222bfe7d4606f976400244d2",
      c1 = "0x15f35eab6e70e2922b85d257a256ec6d43794851f05257452de3965753474ca66bf3f923c10bfe022d07d7f60000fffb"
    )

    doAssert bool a.trySetFromCoordsXandZ(ax, az)
    doAssert bool b.trySetFromCoordsXandZ(bx, bz)
    doAssert bool c.trySetFromCoordsXandZ(cx, cz)

    testAddAssociativity(a, b, c)

  test "EC Add G2 is associative - #65-2":

    var a, b, c: EC_ShortW_Prj[Fp2[BLS12_381], G2]
    var ax, az, bx, bz, cx, cz: Fp2[BLS12_381]

    ax.fromHex(
      c0 = "0x0be65dc3f260e3814b86f997a256dc6cf5cbfc536ed257455f48985751c758b6d3efc005c38b00027588befff802fffc",
      c1 = "0x015802786d80b1c7e206290223e4440c40a8da49575c7cc40ca93b99392944fd084ba00124b2fdfde907000000025552"
    )
    az.fromHex(
      c0 = "0x13f1dcf37a53c48a5c071a972236ea6cebce5843674a5324542885d7098337b0e2ebe003b80bd801f588ffb7f55efbdb",
      c1 = "0x05b5dec1fa80e4935c05fa869055ec6cb5b64fc37051d74557088c4753c758baeb31fd03420ae00155fe7e000002fffb"
    )

    bx.fromHex(
      c0 = "0x0beb9e43fa1f34933c06ea5c9206536d67ce585330525744fe485756817f46ba53f3f00bc40c00027188ffeefbf2efe7",
      c1 = "0x15f65ebdf640e4525c051a976256ec6d778c185370524f3d5f48905741c6d829ebf3ff6ba34abfb87607fed3cfaabfa8"
    )
    bz.fromHex(
      c0 = "0x16fbb84711c0596bd3916126d2d0caa1da00b1bc116b70ff4938b574243aa76f754d5f05309fffa90ffbeff9e900b043",
      c1 = "0x13d2848256ff557fbd1601aa27b8f07384e7faca4ae18d030c55883a36d63b1f4778000757ff780163f57ffffffee469"
    )

    cx.fromHex(
      c0 = "0x15d0dd8bf97fe1eb37fe9a827a56e9665ace4bd168120cbd5b208e56f18f547aeaf2000b2289effa61fff7300002f7b9",
      c1 = "0x15f65ec3fa80e4832ec68a97a256ec6d734e27cee05257435ef898554cc748bae3cfda0b998277c27606bffdf202ff7c"
    )
    cz.fromHex(
      c0 = "0x05f61d97f970e1867be71a17a1d6e46d764e53ce7051d5455f4697d7139f54b8eb63f80bc40bfffe6e04fbffb5d2efba",
      c1 = "0x15f65ec3f63fe0115b9ee2871232dc63378e584b6fc95742d807184cbb4735faebf4000ac40afd727608dfef8002ff7c"
    )


    doAssert bool a.trySetFromCoordsXandZ(ax, az)
    doAssert bool b.trySetFromCoordsXandZ(bx, bz)
    doAssert bool c.trySetFromCoordsXandZ(cx, cz)

    testAddAssociativity(a, b, c)
