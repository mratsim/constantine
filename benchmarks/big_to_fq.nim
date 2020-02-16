# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#        Benchmark of the conversion from Big Int to Fq
#
# ############################################################

# 2 implementations are possible
# - 1 based on Montgomery Multiplication
# - 1 based on modular left shift which involves multiple divisions

import
  ../constantine/config/[common, curves],
  ../constantine/math/[bigints_checked, finite_fields],
  random, std/monotimes, times, strformat

const Iters = 1_000_000

randomize(1234)

proc main() =
  var x: BigInt[381]
  x.setInternalBitLength()
  for i in 0 ..< x.limbs.len - 1:
    # Set x to a random value guaranteed below the prime
    x.limbs[i] = Word(rand(BaseType.high.int))


  let start = getMonotime()
  for _ in 0 ..< Iters:
    let y = Fq[BLS12_381].fromBig(x)
  let stop = getMonotime()

  echo &"Time for {Iters} iterations: {inMilliseconds(stop-start)} ms"


main()
# 1_000_000 iterations with -d:danger on i9-9980XE all-core turbo 4.1GHz
# Montgomery Multiplication based: 254ms
# shlAddMod based (using assembly div2n1n!!): 907 ms
# Note: shlAddMod will be even slower when division is made constant-time
