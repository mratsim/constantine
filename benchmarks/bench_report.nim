# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy Andre-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import std/strutils

var printedMarkdownHeaders: seq[string]

func markdownEscape*(cell: string): string =
  cell.multiReplace(
    ("\\", "\\\\"),
    ("|", "\\|"),
    ("\r", ""),
    ("\n", "<br>")
  )

func markdownTableHeader*(headers: openArray[string]): string =
  result = "|"
  for header in headers:
    result.add " " & markdownEscape(header) & " |"

func markdownTableSeparator*(columns: int): string =
  result = "|"
  for _ in 0 ..< columns:
    result.add " --- |"

func markdownTableRow*(cells: openArray[string]): string =
  result = "|"
  for cell in cells:
    result.add " " & markdownEscape(cell) & " |"

proc reportMarkdownTable*(headers, cells: openArray[string]) =
  doAssert headers.len == cells.len

  let key = headers.join("\t")
  for printedHeader in printedMarkdownHeaders:
    if printedHeader == key:
      echo markdownTableRow(cells)
      return

  echo markdownTableHeader(headers)
  echo markdownTableSeparator(headers.len)
  printedMarkdownHeaders.add key
  echo markdownTableRow(cells)
