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

# imports for test vector construction
from std / strutils import repeat, join
import std / sequtils
proc sanityTestVectors() =
  ## Test vectors from:
  ## https://homes.esat.kuleuven.be/~bosselae/ripemd160.html
  let vectors = {
   ""                                                               : "0x9c1185a5c5e9fc54612808977ee8f548b2258d31",
   "a"                                                              : "0x0bdc9d2d256b3ee9daae347be6f4dc835a467ffe",
   "abc"                                                            : "0x8eb208f7e05d987a9b044a8e98c6b087f15a0bfc",
   "message digest"                                                 : "0x5d0689ef49d2fae572b881b123a85ffa21595f36",
   toSeq('a'..'z').join()                                           : "0xf71c27109c692c1b56bbdceb5b9d2865b3708dbc",
   "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"       : "0x12a053384a9c0c88e405a06c27dcf49ada62eb2b",
   concat(toSeq('A'..'Z'), toSeq('a'..'z'), toSeq('0'..'9')).join() : "0xb0e20b6e3116640286ed3a87a5713079b21f5189",
   repeat("1234567890", 8)                                          : "0x9b752e45573d4b39f4dbd3323cab82bf63326bfb",
   repeat("a", 1_000_000)                                           : "0x52783243c1697bdbe16d37f97f68f08325dc1528"
  }

  template test(input: string, digest: string): untyped =

    var exp = array[20, byte].fromHex(digest)
    var dgst: array[20, byte]
    ripemd160.hash(dgst, input)
    doAssert dgst == exp

  for v in vectors:
    test(v[0], v[1])

# Differential fuzzing
# --------------------------------------------------------------------

const SmallSizeIters = 64
const LargeSizeIters =  1

when not defined(windows):
  proc innerTest(rng: var RngState, sizeRange: Slice[int]) =
    let size = rng.random_unsafe(sizeRange)
    let msg = rng.random_byte_seq(size)

    var bufCt, bufOssl: array[20, byte]

    ripemd160.hash(bufCt, msg)
    RIPEMD160_OpenSSL(bufOssl, msg)
    doAssert bufCt == bufOssl, "Test failed with message of length " & $size

proc chunkTest(rng: var RngState, sizeRange: Slice[int]) =
  let size = rng.random_unsafe(sizeRange)
  let msg = rng.random_byte_seq(size)

  let chunkSize = rng.random_unsafe(2 ..< 20)

  var bufOnePass: array[20, byte]
  ripemd160.hash(bufOnePass, msg)

  var bufChunked: array[20, byte]
  let maxChunk = max(2, sizeRange.b div 10) # Consume up to 10% at once

  var ctx: Ripemd160Context
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
  echo "RIPEMD160 - sanity checks"
  sanityTestVectors()

  echo "RIPEMD160 - Starting differential testing vs OpenSSL (except on Windows)"

  var rng: RngState
  rng.seed(0xFACADE)

  when not defined(windows):
    echo "RIPEMD160 - 0 <= size < 64 - exhaustive"
    for i in 0 ..< 64:
      rng.innerTest(i .. i)
  else:
    echo "RIPEMD160 - 0 <= size < 64 - exhaustive [SKIPPED]"

  echo "RIPEMD160 - 0 <= size < 64 - exhaustive chunked"
  for i in 0 ..< 64:
    rng.chunkTest(i .. i)

  echo "RIPEMD160 - 64 <= size < 1024B - chunked"
  for _ in 0 ..< SmallSizeIters:
    rng.chunkTest(0 ..< 1024)

  when not defined(windows):
    echo "RIPEMD160 - 64 <= size < 1024B"
    for _ in 0 ..< SmallSizeIters:
      rng.innerTest(0 ..< 1024)

    echo "RIPEMD160 - 1MB <= size < 50MB"
    for _ in 0 ..< LargeSizeIters:
      rng.innerTest(1_000_000 ..< 50_000_000)

    echo "RIPEMD160 - Differential testing vs OpenSSL - SUCCESS"
  else:
    echo "RIPEMD160 - Differential testing vs OpenSSL - [SKIPPED]"

main()
