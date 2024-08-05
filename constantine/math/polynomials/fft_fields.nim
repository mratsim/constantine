# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/named/algebras,
  constantine/math/arithmetic,
  constantine/math/io/io_bigints,
  constantine/platforms/[abstractions, allocs, views],
  ./fft_lut,
  constantine/platforms/bithacks # for nextPowerOf2

# ############################################################
#
#               Fast Fourier Transform
#
# ############################################################

# Fast Fourier Transform (Number Theoretic Transform - NTT) over finite fields
# ----------------------------------------------------------------

type
  FFTStatus* = enum
    FFTS_Success
    FFTS_TooManyValues = "Input length greater than the field 2-adicity (number of roots of unity)"
    FFTS_SizeNotPowerOfTwo = "Input must be of a power of 2 length"

  FFT_Descriptor*[F] = object # `F` is either `Fp[Name]` or `Fr[Name]`
    ## Metadata for FFT on Elliptic Curve
    order*: int
    rouGen*: F #getBigInt(F)
    rootsOfUnity*: ptr UncheckedArray[getBigInt(F)] # `getBigInt` gives us the right type depending on Fr/Fp
      ## domain, starting and ending with 1, length is cardinality+1
      ## This allows FFT and inverse FFT to use the same buffer for roots.

func computeRootsOfUnity[F](ctx: var FFT_Descriptor[F], generatorRootOfUnity: auto) =
  static:
    doAssert typeof(generatorRootOfUnity) is Fr[F.Name] or typeof(generatorRootOfUnity) is Fp[F.Name]

  ctx.rootsOfUnity[0].setOne()

  debugecho "Generator ROU: ", generatorRootOfUnity.toHex()
  var res = generatorRootOfUnity
  let p = getBigInt(F).fromDecimal($ctx.order)
  pow(res, p)
  debugecho "To pow ? ", res.toHex()

  var cur = generatorRootOfUnity
  for i in 1 .. ctx.order:
    ctx.rootsOfUnity[i].fromField(cur)
    cur *= generatorRootOfUnity

  doAssert ctx.rootsOfUnity[ctx.order].isOne().bool(), "The given generator does not seem to be a root of unity " &
    "of " & $F & " for order: " & $ctx.order & "."

func init*[Name: static Algebra](T: type FFT_Descriptor, order: int, generatorRootOfUnity: FF[Name]): T =
  result.order = order
  result.rouGen = generatorRootOfUnity
  result.rootsOfUnity = allocHeapArrayAligned(T.F.getBigInt(), order+1, alignment = 64)

  result.computeRootsOfUnity(generatorRootOfUnity)

  for i in 0 ..< result.order:
    debugecho "ω^", i, " = ", result.rootsOfUnity[i].toHex()

proc rootOfUnityGenerator*[F](_: typedesc[F], order: int): F =
  ## `p` = prime of the field (or order of subgroup)
  ## `n` = FFT order
  ## Highlighted the part we compute in each comment.
  # ω = g^( `(p - 1)` // n )
  var exponentI {.noInit.}: BigInt[F.bits()]
  exponentI = F.getModulus()
  exponentI -= One
  var exponent = F.fromBig(exponentI)

  # ω = g^( (p - 1) // `n` )
  var n = F.fromInt(order.uint64)
  #echo "n = ", n.toHex()
  # ω = g^( (p - 1) `// n` )
  n.inv()
  #echo "Inverted? ", n.toHex()
  # ω = g^( `(p - 1) // n` )
  exponent *= n
  #echo "Exp? ", exponent.toHex()

  var g: F = F.fromUint(primitiveRoot(F.Name).uint64)
  # ω = `g^( (p - 1) // n` )
  g.pow_vartime(toBig(exponent))
  #echo "g ? ", g.toHex()
  result = g

proc init*(T: typedesc[FFT_Descriptor], order: int): T =
  ## For example for GF(13) and n == 4:
  ## In backticks the part we currently compute
  let g = rootOfUnityGenerator(T.F, order)
  #let g2 = scaleToRootOfUnity(T.F.Name) # [28 - order]
  #for i, el in g2:
  #  debugecho i, " = ", el.toHex()
  result = T.init(order, g)

func delete*(ctx: FFT_Descriptor) =
  ctx.rootsOfUnity.freeHeapAligned()

proc toFr[S: static int, Name: static Algebra](x: BigInt[S], isMont = true): Fr[Name] =
  result.fromBig(x)

proc toFp[S: static int, Name: static Algebra](x: BigInt[S], isMont = true): Fp[Name] =
  result.fromBig(x)

