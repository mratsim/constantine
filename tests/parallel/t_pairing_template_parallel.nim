# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/unittest, times,
  # Internals
  constantine/platforms/abstractions,
  constantine/math/extension_fields,
  constantine/named/algebras,
  constantine/math/pairings/[
    gt_exponentiations_vartime,
    gt_multiexp_parallel,
    pairings_generic],
  constantine/threadpool,

  # Test utilities
  helpers/prng_unsafe

export
  unittest,     # generic sandwich
  abstractions, # generic sandwich
  extension_fields,
  algebras

type
  RandomGen* = enum
    Uniform
    HighHammingWeight
    Long01Sequence

func random_elem(rng: var RngState, F: typedesc, gen: RandomGen): F {.noInit.} =
  if gen == Uniform:
    result = rng.random_unsafe(F)
  elif gen == HighHammingWeight:
    result = rng.random_highHammingWeight(F)
  else:
    result = rng.random_long01Seq(F)

func random_gt(rng: var RngState, F: typedesc, gen: RandomGen): F {.noInit.} =
  result = rng.random_elem(F, gen)
  result.finalExp()

proc runGTmultiexp_parallel_Tests*[N: static int](GT: typedesc, num_points: array[N, int], Iters: int) =
  var rng: RngState
  let timeseed = uint32(toUnix(getTime()) and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  seed(rng, timeseed)
  echo "\n------------------------------------------------------\n"
  echo "test_pairing_",$GT.Name,"_gt_multiexp_parallel xoshiro512** seed: ", timeseed

  proc test_gt_multiexp_parallel_impl[N](GT: typedesc, rng: var RngState, num_points: array[N, int], gen: RandomGen, iters: int) =
    let tp = Threadpool.new()
    defer: tp.shutdown()

    for N in num_points:
      stdout.write "    "
      for _ in 0 ..< iters:
        var elems = newSeq[GT](N)
        var exponents = newSeq[Fr[GT.Name]](N)

        for i in 0 ..< N:
          elems[i] = rng.random_gt(GT, gen)
          exponents[i] = rng.random_elem(Fr[GT.Name], gen)

        var naive: GT
        naive.setOne()
        for i in 0 ..< N:
          var t {.noInit.}: GT
          t.gtExp_vartime(elems[i], exponents[i])
          naive *= t

        var mexp, mexp_torus: GT
        tp.multiExp_vartime_parallel(mexp, elems, exponents, useTorus = false)
        tp.multiExp_vartime_parallel(mexp_torus, elems, exponents, useTorus = true)

        doAssert bool(naive == mexp)
        doAssert bool(naive == mexp_torus)

        stdout.write '.'

      stdout.write '\n'

  suite "Pairing - Parallel MultiExponentiation for 𝔾ₜ " & $GT.Name & " [" & $WordBitWidth & "-bit words]":
    test "Parallel 𝔾ₜ multi-exponentiation consistency":
      test_gt_multiexp_parallel_impl(GT, rng, num_points, gen = Long01Sequence, Iters)
