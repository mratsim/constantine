# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#             Benchmark blueprint
#
# ############################################################

import
  # Internal
  constantine/platforms/abstractions,
  # Helpers
  helpers/prng_unsafe,
  ./platforms,
  # Standard library
  std/[monotimes, times, strformat, strutils, macros]

export strutils, strformat, platforms, times, monotimes, macros

var rng*: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "bench xoshiro512** seed: ", seed

# warmup
proc warmup*() =
  # Warmup - make sure cpu is on max perf
  let start = cpuTime()
  var foo = 123
  for i in 0 ..< 300_000_000:
    foo += i*i mod 456
    foo = foo mod 789

  # Compiler shouldn't optimize away the results as cpuTime rely on sideeffects
  let stop = cpuTime()
  echo &"Warmup: {stop - start:>4.4f} s, result {foo} (displayed to avoid compiler optimizing warmup away)\n"

# warmup()

when defined(gcc):
  echo "\nCompiled with GCC"
elif defined(clang):
  echo "\nCompiled with Clang"
elif defined(vcc):
  echo "\nCompiled with MSVC"
elif defined(icc):
  echo "\nCompiled with ICC"
else:
  echo "\nCompiled with an unknown compiler"

echo "Optimization level => "
echo "  no optimization: ", not defined(release)
echo "  release: ", defined(release)
echo "  danger: ", defined(danger)
echo "  inline assembly: ", UseASM_X86_64

when CTT_32:
  echo "⚠️ Warning: using Constantine with 32-bit limbs"
else:
  echo "Using Constantine with 64-bit limbs"

when SupportsCPUName:
  echo "Running on ", cpuName(), ""

when SupportsGetTicks:
  echo "\n⚠️ Cycles measurements are approximate and use the CPU nominal clock: Turbo-Boost and overclocking will skew them."
  echo "i.e. a 20% overclock will be about 20% off (assuming no dynamic frequency scaling)"

echo "\n=================================================================================================================\n"

proc separator*(length: int) =
  echo "-".repeat(length)

proc notes*() =
  echo ""
  echo "Notes:"
  echo "  - All procedures are constant-time unless mentioned otherwise (unsafe or vartime)"
  echo "  - Compilers:"
  echo "    Compilers are severely limited on multiprecision arithmetic."
  echo "    Constantine compile-time assembler is used by default \"nimble bench_summary_bls12_381\"."
  echo "    GCC is significantly slower than Clang on multiprecision arithmetic due to catastrophic handling of carries."
  echo "    GCC also seems to have issues with large temporaries and register spilling."
  echo "    This is somewhat alleviated by Constantine compile-time assembler but not perfect."
  echo "    Bench on specific compiler with assembler: \"nimble bench_summary_bls12_381_clang\"."
  echo "    Bench on specific compiler with assembler: \"nimble bench_summary_bls12_381_clang_noasm\"."
  echo "  - The simplest operations might be optimized away by the compiler."

template measure*(iters: int,
               startTime, stopTime: untyped,
               startClk, stopClk: untyped,
               body: untyped): untyped =
  let startTime = getMonotime()
  when SupportsGetTicks:
    let startClk = getTicks()
  for _ in 0 ..< iters:
    body
  when SupportsGetTicks:
    let stopClk = getTicks()
  let stopTime = getMonotime()

  when not SupportsGetTicks:
    let startClk = -1'i64
    let stopClk = -1'i64
