# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# No exceptions allowed in core cryptographic operations
{.push raises: [].}
{.push checks: off.}

# ############################################################
#
#                    Matrix View
#
# ############################################################

type
  MatrixView*[T] = object
    ## A matrix view over an unowned buffer
    ## Storage is row-major, i.e.:
    ## - items in the same row (next column) are contiguous in memory
    ## - items in the same column (next row) are separated by "row length"
    buffer*: ptr UncheckedArray[T]
    rowStride*: int

func toMatrixView*[T](data: ptr UncheckedArray[T], numRows, numCols: int): MatrixView[T] {.inline.} =
  result.buffer = data
  result.rowStride = numCols

template `[]`*[T](view: MatrixView[T], row, col: int): T =
  ## Access like a 2D matrix
  view.buffer[row*view.rowStride + col]

template `[]=`*[T](view: MatrixView[T], row, col: int, value: T) =
  ## Access like a 2D matrix
  view.buffer[row*view.rowStride + col] = value