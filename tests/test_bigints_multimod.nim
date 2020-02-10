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
  ../constantine/[io, bigints_raw, bigints_public, primitives]

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
    let a = BigInt[365].fromHex("0x6c8ae85a6cab4bc530b91177e3f399894ff1fe335b6b3fcdc577ea4f8d754bbe71a6353e8609a4769ec8c56727a")
    let m = BigInt[258].fromHex("0x2cadadfa2bb7d7141ad9728d6955ddb68a8b81ecb6a7610575bf4d6f562b09f0d")

    let expected = BigInt[258].fromHex("0xb7c8844f534bf298645dc118384e975245c1a44ba4b0bca8a04c9db0c9035b9")

    var r: BigInt[258]
    r.reduce(a, m)

    check:
      bool(r == expected)
