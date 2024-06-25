import
  # Internals
  constantine/hashes,
  # Helpers
  helpers/prng_unsafe,
  ./bench_blueprint

proc separator*() = separator(69)

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

proc SHA256[T: byte|char](
       msg: openarray[T],
       digest: ptr array[32, byte] = nil
     ): ptr array[32, byte] {.noconv, dynlib: DLLSSLName, importc.}

proc SHA256_OpenSSL[T: byte|char](
       digest: var array[32, byte],
       s: openarray[T]) =
  discard SHA256(s, digest.addr)

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

proc benchSHA256_constantine[T](msg: openarray[T], msgComment: string, iters: int) =
  var digest: array[32, byte]
  bench("SHA256 - Constantine - " & msgComment, msg.len, iters):
    sha256.hash(digest, msg)

proc benchSHA256_openssl[T](msg: openarray[T], msgComment: string, iters: int) =
  var digest: array[32, byte]
  bench("SHA256 - OpenSSL     - " & msgComment, msg.len, iters):
    SHA256_OpenSSL(digest, msg)

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
      benchSHA256_constantine(msg, $s & "B", iters)
      benchSHA256_openssl(msg, $s & "B", iters)

  main()
