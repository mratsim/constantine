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
  std/[unittest, times],
  # Internals
  ../constantine/config/[common, curves],
  ../constantine/arithmetic,
  ../constantine/towers,
  ../constantine/io/[io_bigints, io_fields, io_towers, io_ec],
  ../constantine/elliptic/[ec_weierstrass_projective, ec_scalar_mul],
  # Test utilities
  ../helpers/prng_unsafe,
  ./support/ec_reference_scalar_mult

func testAddAssociativity[EC](a, b, c: EC) =
  var tmp1{.noInit.}, tmp2{.noInit.}: ECP_SWei_Proj[Fp2[BLS12_381]]

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

suite "Short Weierstrass Elliptic Curve - Edge cases [" & $WordBitwidth & "-bit mode]":
  test "EC Add G2 is associative - #60":

    var a, b, c: ECP_SWei_Proj[Fp2[BLS12_381]]
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
