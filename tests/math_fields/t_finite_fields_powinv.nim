# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[unittest, times, strutils],
  # Internal
  constantine/platforms/abstractions,
  constantine/math/arithmetic,
  constantine/math/io/[io_bigints, io_fields],
  constantine/named/algebras,
  # Test utilities
  helpers/prng_unsafe


static: doAssert defined(CTT_TEST_CURVES), "This modules requires the -d:CTT_TEST_CURVES compile option"

const Iters = 8

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "\n------------------------------------------------------\n"
echo "test_finite_fields_powinv xoshiro512** seed: ", seed

proc main() =
  suite "Modular exponentiation over finite fields" & " [" & $WordBitWidth & "-bit words]":
    test "n² mod 101":
      let exponent = BigInt[64].fromUint(2'u64)

      block: # 1*1 mod 101
        var n, expected: Fp[Fake101]

        n.fromUint(1'u32)
        expected = n

        var r: Fp[Fake101]
        r.prod(n, n)

        var r_bytes: array[8, byte]
        r_bytes.marshal(r, cpuEndian)
        let rU64 = cast[uint64](r_bytes)

        check:
          # Check equality in the Montgomery domain
          bool(r == expected)
          # Check equality when converting back to natural domain
          1'u64 == rU64

      block: # 1^2 mod 101
        var n, expected: Fp[Fake101]

        n.fromUint(1'u32)
        expected = n

        n.pow(exponent)

        var n_bytes: array[8, byte]
        n_bytes.marshal(n, cpuEndian)
        let r = cast[uint64](n_bytes)

        check:
          # Check equality in the Montgomery domain
          bool(n == expected)
          # Check equality when converting back to natural domain
          1'u64 == r

      block: # 2^2 mod 101
        var n, expected: Fp[Fake101]

        n.fromUint(2'u32)
        expected.fromUint(4'u32)

        n.pow(exponent)

        var n_bytes: array[8, byte]
        n_bytes.marshal(n, cpuEndian)
        let r = cast[uint64](n_bytes)

        check:
          # Check equality in the Montgomery domain
          bool(n == expected)
          # Check equality when converting back to natural domain
          4'u64 == r

      block: # 10^2 mod 101
        var n, expected: Fp[Fake101]

        n.fromUint(10'u32)
        expected.fromUint(100'u32)

        n.pow(exponent)

        var n_bytes: array[8, byte]
        n_bytes.marshal(n, cpuEndian)
        let r = cast[uint64](n_bytes)

        check:
          # Check equality in the Montgomery domain
          bool(n == expected)
          # Check equality when converting back to natural domain
          100'u64 == r

      block: # 11^2 mod 101
        var n, expected: Fp[Fake101]

        n.fromUint(11'u32)
        expected.fromUint(20'u32)

        n.pow(exponent)

        var n_bytes: array[8, byte]
        n_bytes.marshal(n, cpuEndian)
        let r = cast[uint64](n_bytes)

        check:
          # Check equality in the Montgomery domain
          bool(n == expected)
          # Check equality when converting back to natural domain
          20'u64 == r

    test "x^(p-2) mod p (modular inversion if p prime)":
      block:
        var x: Fp[BLS12_381]

        # BN254 field modulus
        x.fromHex("0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47")
        # BLS12-381 prime - 2
        let exponent = BigInt[381].fromHex("0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaa9")

        let expected = "0x0636759a0f3034fa47174b2c0334902f11e9915b7bd89c6a2b3082b109abbc9837da17201f6d8286fe6203caa1b9d4c8"

        x.pow(exponent)
        let computed = x.toHex()

        check:
          computed == expected

      block:
        var x: Fp[BLS12_381]

        # BN254 field modulus
        x.fromHex("0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47")
        # BLS12-381 prime - 2
        let exponent = BigInt[381].fromHex("0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaa9")

        let expected = "0x0636759a0f3034fa47174b2c0334902f11e9915b7bd89c6a2b3082b109abbc9837da17201f6d8286fe6203caa1b9d4c8"

        x.pow_vartime(exponent)
        let computed = x.toHex()

        check:
          computed == expected

  suite "Modular division by 2":
    proc testRandomDiv2(name: static Algebra) =
      test "Random modular div2 testing on " & $Algebra(name):
        for _ in 0 ..< Iters:
          let a = rng.random_unsafe(Fp[name])
          var a2 = a
          a2.double()
          a2.div2()
          check: bool(a == a2)
          a2.div2()
          a2.double()
          check: bool(a == a2)

        for _ in 0 ..< Iters:
          let a = rng.randomHighHammingWeight(Fp[name])
          var a2 = a
          a2.double()
          a2.div2()
          check: bool(a == a2)
          a2.div2()
          a2.double()
          check: bool(a == a2)

        for _ in 0 ..< Iters:
          let a = rng.random_long01Seq(Fp[name])
          var a2 = a
          a2.double()
          a2.div2()
          check: bool(a == a2)
          a2.div2()
          a2.double()
          check: bool(a == a2)

    testRandomDiv2 P224
    testRandomDiv2 BN254_Nogami
    testRandomDiv2 BN254_Snarks
    testRandomDiv2 Edwards25519
    testRandomDiv2 P256
    testRandomDiv2 Secp256k1
    testRandomDiv2 BLS12_377
    testRandomDiv2 BLS12_381
    testRandomDiv2 Bandersnatch
    testRandomDiv2 Pallas
    testRandomDiv2 Vesta

  suite "Modular inversion over prime fields" & " [" & $WordBitWidth & "-bit words]":
    test "Specific tests on Fp[BLS12_381]":
      block: # No inverse exist for 0 --> should return 0 for projective/jacobian to affine coordinate conversion
        var r, x: Fp[BLS12_381]
        x.setZero()
        r.inv(x)
        check: bool r.isZero()

        var r2: Fp[BLS12_381]
        r2.inv_vartime(x)
        check: bool r2.isZero()

      block:
        var r, x: Fp[BLS12_381]
        x.setOne()
        r.inv(x)
        check: bool r.isOne()

        var r2: Fp[BLS12_381]
        r2.inv_vartime(x)
        check: bool r2.isOne()

      block:
        var r, x: Fp[BLS12_381]

        # BN254 field modulus
        x.fromHex("0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47")

        let expected = "0x0636759a0f3034fa47174b2c0334902f11e9915b7bd89c6a2b3082b109abbc9837da17201f6d8286fe6203caa1b9d4c8"
        r.inv(x)
        let computed = r.toHex()

        check: computed == expected

        var r2: Fp[BLS12_381]
        r2.inv_vartime(x)
        let computed2 = r2.toHex()

        check: computed2 == expected

    test "Specific tests on Fp[BN254_Snarks]":
      block:
        var r, x: Fp[BN254_Snarks]
        x.setOne()
        r.inv(x)
        check: bool r.isOne()

      block:
        var r, x, expected: Fp[BN254_Snarks]
        x.fromHex"0x076ef96647587df443d86a7ac8aa12f3f52d5d775287a6f5e47764a59d378309"
        expected.fromHex"2d2ef0cd23dd8ec9e9b47c130942ecd7d7fda5e2dd5af19114bc34565ee355b8"

        r.inv(x)
        check: bool(r == expected)

        var r2: Fp[BN254_Snarks]
        r2.inv_vartime(x)
        check: bool(r2 == expected)

      block:
        var r, x, expected: Fp[BN254_Snarks]
        x.fromHex"0x0d2007d8aaface1b8501bfbe792974166e8f9ad6106e5b563604f0aea9ab06f6"
        expected.fromHex"1b632d8aa572c4356debe80f772228dee49c203f34066a998fba5194b98e56c3"

        r.inv(x)
        check: bool(r == expected)

        var r2: Fp[BN254_Snarks]
        r2.inv_vartime(x)
        check: bool(r2 == expected)

    proc testRandomInv(name: static Algebra) =
      test "Random inversion testing on " & $Algebra(name):
        var aInv, r: Fp[name]
        var aFLT, pm2: Fp[name]
        pm2 = Fp[name].fromUint(2'u)
        pm2.neg()

        for _ in 0 ..< Iters:
          let a = rng.random_unsafe(Fp[name])
          aInv.inv(a)
          r.prod(a, aInv)
          check: bool r.isOne() or (a.isZero() and r.isZero())
          r.prod(aInv, a)
          check: bool r.isOne() or (a.isZero() and r.isZero())

          aInv.inv_vartime(a)
          r.prod(a, aInv)
          check: bool r.isOne() or (a.isZero() and r.isZero())
          r.prod(aInv, a)
          check: bool r.isOne() or (a.isZero() and r.isZero())

          aFLT = a
          aFLT.pow(pm2)
          r.prod(a, aFLT)
          check: bool r.isOne() or (a.isZero() and r.isZero())
          aFLT = a
          aFLT.pow_vartime(pm2)
          r.prod(a, aFLT)
          check: bool r.isOne() or (a.isZero() and r.isZero())

        for _ in 0 ..< Iters:
          let a = rng.randomHighHammingWeight(Fp[name])
          aInv.inv(a)
          r.prod(a, aInv)
          check: bool r.isOne() or (a.isZero() and r.isZero())
          r.prod(aInv, a)
          check: bool r.isOne() or (a.isZero() and r.isZero())

          aInv.inv_vartime(a)
          r.prod(a, aInv)
          check: bool r.isOne() or (a.isZero() and r.isZero())
          r.prod(aInv, a)
          check: bool r.isOne() or (a.isZero() and r.isZero())

          aFLT = a
          aFLT.pow(pm2)
          r.prod(a, aFLT)
          check: bool r.isOne() or (a.isZero() and r.isZero())
          aFLT = a
          aFLT.pow_vartime(pm2)
          r.prod(a, aFLT)
          check: bool r.isOne() or (a.isZero() and r.isZero())

        for _ in 0 ..< Iters:
          let a = rng.random_long01Seq(Fp[name])
          aInv.inv(a)
          r.prod(a, aInv)
          check: bool r.isOne() or (a.isZero() and r.isZero())
          r.prod(aInv, a)
          check: bool r.isOne() or (a.isZero() and r.isZero())

          aInv.inv_vartime(a)
          r.prod(a, aInv)
          check: bool r.isOne() or (a.isZero() and r.isZero())
          r.prod(aInv, a)
          check: bool r.isOne() or (a.isZero() and r.isZero())

          aFLT = a
          aFLT.pow(pm2)
          r.prod(a, aFLT)
          check: bool r.isOne() or (a.isZero() and r.isZero())
          aFLT = a
          aFLT.pow_vartime(pm2)
          r.prod(a, aFLT)
          check: bool r.isOne() or (a.isZero() and r.isZero())


    testRandomInv P224
    testRandomInv BN254_Nogami
    testRandomInv BN254_Snarks
    testRandomInv Edwards25519
    testRandomInv P256
    testRandomInv Secp256k1
    testRandomInv BLS12_377
    testRandomInv BLS12_381
    testRandomInv Bandersnatch
    testRandomInv Pallas
    testRandomInv Vesta

  suite "Batch inversion over prime fields" & " [" & $WordBitWidth & "-bit words]":

    proc testRandomBatchInv(name: static Algebra) =
      const N = 10

      var a: array[N, Fp[name]]
      rng.random_unsafe(a)

      test "Batch inversion: " & alignLeft("random testing", 22) & $Algebra(name):
        var r{.noInit.}, r1{.noInit.}, r2{.noInit.}: array[N, Fp[name]]
        r1.batchInv(a)
        r2.batchInv_vartime(a)
        for i in 0 ..< N:
          r[i].inv_vartime(a[i])
          doAssert bool(r[i] == r1[i])
          doAssert bool(r[i] == r2[i])

      test "Batch inversion: " & alignLeft("zero value in middle", 22) & $Algebra(name):
        var r{.noInit.}, r1{.noInit.}, r2{.noInit.}: array[N, Fp[name]]
        var b = a
        b[N div 2].setZero()
        r1.batchInv(b)
        r2.batchInv_vartime(b)
        for i in 0 ..< N:
          r[i].inv_vartime(b[i])
          doAssert bool(r[i] == r1[i])
          doAssert bool(r[i] == r2[i])

      test "Batch inversion: " & alignLeft("zero value at start", 22) & $Algebra(name):
        var r{.noInit.}, r1{.noInit.}, r2{.noInit.}: array[N, Fp[name]]
        var b = a
        b[0].setZero()
        r1.batchInv(b)
        r2.batchInv_vartime(b)
        for i in 0 ..< N:
          r[i].inv_vartime(b[i])
          doAssert bool(r[i] == r1[i])
          doAssert bool(r[i] == r2[i])

      test "Batch inversion: " & alignLeft("zero value at end", 22) & $Algebra(name):
        var r{.noInit.}, r1{.noInit.}, r2{.noInit.}: array[N, Fp[name]]
        var b = a
        b[N-1].setZero()
        r1.batchInv(b)
        r2.batchInv_vartime(b)
        for i in 0 ..< N:
          r[i].inv_vartime(b[i])
          doAssert bool(r[i] == r1[i])
          doAssert bool(r[i] == r2[i])

      test "Batch inversion: " & alignLeft("multiple zero values", 22) & $Algebra(name):
        var r{.noInit.}, r1{.noInit.}, r2{.noInit.}: array[N, Fp[name]]
        var b = a
        block:
          static: doAssert N < sizeof(rng.next()) * 8, "There are only " & $sizeof(rng.next() * 8) & " bits produced."
          var randomness = rng.next()
          for i in 0 ..< N:
            if bool(randomness and 1):
              b[i].setZero()
        r1.batchInv(b)
        r2.batchInv_vartime(b)
        for i in 0 ..< N:
          r[i].inv_vartime(b[i])
          doAssert bool(r[i] == r1[i])
          doAssert bool(r[i] == r2[i])

    testRandomBatchInv P224
    testRandomBatchInv BN254_Nogami
    testRandomBatchInv BN254_Snarks
    testRandomBatchInv Edwards25519
    testRandomBatchInv P256
    testRandomBatchInv Secp256k1
    testRandomBatchInv BLS12_377
    testRandomBatchInv BLS12_381
    testRandomBatchInv Bandersnatch
    testRandomBatchInv Pallas
    testRandomBatchInv Vesta

main()

proc main_anti_regression =
  suite "Bug highlighted by property-based testing" & " [" & $WordBitWidth & "-bit words]":
    # test "#30 - Euler's Criterion should be 1 for square on FKM12_447":
    #   var a: Fp[FKM12_447]
    #   # square of "0x406e5e74ee09c84fa0c59f2db3ac814a4937e2f57ecd3c0af4265e04598d643c5b772a6549a2d9b825445c34b8ba100fe8d912e61cfda43d"
    #   a.fromHex("0x1e6511b2bfabd7d32d8df7492c66df29ade7fdb21bb0d8f6cacfccb05e45a812a27cd087e1bbb2d202ee29f75a021a6a68d990a2a5e73410")

    #   a.pow_vartime(FKM12_447.getPrimeMinus1div2_BE())
    #   check: bool a.isOne()

    test "#42 - a^(p-3)/4 (inverse square root)":
      # x = -(2^63 + 2^62 + 2^60 + 2^57 + 2^48 + 2^16)
      # p = (x - 1)^2 * (x^4 - x^2 + 1)//3 + x
      # Fp       = GF(p)
      # a = Fp(Integer('0x184d02ce4f24d5e59b4150a57a31b202fd40a4b41d7518c22b84bee475fbcb7763100448ef6b17a6ea603cf062e5db51'))
      # inv = a^((p-3)/4)
      # print('a^((p-3)/4): ' + Integer(inv).hex())

      var a: Fp[BLS12_381]
      a.fromHex"0x184d02ce4f24d5e59b4150a57a31b202fd40a4b41d7518c22b84bee475fbcb7763100448ef6b17a6ea603cf062e5db51"


      var pm3div4 = Fp[BLS12_381].getModulus()
      discard pm3div4.sub SecretWord(3)
      pm3div4.shiftRight(2)

      a.pow_vartime(pm3div4)

      var expected: Fp[BLS12_381]
      expected.fromHex"ec6fc6cd4d8a3afe1114d5288759b40a87b6b2f001c8c41693f13132be04de21ca22ea38bded36f3748e06d7b4c348c"

      check: bool(a == expected)

    test "#43 - a^(p-3)/4 (inverse square root)":
      # x = -(2^63 + 2^62 + 2^60 + 2^57 + 2^48 + 2^16)
      # p = (x - 1)^2 * (x^4 - x^2 + 1)//3 + x
      # Fp       = GF(p)
      # a = Fp(Integer('0x0f16d7854229d8804bcadd889f70411d6a482bde840d238033bf868e89558d39d52f9df60b2d745e02584375f16c34a3'))
      # inv = a^((p-3)/4)
      # print('a^((p-3)/4): ' + Integer(inv).hex())

      var a: Fp[BLS12_381]
      a.fromHex"0x0f16d7854229d8804bcadd889f70411d6a482bde840d238033bf868e89558d39d52f9df60b2d745e02584375f16c34a3"


      var pm3div4 = Fp[BLS12_381].getModulus()
      discard pm3div4.sub SecretWord(3)
      pm3div4.shiftRight(2)

      a.pow_vartime(pm3div4)

      var expected: Fp[BLS12_381]
      expected.fromHex"16bf380e9b6d01aa6961c4fcee02a00cb827b52d0eb2b541ea8b598d32100d0bd7dc9a600852b49f0379e63ba9c5d35e"

      check: bool(a == expected)

  suite "Bug highlighted by 24/7 fuzzing (Guido Vranken's CryptoFuzz / Google-OssFuzz)" & " [" & $WordBitWidth & "-bit words]":
    test "#433 - Short-circuit when Montgomery a' = aR (mod p) == 1":
      let a = BigInt[255].fromDecimal("12549076656233958353659347336803947287922716146853412054870763148006372261952")
      let expected = BigInt[255].fromDecimal("10920338887063814464675503992315976177888879664585288394250266608035967270910")
      var aa = Fr[BLS12_381].fromBig(a)

      doAssert bool(aa.mres.isOne())
      aa.inv_vartime()
      check: bool(aa.toBig() == expected)

main_anti_regression()
