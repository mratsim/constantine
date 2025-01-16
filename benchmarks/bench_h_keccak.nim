import
  # Internals
  constantine/hashes,
  # Helpers
  helpers/prng_unsafe,
  ./bench_blueprint

proc separator*() = separator(69)

# Deal with platform mess
# --------------------------------------------------------------------
when false:
  include ./openssl_wrapper

# OpenSSL wrapper
# --------------------------------------------------------------------
# Only supported on OpenSSL 3.3, and even then it might have been removed in OpenSSL 3.4
# On MacOS the default libssl is actually LibreSSL which doesn't provide the new mandatory (for Keccak) EVP API

when false:
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

# --------------------------------------------------------------------

proc report(op: string, bytes: int, startTime, stopTime: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stopTime-startTime) div iters)
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    let cycles = (stopClk - startClk) div iters
    let cyclePerByte = cycles.float64 / bytes.float64
    echo &"{op:<50}     {throughput:>15.3f} ops/s    {ns:>9} ns/op    {cycles:>10} cycles    {cyclePerByte:>5.2f} cycles/byte"
  else:
    echo &"{op:<50}     {throughput:>15.3f} ops/s    {ns:>9} ns/op"

template bench(op: string, bytes: int, iters: int, body: untyped): untyped =
  measure(iters, startTime, stopTime, startClk, stopClk, body)
  report(op, bytes, startTime, stopTime, startClk, stopClk, iters)

proc benchKeccak256_constantine[T](msg: openarray[T], msgComment: string, iters: int) =
  var digest: array[32, byte]
  bench("Keccak256 - Constantine - " & msgComment, msg.len, iters):
    keccak256.hash(digest, msg)

when false:
  proc benchSHA3_256_openssl[T](msg: openarray[T], msgComment: string, iters: int) =
    var digest: array[32, byte]
    bench("SHA3-256  - OpenSSL     - " & msgComment, msg.len, iters):
      SHA3_256_OpenSSL(digest, msg)

when isMainModule:
  proc main() =
    const sizes = [
      32, 64, 128, 256,
      1024, 4096, 16384, 65536,
      1_000_000, 10_000_000
    ]

    const target_cycles = 1_000_000_000'i64
    const worst_cycles_per_bytes = 25'i64
    for s in sizes:
      let msg = rng.random_byte_seq(s)
      let iters = int(target_cycles div (s.int64 * worst_cycles_per_bytes))
      benchKeccak256_constantine(msg, $s & "B", iters)
      when false:
        benchSHA3_256_openssl(msg, $s & "B", iters)
      echo "----"

  main()
