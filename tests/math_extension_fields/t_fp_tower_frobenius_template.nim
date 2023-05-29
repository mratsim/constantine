# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#         Template tests for towered extension fields
#
# ############################################################


import
  # Standard library
  std/[unittest, times],
  # Internals
  ../../constantine/platforms/abstractions,
  ../../constantine/math/extension_fields,
  ../../constantine/math/config/curves,
  ../../constantine/math/arithmetic,
  ../../constantine/math/isogenies/frobenius,
  # Test utilities
  ../../helpers/prng_unsafe

export unittest # Generic sandwich

echo "\n------------------------------------------------------\n"

template ExtField(degree: static int, curve: static Curve): untyped =
  when degree == 2:
    Fp2[curve]
  elif degree == 4:
    Fp4[curve]
  elif degree == 6:
    Fp6[curve]
  elif degree == 12:
    Fp12[curve]
  else:
    {.error: "Unconfigured extension degree".}

type
  RandomGen = enum
    Uniform
    HighHammingWeight
    Long01Sequence

func random_elem(rng: var RngState, F: typedesc, gen: RandomGen): F {.inline, noInit.} =
  if gen == Uniform:
    result = rng.random_unsafe(F)
  elif gen == HighHammingWeight:
    result = rng.random_highHammingWeight(F)
  else:
    result = rng.random_long01Seq(F)

proc runFrobeniusTowerTests*[N](
      ExtDegree: static int,
      Iters: static int,
      TestCurves: static array[N, Curve],
      moduleName: string,
      testSuiteDesc: string) =
  # Random seed for reproducibility
  var rng: RngState
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  rng.seed(seed)
  echo moduleName, " xoshiro512** seed: ", seed

  suite testSuiteDesc & " [" & $WordBitWidth & "-bit words]":
    test "Frobenius(a) = a^p (mod p^" & $ExtDegree & ")":
      proc test(Field: typedesc, Iters: static int, gen: RandomGen) =
        for _ in 0 ..< Iters:
          var a = rng.random_elem(Field, gen)
          var fa {.noInit.}: typeof(a)
          fa.frobenius_map(a, k = 1)
          a.powUnsafeExponent(Field.fieldMod(), window = 3)
          check: bool(a == fa)

      staticFor(curve, TestCurves):
        echo "    Frobenius(a) for ", $ExtField(ExtDegree, curve)
        test(ExtField(ExtDegree, curve), Iters, gen = Uniform)
        test(ExtField(ExtDegree, curve), Iters, gen = HighHammingWeight)
        test(ExtField(ExtDegree, curve), Iters, gen = Long01Sequence)

    test "Frobenius(a, 2) = a^(p^2) (mod p^" & $ExtDegree & ")":
      proc test(Field: typedesc, Iters: static int, gen: RandomGen) =
        for _ in 0 ..< Iters:
          var a = rng.random_elem(Field, gen)
          var fa {.noInit.}: typeof(a)
          fa.frobenius_map(a, k = 2)

          a.powUnsafeExponent(Field.fieldMod(), window = 3)
          a.powUnsafeExponent(Field.fieldMod(), window = 3)

          check:
            bool(a == fa)

      staticFor(curve, TestCurves):
        echo "    Frobenius(a, 2) for ", $ExtField(ExtDegree, curve)
        test(ExtField(ExtDegree, curve), Iters, gen = Uniform)
        test(ExtField(ExtDegree, curve), Iters, gen = HighHammingWeight)
        test(ExtField(ExtDegree, curve), Iters, gen = Long01Sequence)

    test "Frobenius(a, 3) = a^(p^3) (mod p^" & $ExtDegree & ")":
      proc test(Field: typedesc, Iters: static int, gen: RandomGen) =
        for _ in 0 ..< Iters:
          var a = rng.random_elem(Field, gen)
          var fa {.noInit.}: typeof(a)
          fa.frobenius_map(a, k = 3)

          a.powUnsafeExponent(Field.fieldMod(), window = 3)
          a.powUnsafeExponent(Field.fieldMod(), window = 3)
          a.powUnsafeExponent(Field.fieldMod(), window = 3)
          check: bool(a == fa)

      staticFor(curve, TestCurves):
        echo "    Frobenius(a, 3) for ", $ExtField(ExtDegree, curve)
        test(ExtField(ExtDegree, curve), Iters, gen = Uniform)
        test(ExtField(ExtDegree, curve), Iters, gen = HighHammingWeight)
        test(ExtField(ExtDegree, curve), Iters, gen = Long01Sequence)
