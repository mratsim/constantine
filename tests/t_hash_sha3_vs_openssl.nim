import
  # Internals
  constantine/hashes,
  # Helpers
  helpers/prng_unsafe

# Deal with platform mess
# --------------------------------------------------------------------
when defined(windows):
  when sizeof(int) == 8:
    const DLLSSLName* = "(libssl-1_1-x64|ssleay64|libssl64).dll"
  else:
    const DLLSSLName* = "(libssl-1_1|ssleay32|libssl32).dll"
else:
  when defined(macosx) or defined(macos) or defined(ios):
    const versions = "(.1.1|.38|.39|.41|.43|.44|.45|.46|.47|.48|.10|.1.0.2|.1.0.1|.1.0.0|.0.9.9|.0.9.8|)"
  else:
    const versions = "(.1.1|.1.0.2|.1.0.1|.1.0.0|.0.9.9|.0.9.8|.48|.47|.46|.45|.44|.43|.41|.39|.38|.10|)"

  when defined(macosx) or defined(macos) or defined(ios):
    const DLLSSLName* = "libssl" & versions & ".dylib"
  elif defined(genode):
    const DLLSSLName* = "libssl.lib.so"
  else:
    const DLLSSLName* = "libssl.so" & versions

# OpenSSL wrapper
# --------------------------------------------------------------------

proc EVP_Q_digest[T: byte|char](
                ossl_libctx: pointer,
                algoName: cstring,
                propq: cstring,
                data: openArray[T],
                digest: var array[32, byte],
                size: ptr uint): int32 {.noconv, dynlib: DLLSSLName, importc.}

proc SHA3_256_OpenSSL[T: byte|char](
      digest: var array[32, byte],
      s: openArray[T]) =
  discard EVP_Q_digest(nil, "SHA3-256", nil, s, digest, nil)

# Test
# --------------------------------------------------------------------

echo "\n------------------------------------------------------\n"
const SmallSizeIters = 64
const LargeSizeIters =  1

proc innerTest(rng: var RngState, sizeRange: Slice[int]) =
  let size = rng.random_unsafe(sizeRange)
  let msg = rng.random_byte_seq(size)

  var bufCt, bufOssl: array[32, byte]

  sha3_256.hash(bufCt, msg)
  SHA3_256_OpenSSL(bufOssl, msg)
  doAssert bufCt == bufOssl, "Test failed with message of length " & $size

template doWhile(a: bool, b: untyped): untyped =
  ## For Keccak / SHA-3, an update MUST be called
  ## before finish, hence we need do while loop
  ## for empty inputs
  while true:
    b
    if not a:
      break

proc chunkTest(rng: var RngState, sizeRange: Slice[int]) =
  let size = rng.random_unsafe(sizeRange)
  let msg = rng.random_byte_seq(size)

  let chunkSize = rng.random_unsafe(2 ..< 20)

  var bufOnePass: array[32, byte]
  sha3_256.hash(bufOnePass, msg)

  var bufChunked: array[32, byte]
  let maxChunk = max(2, sizeRange.b div 10) # Consume up to 10% at once

  var ctx: sha3_256
  ctx.init()
  var cur = 0
  doWhile size - cur > 0:
    let chunkSize = rng.random_unsafe(0 ..< maxChunk)
    let stop = min(cur+chunkSize-1, size-1)
    let consumed = stop-cur+1
    ctx.update(msg.toOpenArray(cur, stop))
    cur += consumed

  ctx.finish(bufChunked)

  doAssert bufOnePass == bufChunked

proc main() =
  echo "SHA3-256 - Starting differential testing vs OpenSSL"

  var rng: RngState
  rng.seed(0xFACADE)

  echo "SHA3-256 - 0 <= size < 64 - exhaustive"
  for i in 0 ..< 64:
    rng.innerTest(i .. i)

  echo "SHA3-256 - 0 <= size < 64 - exhaustive chunked"
  for i in 0 ..< 64:
    rng.chunkTest(i .. i)

  echo "SHA3-256 - 135 <= size < 138 - exhaustive (sponge rate = 136)"
  for i in 135 ..< 138:
    rng.innerTest(i .. i)

  echo "SHA3-256 - 135 <= size < 138 - exhaustive chunked (sponge rate = 136)"
  for i in 135 ..< 138:
    rng.chunkTest(i .. i)

  echo "SHA3-256 - 64 <= size < 1024B"
  for _ in 0 ..< SmallSizeIters:
    rng.innerTest(0 ..< 1024)

  echo "SHA3-256 - 64 <= size < 1024B - chunked"
  for _ in 0 ..< SmallSizeIters:
    rng.chunkTest(0 ..< 1024)

  echo "SHA3-256 - 1MB <= size < 50MB"
  for _ in 0 ..< LargeSizeIters:
    rng.innerTest(1_000_000 ..< 50_000_000)

  echo "SHA3-256 - Differential testing vs OpenSSL - SUCCESS"

main()
