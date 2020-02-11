# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  unittest, random, strutils,
  # Third-party
  ../constantine/io/io,
  ../constantine/math/[bigints_raw, bigints_checked],
  ../constantine/primitives/constant_time

suite "Bigints - Multiprecision modulo":
  test "bitsize 237 mod bitsize 192":
    let a = BigInt[237].fromHex("0x123456789012345678901234567890123456789012345678901234567890")
    let m = BigInt[192].fromHex("0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB")

    let expected = BigInt[192].fromHex("0x34567890123456789012345678901234567886f8091a3087")

    var r: BigInt[192]
    r.reduce(a, m)

    check:
      bool(r == expected)

  test "bitsize 365 mod bitsize 258":
    block:
      let a = BigInt[365].fromHex("0x6c8ae85a6cab4bc530b91177e3f399894ff1fe335b6b3fcdc577ea4f8d754bbe71a6353e8609a4769ec8c56727a")
      let m = BigInt[258].fromHex("0x2cadadfa2bb7d7141ad9728d6955ddb68a8b81ecb6a7610575bf4d6f562b09f0d")

      let expected = BigInt[258].fromHex("0xb7c8844f534bf298645dc118384e975245c1a44ba4b0bca8a04c9db0c9035b9")

      var r: BigInt[258]
      r.reduce(a, m)

      check:
        bool(r == expected)

    block:
      let a = BigInt[365].fromHex("0xbf3e7574adacfcba0016a92269ef5db4a6252cda4f0493e968a83f33657b85a7d23d59630a1f5455ff426ecb9ee")
      let m = BigInt[258].fromHex("0x38aa8382b17797e08a89487925eb716be55620aa482a7098b4d02a4a30a4a1178")

      let expected = BigInt[258].fromHex("0x2512663958ef1b3e6e7f14ce722e72d82e10cbdd05e9fdcfb7cd5580bf074a3fe")

      var r: BigInt[258]
      r.reduce(a, m)

      check:
        bool(r == expected)

    block:
      let a = BigInt[365].fromHex("0x16e20483c4a7f891fae2ddd77688fe72718c843ef4bc211069365a4e23bdc0b62680248fb0bf88760810de9f592b")
      let m = BigInt[258].fromHex("0x315d9c9ed0df4257a2db89e907e5f8a06e26d149e058b73c6db33bdc84c1619a4")

      let expected = BigInt[258].fromHex("0x1b264b514412fdfb7579204afaad1b96d09ed6e4c985baf7e96815ab1c065e88f")

      var r: BigInt[258]
      r.reduce(a, m)

      check:
        bool(r == expected)

  test "bitsize 1955 mod bitsize 459":
      let a = BigInt[1955].fromHex("0x4f688e286a7c6e2b64663d8925c2f686994f2b90d58e7a843087c676c2c614ebab3eef9c765a88fe597b23b0e1fb28c812627366020edeafeefd0bf67a95215b4335412e2bd623b4cf7b69e669e1a8e782ab9a3e5fd443f10f459eed4ec9bd61821d94da82e937989245d481612b83b75d6d393e5de2258ac92aec7cd6e4f12c6b035e1fac3ef22851a8e211232b57db7551c03a88e9272411eea86e15c989be9d2962d5ae32ca35b18060212aaf6599b5a5f2416e436f009728b4017f87f70f4e528c9a33042b6810040c1e64457d56695d03b701540a5537c8cf781ff2ea4be2aa6daf1a5f2f0874a1cf495485a01254c2e2f4a")
      let m = BigInt[459].fromHex("0x47304803a4a8c31e18287ad51c1ac7546c42e23206e9dc43e51eff5fa003f44bd08e542ec2659c405bfa4c9eb518ada943412767361029a902b")

      let expected = BigInt[459].fromHex("0x1f039dfe7c9da071d578b3b852db3916f4d79f6169818085994cbc41610abb7abb96e10d1126313cc281a87c309c2dd43bed745a9603f3c606c")

      var r: BigInt[459]
      r.reduce(a, m)

      check:
        bool(r == expected)

  test "bitsize 2346 mod bitsize 97":
      let a = BigInt[2346].fromHex("0x1b5efa688e4124a71edd035f106c6ea81bafd78f610cd59d46fc6cda548fd970dde6b91c6fa10ab6d198026dea3c46c41495294082f2acc8210fd7ebfb25fdc6ce8131676ab0d749c5a4a83dd08172b3849df30304685192708ff0b510600cbf87be3179ce704adc43f2c9b22ba28c77f0a364fa1a96344d7f338227a8f346c0e721bc1312f53cebfc20fd0763ec039aa83a77ba489056ebee2a462058f1daffec9b5df29474f638185c6684729482a29764b46a5487e159fc4eedda5018d3d18ae1c0c6503ebbbd859b4dff3e09b6567b752d51c9733fc822b2758b69ffd65974a8fbf4ad25a40761bb9b9b6a1f886928fe08f9c1571fe3e3987b15e37208a22f64e2c3ff75a36815b7906fc2a52f7bd32d15e8b0441e8c39ae9127d80946e146db5cd2738")
      let m = BigInt[97].fromHex("0x1100d0717f9fff44c6cc7442e")

      let expected = BigInt[97].fromHex("0x0104ea05300eeb05cd374197b6")

      var r: BigInt[97]
      r.reduce(a, m)

      check:
        bool(r == expected)