proc toF[F; S: static int](T: typedesc[F], x: BigInt[S]): auto =
  when T is Fr:
    toFr[S, T.Name](x)
  else:
    toFp[S, T.Name](x)

func simpleFT[F; bits: static int](
       output: var StridedView[F],
       vals: StridedView[F],
       rootsOfUnity: StridedView[BigInt[bits]]) =
  # FFT is a recursive algorithm
  # This is the base-case using a O(n²) algorithm

  let L = output.len
  var last {.noInit.}, v {.noInit.}: F

  var v0w0 {.noinit}: F
  var v0w0In {.noInit.} = vals[0]
  static: echo "TYE ??? ", F.Name, " is fp ? ", F is Fp[Fake13]
  ## XXX: THER IS NO `prod` WITH ONLY 1 EXTRA ARG
  v0w0.prod(v0w0In, F.toF(rootsOfUnity[0]))

  for i in 0 ..< L:
    last = v0w0
    for j in 1 ..< L:
      v.prod(F.toF(rootsOfUnity[(i*j) mod L]), vals[j])
      last.sum(last, v)
    output[i] = last

func fft_internal[F; bits: static int](
       output: var StridedView[F],
       vals: StridedView[F],
       rootsOfUnity: StridedView[BigInt[bits]]) =
  if output.len <= 4:
    simpleFT(output, vals, rootsOfUnity)
    return

  let (evenVals, oddVals) = vals.splitAlternate()
  var (outLeft, outRight) = output.splitHalf()
  let halfROI = rootsOfUnity.skipHalf()

  fft_internal(outLeft, evenVals, halfROI)
  fft_internal(outRight, oddVals, halfROI)

  let half = outLeft.len
  var y_times_root{.noinit.}: F

  for i in 0 ..< half:
    # FFT Butterfly
    y_times_root.prod(F.toF(rootsOfUnity[i]), output[i+half])
    output[i+half].diff(output[i], y_times_root)
    output[i].sum(output[i], y_times_root)


func fft_vartime*[F](
       desc: FFT_Descriptor[F],
       output: var openarray[F],
       vals: openarray[F]): FFT_Status =
  if vals.len > desc.order:
    return FFTS_TooManyValues
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFTS_SizeNotPowerOfTwo

  let rootz = desc.rootsOfUnity
                  .toStridedView(desc.order)
                  .slice(0, desc.order-1, desc.order div vals.len)

  var voutput = output.toStridedView()
  fft_internal(voutput, vals.toStridedView(), rootz)
  return FFTS_Success

# Similar adjustments would be made for ifft_vartime

func ifft_vartime*[F](
       desc: FFT_Descriptor[F],
       output: var openarray[F],
       vals: openarray[F]): FFT_Status =
  ## Inverse FFT
  if vals.len > desc.order:
    return FFTS_TooManyValues
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFTS_SizeNotPowerOfTwo

  let rootz = desc.rootsOfUnity
                  .toStridedView(desc.order+1) # Extra 1 at the end so that when reversed the buffer starts with 1
                  .reversed()
                  .slice(0, desc.order-1, desc.order div vals.len)

  var voutput = output.toStridedView()
  fft_internal(voutput, vals.toStridedView(), rootz)

  var invLen {.noInit.}: F.getBigInt()
  invLen.fromUint(vals.len.uint64)
  invLen.invmod_vartime(invLen, F.getModulus())

  for i in 0 ..< output.len:
    let inp = output[i]
    output[i].prod(inp, F.toF(invLen))

  return FFTS_Success

func fft_vartime*[F](vals: openarray[F]): seq[F] =
  ## Performs an FFT on the given values and returns a seq of the result.
  ##
  ## For convenience only!
  let order = nextPowerOfTwo_vartime(vals.len.uint64)
  var fftDesc = FFTDescriptor[F].init(order.int)
  defer: fftDesc.delete()

  result = newSeq[F](order)
  let status = fftDesc.fft_vartime(result, vals)

  doAssert (status == FFTS_Success).bool, "FFT failed."

proc ifft_vartime*[F](vals: openarray[F]): seq[F] =
  ## Performs an inverse FFT on the given values and returns a seq of the result.
  ##
  ## For convenience only!
  let order = nextPowerOfTwo_vartime(vals.len.uint64)
  var fftDesc = FFTDescriptor[F].init(order.int)
  defer: fftDesc.delete()

  result = newSeq[F](order)
  let status = fftDesc.ifft_vartime(result, vals)

  doAssert (status == FFTS_Success).bool, "FFT failed."
