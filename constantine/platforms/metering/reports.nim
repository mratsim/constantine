# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/[strformat, strutils],
  ./benchmarking,
  ./tracer

# Reporting benchmark result
# -------------------------------------------------------

proc reportCli*(metrics: seq[Metadata], flags: string) =

  let name = when SupportsCPUName: cpuName() else: "(name auto-detection not implemented for this CPU family)"
  echo "\nCPU: ", name

  when SupportsGetTicks:
    # https://blog.trailofbits.com/2019/10/03/tsc-frequency-for-all-better-profiling-and-benchmarking/
    # https://www.agner.org/optimize/blog/read.php?i=838
    echo "The CPU Cycle Count is indicative only. It cannot be used to compare across systems, works at your CPU nominal frequency and is sensitive to overclocking, throttling and frequency scaling (powersaving and Turbo Boost)."

    const lineSep = &"""|{'-'.repeat(60)}|{'-'.repeat(14)}|{'-'.repeat(20)}|{'-'.repeat(18)}|{'-'.repeat(18)}|{'-'.repeat(15)}|{'-'.repeat(15)}|"""
    echo "\n"
    echo &"""|{"Procedures":^60}|{"# of Calls":^14}|{"Throughput (ops/s)":^20}|{"Time (10⁻⁶s)":^18}|{"Avg Time (10⁻⁶s)":^18}|{"CPU 10³cycles":^15}|{"Avg 10³cycles":^15}|"""
    echo lineSep
    for m in metrics:
      if m.numCalls == 0:
        continue

      let shortname = block:
        if m.procName.len <= 60: m.procName.replace('\n', ' ')
        else: m.procName[0..55].replace('\n', ' ') & " ..."

      # TODO: running variance / standard deviation but the Welford method is quite costly.
      #       https://nim-lang.org/docs/stats.html / https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance#Welford's_online_algorithm
      let cumulTimeUs = m.cumulatedTimeNs.float64 * 1e-3
      let avgTimeUs = cumulTimeUs / m.numCalls.float64
      let throughput = 1e6 / avgTimeUs
      let cumulCyclesThousands = m.cumulatedCycles.float64 * 1e-3
      let avgCyclesThousands = cumulCyclesThousands.float64 / m.numCalls.float64
      echo &"""|{shortname:<60}|{m.numCalls:>14}|{throughput:>20.3f}|{cumulTimeUs:>18.3f}|{avgTimeUs:>18.3f}|{cumulCyclesThousands:>15.3f}|{avgCyclesThousands:>15.3f}|"""
    # echo lineSep

  else:
    const lineSep = &"""|{'-'.repeat(60)}|{'-'.repeat(14)}|{'-'.repeat(20)}|{'-'.repeat(18)}|{'-'.repeat(18)}|"""
    echo "\n"
    echo &"""|{"Procedures":^60}|{"# of Calls":^14}|{"Throughput (ops/s)":^20}|{"Time (µs)":^18}|{"Avg Time (µs)":^18}|"""
    echo lineSep
    for m in metrics:
      if m.numCalls == 0:
        continue

      let shortname = block:
        if m.procName.len <= 60: m.procName.replace('\n', ' ')
        else: m.procName[0..55].replace('\n', ' ') & " ..."

      # TODO: running variance / standard deviation but the Welford method is quite costly.
      #       https://nim-lang.org/docs/stats.html / https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance#Welford's_online_algorithm
      let cumulTimeUs = m.cumulatedTimeNs.float64 * 1e-3
      let avgTimeUs = cumulTimeUs / m.numCalls.float64
      let throughput = 1e6 / avgTimeUs
      echo &"""|{shortname:<60}|{m.numCalls:>14}|{throughput:>20.3f}|{cumulTimeUs:>18.3f}|{avgTimeUs:>18.3f}|"""
    # echo lineSep
