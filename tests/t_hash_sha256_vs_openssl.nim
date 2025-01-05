import
  # Internals
  constantine/hashes,
  constantine/serialization/codecs,
  # Helpers
  helpers/prng_unsafe

## NOTE: For a reason that evades me at the moment, if we only `import`
## the wrapper, we get a linker error of the form:
##
## @mopenssl_wrapper.nim.c:(.text+0x110): undefined reference to `Dl_1073742356_'
## /usr/bin/ld: warning: creating DT_TEXTREL in a PIE
##
## So for the moment, we just include the wrapper.
include ./openssl_wrapper

# Test cases
# --------------------------------------------------------------------

proc sanityABC =
  var bufCt: array[32, byte]
  let msg = "abc"

  let hashed = array[32, byte].fromHex(
    "BA7816BF8F01CFEA414140DE5DAE2223" &
    "B00361A396177A9CB410FF61F20015AD")

  sha256.hash(bufCt, msg)

  doAssert bufCt == hashed

proc sanityABC2 =
  var bufCt: array[32, byte]
  let msg = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"

  let hashed = array[32, byte].fromHex(
    "248D6A61D20638B8E5C026930C3E6039" &
    "A33CE45964FF2167F6ECEDD419DB06C1")

  sha256.hash(bufCt, msg)

  doAssert bufCt == hashed

# Differential fuzzing
# --------------------------------------------------------------------

const SmallSizeIters = 64
const LargeSizeIters =  1

when not defined(windows):
  proc innerTest(rng: var RngState, sizeRange: Slice[int]) =
    let size = rng.random_unsafe(sizeRange)
    let msg = rng.random_byte_seq(size)

    var bufCt, bufOssl: array[32, byte]

    sha256.hash(bufCt, msg)
    SHA256_OpenSSL(bufOssl, msg)
    doAssert bufCt == bufOssl, "Test failed with message of length " & $size

proc chunkTest(rng: var RngState, sizeRange: Slice[int]) =
  let size = rng.random_unsafe(sizeRange)
  let msg = rng.random_byte_seq(size)

  let chunkSize = rng.random_unsafe(2 ..< 20)

  var bufOnePass: array[32, byte]
  sha256.hash(bufOnePass, msg)

  var bufChunked: array[32, byte]
  let maxChunk = max(2, sizeRange.b div 10) # Consume up to 10% at once

  var ctx: Sha256Context
  ctx.init()
  var cur = 0
  while size - cur > 0:
    let chunkSize = rng.random_unsafe(0 ..< maxChunk)
    let stop = min(cur+chunkSize-1, size-1)
    let consumed = stop-cur+1
    ctx.update(msg.toOpenArray(cur, stop))
    cur += consumed

  ctx.finish(bufChunked)

  doAssert bufOnePass == bufChunked

# --------------------------------------------------------------------

proc main() =
  echo "\n------------------------------------------------------\n"
  echo "SHA256 - sanity checks"
  sanityABC()
  sanityABC2()

  echo "SHA256 - Starting differential testing vs OpenSSL (except on Windows)"

  var rng: RngState
  rng.seed(0xFACADE)

  when not defined(windows):
    echo "SHA256 - 0 <= size < 64 - exhaustive"
    for i in 0 ..< 64:
      rng.innerTest(i .. i)
  else:
    echo "SHA256 - 0 <= size < 64 - exhaustive [SKIPPED]"

  echo "SHA256 - 0 <= size < 64 - exhaustive chunked"
  for i in 0 ..< 64:
    rng.chunkTest(i .. i)

  echo "SHA256 - 64 <= size < 1024B - chunked"
  for _ in 0 ..< SmallSizeIters:
    rng.chunkTest(0 ..< 1024)

  when not defined(windows):
    echo "SHA256 - 64 <= size < 1024B"
    for _ in 0 ..< SmallSizeIters:
      rng.innerTest(0 ..< 1024)

    echo "SHA256 - 1MB <= size < 50MB"
    for _ in 0 ..< LargeSizeIters:
      rng.innerTest(1_000_000 ..< 50_000_000)

    echo "SHA256 - Differential testing vs OpenSSL - SUCCESS"
  else:
    echo "SHA256 - Differential testing vs OpenSSL - [SKIPPED]"

main()
