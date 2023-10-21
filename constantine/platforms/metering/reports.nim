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

    const lineSep = &"""|{'-'.repeat(150)}|{'-'.repeat(14)}|{'-'.repeat(20)}|{'-'.repeat(15)}|{'-'.repeat(17)}|{'-'.repeat(26)}|{'-'.repeat(26)}|"""
    echo "\n"
    echo lineSep
    echo &"""|{"Procedures":^150}|{"# of Calls":^14}|{"Throughput (ops/s)":^20}|{"Time (µs)":^15}|{"Avg Time (µs)":^17}|{"CPU cycles (in billions)":^26}|{"Avg cycles (in billions)":^26}|"""
    echo &"""|{flags:^150}|{' '.repeat(14)}|{' '.repeat(20)}|{' '.repeat(15)}|{' '.repeat(17)}|{"indicative only":^26}|{"indicative only":^26}|"""
    echo lineSep
    for m in metrics:
      if m.numCalls == 0:
        continue

      let shortname = block:
        if m.procName.len <= 150: m.procName.replace('\n', ' ')
        else: m.procName[0..145].replace('\n', ' ') & " ..."

      # TODO: running variance / standard deviation but the Welford method is quite costly.
      #       https://nim-lang.org/docs/stats.html / https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance#Welford's_online_algorithm
      let cumulTimeUs = m.cumulatedTimeNs.float64 * 1e-3
      let avgTimeUs = cumulTimeUs / m.numCalls.float64
      let throughput = 1e6 / avgTimeUs
      let cumulCyclesBillions = m.cumulatedCycles.float64 * 1e-9
      let avgCyclesBillions = cumulCyclesBillions / m.numCalls.float64
      echo &"""|{shortname:<150}|{m.numCalls:>14}|{throughput:>20.3f}|{cumulTimeUs:>15.3f}|{avgTimeUs:>17.3f}|"""
    echo lineSep

  else:
    const lineSep = &"""|{'-'.repeat(150)}|{'-'.repeat(14)}|{'-'.repeat(20)}|{'-'.repeat(15)}|{'-'.repeat(17)}|"""
    echo "\n"
    echo lineSep
    echo &"""|{"Procedures":^150}|{"# of Calls":^14}|{"Throughput (ops/s)":^20}|{"Time (µs)":^15}|{"Avg Time (µs)":^17}|"""
    echo &"""|{flags:^150}|{' '.repeat(14)}|{' '.repeat(20)}|{' '.repeat(15)}|{' '.repeat(17)}|"""
    echo lineSep
    for m in metrics:
      if m.numCalls == 0:
        continue

      let shortname = block:
        if m.procName.len <= 150: m.procName.replace('\n', ' ')
        else: m.procName[0..145].replace('\n', ' ') & " ..."

      # TODO: running variance / standard deviation but the Welford method is quite costly.
      #       https://nim-lang.org/docs/stats.html / https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance#Welford's_online_algorithm
      let cumulTimeUs = m.cumulatedTimeNs.float64 * 1e-3
      let avgTimeUs = cumulTimeUs / m.numCalls.float64
      let throughput = 1e6 / avgTimeUs
      echo &"""|{shortname:<150}|{m.numCalls:>14}|{throughput:>20.3f}|{cumulTimeUs:>15.3f}|{avgTimeUs:>17.3f}|"""
    echo lineSep
