# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#         Template tests for elliptic curve operations
#
# ############################################################

import
  # Standard library
  std/[unittest, times],
  # Internals
  constantine/platforms/abstractions,
  constantine/named/zoo_subgroups,
  constantine/math/[arithmetic, extension_fields],
  constantine/math/elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_jacobian,
    ec_shortweierstrass_projective,
    ec_twistededwards_affine,
    ec_twistededwards_projective,
    ec_shortweierstrass_batch_ops_parallel,
    ec_scalar_mul,
    ec_multi_scalar_mul,
    ec_multi_scalar_mul_parallel],
  constantine/threadpool/threadpool,
  # Test utilities
  helpers/prng_unsafe

export unittest, abstractions, arithmetic, ec_twistededwards_affine # Generic sandwich

type
  RandomGen* = enum
    Uniform
    HighHammingWeight
    Long01Sequence

func random_point*(rng: var RngState, EC: typedesc, randZ: bool, gen: RandomGen): EC {.noInit.} =
  when EC is (EC_ShortW_Aff or EC_TwEdw_Aff):
    if gen == Uniform:
      result = rng.random_unsafe(EC)
    elif gen == HighHammingWeight:
      result = rng.random_highHammingWeight(EC)
    else:
      result = rng.random_long01Seq(EC)
  else:
    if not randZ:
      if gen == Uniform:
        result = rng.random_unsafe(EC)
      elif gen == HighHammingWeight:
        result = rng.random_highHammingWeight(EC)
      else:
        result = rng.random_long01Seq(EC)
    else:
      if gen == Uniform:
        result = rng.random_unsafe_with_randZ(EC)
      elif gen == HighHammingWeight:
        result = rng.random_highHammingWeight_with_randZ(EC)
      else:
        result = rng.random_long01Seq_with_randZ(EC)


proc run_EC_batch_add_parallel_impl*[N: static int](
       ec: typedesc,
       numPoints: array[N, int],
       moduleName: string) =

  # Random seed for reproducibility
  var rng: RngState
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  rng.seed(seed)
  echo "\n------------------------------------------------------\n"
  echo moduleName, " xoshiro512** seed: ", seed

  const testSuiteDesc = "Elliptic curve parallel sum reduction for Short Weierstrass form"

  suite testSuiteDesc & " - " & $ec.G & " - [" & $WordBitWidth & "-bit mode]":

    for n in numPoints:
      test $ec & " parallel sum reduction (N=" & $n & ")":
        proc test(EC: typedesc, gen: RandomGen) =
          let tp = Threadpool.new()
          defer: tp.shutdown()

          var points = newSeq[EC_ShortW_Aff[EC.F, EC.G]](n)

          for i in 0 ..< n:
            points[i] = rng.random_point(EC_ShortW_Aff[EC.F, EC.G], randZ = false, gen)

          var r_batch{.noinit.}, r_ref{.noInit.}: EC

          r_ref.setNeutral()
          for i in 0 ..< n:
            r_ref += points[i]

          tp.sum_reduce_vartime_parallel(r_batch, points)

          check: bool(r_batch == r_ref)


        test(ec, gen = Uniform)
        test(ec, gen = HighHammingWeight)
        test(ec, gen = Long01Sequence)

      test "EC " & $ec.G & " parallel sum reduction (N=" & $n & ") - special cases":
        proc test(EC: typedesc, gen: RandomGen) =
          let tp = Threadpool.new()
          defer: tp.shutdown()

          var points = newSeq[EC_ShortW_Aff[EC.F, EC.G]](n)

          let halfN = n div 2

          for i in 0 ..< halfN:
            points[i] = rng.random_point(EC_ShortW_Aff[EC.F, EC.G], randZ = false, gen)

          for i in halfN ..< n:
            # The special cases test relies on internal knowledge that we sum(points[i], points[i+n/2]
            # It should be changed if scheduling change, for example if we sum(points[2*i], points[2*i+1])
            let c = rng.random_unsafe(3)
            if c == 0:
              points[i] = rng.random_point(EC_ShortW_Aff[EC.F, EC.G], randZ = false, gen)
            elif c == 1:
              points[i] = points[i-halfN]
            else:
              points[i].neg(points[i-halfN])

          var r_batch{.noinit.}, r_ref{.noInit.}: EC

          r_ref.setNeutral()
          for i in 0 ..< n:
            r_ref += points[i]

          tp.sum_reduce_vartime_parallel(r_batch, points)

          check: bool(r_batch == r_ref)

        test(ec, gen = Uniform)
        test(ec, gen = HighHammingWeight)
        test(ec, gen = Long01Sequence)


proc run_EC_multi_scalar_mul_parallel_impl*[N: static int](
       ec: typedesc,
       numPoints: array[N, int],
       moduleName: string) =
  # Random seed for reproducibility
  var rng: RngState
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  rng.seed(seed)
  echo "\n------------------------------------------------------\n"
  echo moduleName, " xoshiro512** seed: ", seed

  const testSuiteDesc = "Elliptic curve parallel multi-scalar-multiplication"

  suite testSuiteDesc & " - " & $ec & " - [" & $WordBitWidth & "-bit mode]":
    for n in numPoints:
      let bucketBits = bestBucketBitSize(n, ec.getScalarField().bits(), useSignedBuckets = false, useManualTuning = false)
      test $ec & " Parallel Multi-scalar-mul (N=" & $n & ", bucket bits (default): " & $bucketBits & ")":
        proc test(EC: typedesc, gen: RandomGen) =
          let tp = Threadpool.new()
          defer: tp.shutdown()
          var points = newSeq[affine(EC)](n)
          var coefs = newSeq[BigInt[EC.getScalarField().bits()]](n)

          for i in 0 ..< n:
            var tmp = rng.random_unsafe(EC)
            tmp.clearCofactor()
            points[i].affine(tmp)
            coefs[i] = rng.random_unsafe(BigInt[EC.getScalarField().bits()])

          var naive, naive_tmp: EC
          naive.setNeutral()
          for i in 0 ..< n:
            naive_tmp.fromAffine(points[i])
            naive_tmp.scalarMul(coefs[i])
            naive += naive_tmp

          var msm: EC
          tp.multiScalarMul_vartime_parallel(msm, coefs, points)

          doAssert bool(naive == msm)

        test(ec, gen = Uniform)
        test(ec, gen = HighHammingWeight)
        test(ec, gen = Long01Sequence)
