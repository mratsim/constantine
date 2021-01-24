# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# Strided View - Monodimensional Tensors
# ----------------------------------------------------------------
#
# FFT uses recursive divide-and-conquer.
# In code this means need strided views
# to enable different logical views of the same memory buffer.
# Strided views are monodimensional tensors:
# See Arraymancer backend:
# https://github.com/mratsim/Arraymancer/blob/71cf616/src/arraymancer/laser/tensor/datatypes.nim#L28-L32
# Or the minimal tensor implementation challenge:
# https://github.com/SimonDanisch/julia-challenge/blob/b8ed3b6/nim/nim_sol_mratsim.nim#L4-L26

{.experimental: "views".}

type
  View*[T] = object
    ## A strided view over an (unowned) data buffer
    len*: int
    stride: int
    offset: int
    data: lent UncheckedArray[T]

func `[]`*[T](v: View[T], idx: int): lent T {.inline.} =
  v.data[v.offset + idx*v.stride]

func `[]`*[T](v: var View[T], idx: int): var T {.inline.} =
  # Experimental views indeed ...
  cast[ptr UncheckedArray[T]](v.data)[v.offset + idx*v.stride]

func `[]=`*[T](v: var View[T], idx: int, val: T) {.inline.} =
  # Experimental views indeed ...
  cast[ptr UncheckedArray[T]](v.data)[v.offset + idx*v.stride] = val

func toView*[T](oa: openArray[T]): View[T] {.inline.} =
  result.len = oa.len
  result.stride = 1
  result.offset = 0
  result.data = cast[lent UncheckedArray[T]](oa[0].unsafeAddr)

iterator items*[T](v: View[T]): lent T =
  var cur = v.offset
  for _ in 0 ..< v.len:
    yield v.data[cur]
    cur += v.stride

func `$`*(v: View): string =
  result = "View["
  var first = true
  for elem in v:
    if not first:
      result &= ", "
    else:
      first = false
    result &= $elem
  result &= ']'

func toHex*(v: View): string =
  mixin toHex

  result = "View["
  var first = true
  for elem in v:
    if not first:
      result &= ", "
    else:
      first = false
    result &= elem.toHex()
  result &= ']'

# FFT-specific splitting
# -------------------------------------------------------------------------------

func splitAlternate*(t: View): tuple[even, odd: View] {.inline.} =
  ## Split the tensor into 2
  ## partitioning the input every other index
  ## even: indices [0, 2, 4, ...]
  ## odd: indices [ 1, 3, 5, ...]
  assert (t.len and 1) == 0, "The tensor must contain an even number of elements"

  let half = t.len shr 1
  let skipHalf = t.stride shl 1

  result.even.len = half
  result.even.stride = skipHalf
  result.even.offset = t.offset
  result.even.data = t.data

  result.odd.len = half
  result.odd.stride = skipHalf
  result.odd.offset = t.offset + t.stride
  result.odd.data = t.data

func splitMiddle*(t: View): tuple[left, right: View] {.inline.} =
  ## Split the tensor into 2
  ## partitioning into left and right halves.
  ## left:  indices [0, 1, 2, 3]
  ## right: indices  [4, 5, 6, 7]
  assert (t.len and 1) == 0, "The tensor must contain an even number of elements"

  let half = t.len shr 1

  result.left.len = half
  result.left.stride = t.stride
  result.left.offset = t.offset
  result.left.data = t.data

  result.right.len = half
  result.right.stride = t.stride
  result.right.offset = t.offset + half
  result.right.data = t.data

func skipHalf*(t: View): View {.inline.} =
  ## Pick one every other indices
  ## output: [0, 2, 4, ...]
  assert (t.len and 1) == 0, "The tensor must contain an even number of elements"

  result.len = t.len shr 1
  result.stride = t.stride shl 1
  result.offset = t.offset
  result.data = t.data

func slice*(v: View, start, stop, step: int): View {.inline.} =
  ## Slice a view
  ## stop is inclusive
  # General tensor slicing algorithm is
  # https://github.com/mratsim/Arraymancer/blob/71cf616/src/arraymancer/tensor/private/p_accessors_macros_read.nim#L26-L56
  #
  # for i, slice in slices:
  #   # Check if we start from the end
  #   let a = if slice.a_from_end: result.shape[i] - slice.a
  #           else: slice.a
  #
  #   let b = if slice.b_from_end: result.shape[i] - slice.b
  #           else: slice.b
  #
  #   # Compute offset:
  #   result.offset += a * result.strides[i]
  #   # Now change shape and strides
  #   result.strides[i] *= slice.step
  #   result.shape[i] = abs((b-a) div slice.step) + 1
  #
  # with slices being of size 1, as we have a monodimensional Tensor
  # and the slice being a..<b with the reverse case: len-1 -> 0
  #
  # result is preinitialized with a copy of v (shape, stride, offset, data)
  result.offset = v.offset + start * v.stride
  result.stride = v.stride * step
  result.len = abs((stop-start) div step) + 1
  result.data = v.data

func reversed*(v: View): View {.inline.} =
  # Hopefully the compiler optimizes div by -1
  v.slice(v.len-1, 0, -1)

# ############################################################
#
#                    Sanity checks
#
# ############################################################

when isMainModule:
  proc main() =
    var x = [0, 1, 2, 3, 4, 5, 6, 7]
    let v = x.toView()

    echo "view: ", v
    echo "reversed: ", v.reversed()

    block:
      let (even, odd) = v.splitAlternate()
      echo "\nSplit Alternate"
      echo "----------------"
      echo "even: ", even
      echo "odd:  ", odd

      block:
        let (ee, eo) = even.splitAlternate()
        echo ""
        echo "even-even: ", ee
        echo "even-odd:  ", eo
        echo "even-even rev: ", ee.reversed()
        echo "even-odd rev:  ", eo.reversed()

      block:
        let (oe, oo) = odd.splitAlternate()
        echo ""
        echo "odd-even: ", oe
        echo "odd-odd:  ", oo
        echo "odd-even rev: ", oe.reversed()
        echo "odd-odd rev:  ", oo.reversed()

    echo "\nSkip Half"
    echo "----------------"
    echo "skipHalf: ", v.skipHalf()
    echo "skipQuad: ", v.skipHalf().skipHalf()
    echo "skipQuad rev: ", v.skipHalf().skipHalf().reversed()

    echo "\nSplit middle"
    echo "----------------"
    block:
      let (left, right) = v.splitMiddle()
      echo "left:  ", left
      echo "right: ", right
      block:
        let (ll, lr) = left.splitMiddle()
        echo ""
        echo "left-left:  ", ll
        echo "left-right: ", lr
        echo "left-left rev:  ", ll.reversed()
        echo "left-right rev: ", lr.reversed()

      block:
        let (rl, rr) = right.splitMiddle()
        echo ""
        echo "right-left:  ", rl
        echo "right-right: ", rr
        echo "right-left rev:  ", rl.reversed()
        echo "right-right rev: ", rr.reversed()

  main()
