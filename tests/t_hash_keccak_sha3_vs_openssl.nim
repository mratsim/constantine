import
  # Internals
  constantine/hashes,
  constantine/serialization/codecs,
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
# Hash API isn't available on Windows
when not defined(windows):
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

# Test cases
# --------------------------------------------------------------------

proc t_sha3_256_empty =
  var bufCt: array[32, byte]
  let msg = ""
  let hashed = array[32, byte].fromHex("a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a")
  sha3_256.hash(bufCt, msg)
  doAssert bufCt == hashed

proc t_sha3_256_abc =
  var bufCt: array[32, byte]
  let msg = "abc"
  let hashed = array[32, byte].fromHex("3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532")
  sha3_256.hash(bufCt, msg)
  doAssert bufCt == hashed

proc t_sha3_256_abcdef0123456789 =
  var bufCt: array[32, byte]
  let msg = "abcdef0123456789"
  let hashed = array[32, byte].fromHex("11711275e983511cbd160d19d122e1756a44462cef4cc5a83dcc92b46e93a9c4")
  sha3_256.hash(bufCt, msg)
  doAssert bufCt == hashed

proc t_sha3_256_abc_long =
  var bufCt: array[32, byte]
  let msg = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
  let hashed = array[32, byte].fromHex("41c0dba2a9d6240849100376a8235e2c82e1b9998a999e21db32dd97496d3376")
  sha3_256.hash(bufCt, msg)
  doAssert bufCt == hashed

proc t_keccak256_empty =
  var bufCt: array[32, byte]
  let msg = ""
  let hashed = array[32, byte].fromHex("c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
  keccak256.hash(bufCt, msg)
  doAssert bufCt == hashed

proc t_keccak256_abc =
  var bufCt: array[32, byte]
  let msg = "abc"
  let hashed = array[32, byte].fromHex("4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45")
  keccak256.hash(bufCt, msg)
  doAssert bufCt == hashed

proc t_keccak256_abcdef0123456789 =
  var bufCt: array[32, byte]
  let msg = "abcdef0123456789"
  let hashed = array[32, byte].fromHex("9d0db1e0c6820c62f470dbd81e9db48fdf7d76f62027568e6496566fad3661e0")
  keccak256.hash(bufCt, msg)
  doAssert bufCt == hashed

proc t_keccak256_abclong =
  var bufCt: array[32, byte]
  let msg = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
  let hashed = array[32, byte].fromHex("45d3b367a6904e6e8d502ee04999a7c27647f91fa845d456525fd352ae3d7371")
  keccak256.hash(bufCt, msg)
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

  var bufOnePass: array[32, byte]
  sha3_256.hash(bufOnePass, msg)

  var bufChunked: array[32, byte]
  let maxChunk = max(2, sizeRange.b div 10) # Consume up to 10% at once

  var ctx {.noInit.}: sha3_256
  ctx.init()
  var cur = 0
  doWhile size - cur > 0:
    let chunkSize = rng.random_unsafe(0 ..< maxChunk)
    let len = min(chunkSize, size-cur)
    let consumed = len
    ctx.update(msg.toOpenArray(cur, cur+len-1))
    cur += consumed

  ctx.finish(bufChunked)

  doAssert bufOnePass == bufChunked, block:
    "Test failed with message of length " & $size & "\n" &
    "  and chunk range in [" & $sizeRange.a & ", " & $sizeRange.b & ")"

# --------------------------------------------------------------------

proc main() =
  echo "\n------------------------------------------------------\n"
  echo "SHA3-256 & Keccak256 - sanity checks"
  t_sha3_256_empty()
  t_sha3_256_abc()
  t_sha3_256_abcdef0123456789()
  t_sha3_256_abc_long()
  t_keccak256_empty()
  t_keccak256_abc()
  t_keccak256_abcdef0123456789()
  t_keccak256_abclong()

  echo "SHA3-256 - Starting differential testing vs OpenSSL (except on Windows)"

  var rng: RngState
  rng.seed(0xFACADE)

  when not defined(windows):
    echo "SHA3-256 - 0 <= size < 64 - exhaustive"
    for i in 0 ..< 64:
      rng.innerTest(i .. i)
  else:
    echo "SHA3-256 - 0 <= size < 64 - exhaustive [SKIPPED]"

  echo "SHA3-256 - 0 <= size < 64 - exhaustive chunked"
  for i in 0 ..< 64:
    rng.chunkTest(i .. i)

  when not defined(windows):
    echo "SHA3-256 - 135 <= size < 138 - exhaustive (sponge rate = 136)"
    for i in 135 ..< 138:
      rng.innerTest(i .. i)
  else:
    echo "SHA3-256 - 135 <= size < 138 - exhaustive (sponge rate = 136) [SKIPPED]"

  echo "SHA3-256 - 135 <= size < 138 - exhaustive chunked (sponge rate = 136)"
  for i in 135 ..< 138:
    rng.chunkTest(i .. i)

  when not defined(windows):
    echo "SHA3-256 - 64 <= size < 1024B"
    for _ in 0 ..< SmallSizeIters:
      rng.innerTest(0 ..< 1024)

  echo "SHA3-256 - 64 <= size < 1024B - chunked"
  for _ in 0 ..< SmallSizeIters:
    rng.chunkTest(0 ..< 1024)

  when not defined(windows):
    echo "SHA3-256 - 1MB <= size < 50MB"
    for _ in 0 ..< LargeSizeIters:
      rng.innerTest(1_000_000 ..< 50_000_000)

    echo "SHA3-256 - Differential testing vs OpenSSL - SUCCESS"
  else:
    echo "SHA256 - Differential testing vs OpenSSL - [SKIPPED]"

main()
