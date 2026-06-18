# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy Andre-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/unittest,
  ../benchmarks/bench_report

suite "Benchmark Markdown reports":
  test "renders a Markdown table header":
    check markdownTableHeader(["Operation", "Domain"]) == "| Operation | Domain |"
    check markdownTableSeparator(2) == "| --- | --- |"

  test "escapes Markdown table cells":
    check markdownTableRow(["A | B", "line 1\nline 2"]) == "| A \\| B | line 1<br>line 2 |"
