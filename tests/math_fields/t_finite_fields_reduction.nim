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
  # Internal
  constantine/named/algebras,
  constantine/platforms/abstractions,
  constantine/math/arithmetic,
  constantine/math/io/io_fields,
  # Test utilities
  helpers/prng_unsafe

const Iters = 12

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "\n------------------------------------------------------\n"
echo "test_finite_fields_reduction xoshiro512** seed: ", seed

static: doAssert defined(CTT_TEST_CURVES), "This modules requires the -d:CTT_TEST_CURVES compile option"

suite "Crandall prime reduction - anti-regression tests" & " [" & $WordBitWidth & "-bit words]":
  test "Secp256k1 - multiplication by 1 (S=0 edge case)":
    ## Bug: When S = N*WordBitWidth - m = 0 (Secp256k1 case),
    ## the reduction code was doing `r[N-1] shr (WordBitWidth-S)` = `r[3] shr 64`
    ## which is undefined behavior and caused incorrect reduction.
    ## This test ensures multiplication by 1 preserves the value.
    for _ in 0 ..< Iters:
      let a = rng.random_unsafe(Fp[Secp256k1])
      var b: Fp[Secp256k1]
      b.setOne()
      
      var r: Fp[Secp256k1]
      r.prod(a, b)
      
      doAssert bool(r == a), block:
        "\nSecp256k1 mul by 1 failed:" &
        "\nInput:    " & a.toHex() &
        "\nExpected: " & a.toHex() &
        "\nGot:      " & r.toHex()

  test "Secp256k1 - squaring consistency":
    ## Ensure squaring produces same result as multiplication
    for _ in 0 ..< Iters:
      let a = rng.random_unsafe(Fp[Secp256k1])
      
      var r_sqr, r_mul: Fp[Secp256k1]
      r_sqr.square(a)
      r_mul.prod(a, a)
      
      doAssert bool(r_sqr == r_mul), block:
        "\nSecp256k1 squaring inconsistency:" &
        "\nInput: " & a.toHex() &
        "\nSquare: " & r_sqr.toHex() &
        "\nMul:    " & r_mul.toHex()

  test "Secp256k1 - multiplication associativity":
    ## (a * b) * c == a * (b * c)
    for _ in 0 ..< Iters:
      let a = rng.random_unsafe(Fp[Secp256k1])
      let b = rng.random_unsafe(Fp[Secp256k1])
      let c = rng.random_unsafe(Fp[Secp256k1])
      
      var r1, r2, tmp: Fp[Secp256k1]
      tmp.prod(a, b)
      r1.prod(tmp, c)
      
      tmp.prod(b, c)
      r2.prod(a, tmp)
      
      doAssert bool(r1 == r2), block:
        "\nSecp256k1 associativity failed:" &
        "\na: " & a.toHex() &
        "\nb: " & b.toHex() &
        "\nc: " & c.toHex() &
        "\n(a*b)*c:     " & r1.toHex() &
        "\na*(b*c):     " & r2.toHex()

  test "Secp256k1 - multiplication with high Hamming weight values":
    ## Test reduction with values that have many bits set
    for _ in 0 ..< Iters:
      let a = rng.random_highHammingWeight(Fp[Secp256k1])
      var b: Fp[Secp256k1]
      b.setOne()
      
      var r: Fp[Secp256k1]
      r.prod(a, b)
      
      doAssert bool(r == a), block:
        "\nSecp256k1 mul by 1 (high Hamming) failed:" &
        "\nInput:    " & a.toHex() &
        "\nExpected: " & a.toHex() &
        "\nGot:      " & r.toHex()

  test "Secp256k1 - specific edge case values":
    ## Test specific values that triggered the bug
    block:
      var a: Fp[Secp256k1]
      a.fromHex("0x7123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
      
      var b: Fp[Secp256k1]
      b.setOne()
      
      var r: Fp[Secp256k1]
      r.prod(a, b)
      
      doAssert bool(r == a), block:
        "\nSecp256k1 specific value test failed:" &
        "\nInput:    " & a.toHex() &
        "\nExpected: " & a.toHex() &
        "\nGot:      " & r.toHex()

    block:
      var a: Fp[Secp256k1]
      a.fromHex("0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
      
      var b: Fp[Secp256k1]
      b.setOne()
      
      var r: Fp[Secp256k1]
      r.prod(a, b)
      
      doAssert bool(r == a), block:
        "\nSecp256k1 specific value test 2 failed:" &
        "\nInput:    " & a.toHex() &
        "\nExpected: " & a.toHex() &
        "\nGot:      " & r.toHex()

  test "Edwards25519 - multiplication by 1":
    ## Edwards25519 also uses Crandall primes but with S != 0
    ## This ensures we didn't break non-Secp256k1 Crandall primes
    for _ in 0 ..< Iters:
      let a = rng.random_unsafe(Fp[Edwards25519])
      var b: Fp[Edwards25519]
      b.setOne()
      
      var r: Fp[Edwards25519]
      r.prod(a, b)
      
      doAssert bool(r == a), block:
        "\nEdwards25519 mul by 1 failed:" &
        "\nInput:    " & a.toHex() &
        "\nExpected: " & a.toHex() &
        "\nGot:      " & r.toHex()

  test "Edwards25519 - squaring consistency":
    for _ in 0 ..< Iters:
      let a = rng.random_unsafe(Fp[Edwards25519])
      
      var r_sqr, r_mul: Fp[Edwards25519]
      r_sqr.square(a)
      r_mul.prod(a, a)
      
      doAssert bool(r_sqr == r_mul), block:
        "\nEdwards25519 squaring inconsistency:" &
        "\nInput: " & a.toHex() &
        "\nSquare: " & r_sqr.toHex() &
        "\nMul:    " & r_mul.toHex()