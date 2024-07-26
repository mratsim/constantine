# Nim-BLSCurve
# Copyright (c) 2018-Present Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/unittest,
  constantine/named/algebras,
  constantine/ethereum_eip2333_bls12381_key_derivation,
  constantine/math/io/io_bigints,
  constantine/math/arithmetic/bigints,
  constantine/platforms/abstractions,
  constantine/serialization/codecs

type SecretKey = Fr[BLS12_381].getBigInt()

proc toBytes(hex: string): seq[byte] =
  doAssert (hex.len and 1) == 0, "Input hex must have an even number of characters"
  let length = hex.len shr 1 - int(hex[0] == '0' and (hex[1] in {'x', 'X'}))

  result.newSeq(length)
  result.paddedFromHex(hex, bigEndian)

proc test0 =
  let seed = toBytes"0xc55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04"
  let expectedMaster = "6083874454709270928345386274498605044986640685124978867557563392430687146096"
  let child_index = 0'u32
  let expectedChild = "20397789859736650942317412262472558107875392172444076792671091975210932703118"

  var master: SecretKey
  let ok0 = master.derive_master_secretKey(seed)
  doAssert ok0

  var eMaster: SecretKey
  doAssert bool eMaster.fromDecimal(expectedMaster)
  doAssert bool(master == eMaster)

  var child: SecretKey
  let ok1 = child.derive_child_secretKey(master, child_index)
  doAssert ok1

  var eChild: SecretKey
  doAssert bool eChild.fromDecimal(expectedChild)
  doAssert bool(child == eChild)

proc test1 =
  let seed = toBytes"0x3141592653589793238462643383279502884197169399375105820974944592"
  let expectedMaster = "29757020647961307431480504535336562678282505419141012933316116377660817309383"
  let child_index = 3141592653'u32
  let expectedChild = "25457201688850691947727629385191704516744796114925897962676248250929345014287"

  var master: SecretKey
  let ok0 = master.derive_master_secretKey(seed)
  doAssert ok0

  var eMaster: SecretKey
  doAssert bool eMaster.fromDecimal(expectedMaster)
  doAssert bool(master == eMaster)

  var child: SecretKey
  let ok1 = child.derive_child_secretKey(master, child_index)
  doAssert ok1

  var eChild: SecretKey
  doAssert bool eChild.fromDecimal(expectedChild)
  doAssert bool(child == eChild)

proc test2 =
  let seed = toBytes"0x0099FF991111002299DD7744EE3355BBDD8844115566CC55663355668888CC00"
  let expectedMaster = "27580842291869792442942448775674722299803720648445448686099262467207037398656"
  let child_index = 4294967295'u32
  let expectedChild = "29358610794459428860402234341874281240803786294062035874021252734817515685787"

  var master: SecretKey
  let ok0 = master.derive_master_secretKey(seed)
  doAssert ok0

  var eMaster: SecretKey
  doAssert bool eMaster.fromDecimal(expectedMaster)
  doAssert bool(master == eMaster)

  var child: SecretKey
  let ok1 = child.derive_child_secretKey(master, child_index)
  doAssert ok1

  var eChild: SecretKey
  doAssert bool eChild.fromDecimal(expectedChild)
  doAssert bool(child == eChild)

proc test3 =
  let seed = toBytes"0xd4e56740f876aef8c010b86a40d5f56745a118d0906a34e69aec8c0db1cb8fa3"
  let expectedMaster = "19022158461524446591288038168518313374041767046816487870552872741050760015818"
  let child_index = 42'u32
  let expectedChild = "31372231650479070279774297061823572166496564838472787488249775572789064611981"

  var master: SecretKey
  let ok0 = master.derive_master_secretKey(seed)
  doAssert ok0

  var eMaster: SecretKey
  doAssert bool  eMaster.fromDecimal(expectedMaster)
  doAssert bool(master == eMaster)

  var child: SecretKey
  let ok1 = child.derive_child_secretKey(master, child_index)
  doAssert ok1

  var eChild: SecretKey
  doAssert bool  eChild.fromDecimal(expectedChild)
  doAssert bool(child == eChild)

suite "Key Derivation (EIP-2333)":
  test "Test 0":
    test0()
  test "Test 1":
    test1()
  test "Test 2":
    test2()
  test "Test 3":
    test3()
