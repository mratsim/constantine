# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import  std/[unittest,times],
        constantine/platforms/abstractions,
        constantine/named/algebras,
        constantine/math/arithmetic,
        constantine/math/arithmetic/limbs_unsaturated,
        constantine/math/io/io_bigints,
        helpers/prng_unsafe

# Random seed for reproducibility
var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "\n------------------------------------------------------\n"
echo "test_io_unsaturated xoshiro512** seed: ", seed

type
  RandomGen = enum
    Uniform
    HighHammingWeight
    Long01Sequence

func random_bigint*(rng: var RngState, name: static Algebra, gen: static RandomGen): auto =
  when gen == Uniform:
    rng.random_unsafe(Fp[name].getBigInt())
  elif gen == HighHammingWeight:
    rng.random_highHammingWeight(Fp[name].getBigInt())
  else:
    rng.random_long01Seq(Fp[name].getBigInt())

proc testRoundtrip(name: static Algebra, gen: static RandomGen) =
  const bits = Fp[name].bits()
  const Excess = 2
  const UnsatBitwidth = WordBitWidth - Excess
  const N = bits.ceilDiv_vartime(UnsatBitwidth)

  let a = rng.random_bigint(name, gen)
  var u: LimbsUnsaturated[N, Excess]
  var b: typeof(a)

  u.fromPackedRepr(a.limbs)
  b.limbs.fromUnsatRepr(u)

  doAssert bool(a == b), block:
    "\n  a: " & a.toHex() &
    "\n  b: " & b.toHex()

proc main() =
  suite "Packed <-> Unsaturated limbs roundtrips" & " [" & $WordBitWidth & "-bit words]":
    const Iters = 10000
    test "BN254_Snarks":
      for _ in 0 ..< Iters:
        testRoundtrip(BN254_Snarks, Uniform)
      for _ in 0 ..< Iters:
        testRoundtrip(BN254_Snarks, HighHammingWeight)
      for _ in 0 ..< Iters:
        testRoundtrip(BN254_Snarks, Long01Sequence)
    test "Edwards25519":
      for _ in 0 ..< Iters:
        testRoundtrip(Edwards25519, Uniform)
      for _ in 0 ..< Iters:
        testRoundtrip(Edwards25519, HighHammingWeight)
      for _ in 0 ..< Iters:
        testRoundtrip(Edwards25519, Long01Sequence)
    test "secp256k1":
      for _ in 0 ..< Iters:
        testRoundtrip(Secp256k1, Uniform)
      for _ in 0 ..< Iters:
        testRoundtrip(Secp256k1, HighHammingWeight)
      for _ in 0 ..< Iters:
        testRoundtrip(Secp256k1, Long01Sequence)
    test "BLS12-381":
      for _ in 0 ..< Iters:
        testRoundtrip(BLS12_381, Uniform)
      for _ in 0 ..< Iters:
        testRoundtrip(BLS12_381, HighHammingWeight)
      for _ in 0 ..< Iters:
        testRoundtrip(BLS12_381, Long01Sequence)

main()
