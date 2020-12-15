import
  # Internals
  ../constantine/hashes/h_sha256,
  # Helpers
  ../helpers/prng_unsafe,
  ./bench_blueprint

proc separator*() = separator(69)

proc SHA256[T: byte|char](
       msg: openarray[T],
       digest: ptr array[32, byte] = nil
     ): ptr array[32, byte] {.cdecl, dynlib: "libssl.so", importc.}

proc SHA256_OpenSSL[T: byte|char](
       digest: var array[32, byte],
       s: openarray[T]) =
  discard SHA256(s, digest.addr)

proc report(op: string, bytes: int, startTime, stopTime: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stopTime-startTime) div iters)
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    let cycles = (stopClk - startClk) div iters
    let cyclePerByte = cycles.float64 / bytes.float64
    echo &"{op:<30}     {throughput:>15.3f} ops/s    {ns:>9} ns/op    {cycles:>10} cycles    {cyclePerByte:>5.2f} cycles/byte"
  else:
    echo &"{op:<30}     {throughput:>15.3f} ops/s    {ns:>9} ns/op"

template bench(op: string, bytes: int, iters: int, body: untyped): untyped =
  measure(iters, startTime, stopTime, startClk, stopClk, body)
  report(op, bytes, startTime, stopTime, startClk, stopClk, iters)

proc benchSHA256_constantine[T](msg: openarray[T], msgComment: string, iters: int) =
  var digest: array[32, byte]
  bench("SHA256 - Constantine - " & msgComment, msg.len, iters):
    sha256.hash(digest, msg)

proc benchSHA256_openssl[T](msg: openarray[T], msgComment: string, iters: int) =
  var digest: array[32, byte]
  bench("SHA256 - OpenSSL - " & msgComment, msg.len, iters):
    SHA256_OpenSSL(digest, msg)

when isMainModule:
  proc main() =
    block:
      let msg128B = rng.random_byte_seq(128)
      benchSHA256_constantine(msg128B, "128B", 128)
      benchSHA256_openssl(msg128B, "128B", 128)
    block:
      let msg5MB = rng.random_byte_seq(5_000_000)
      benchSHA256_constantine(msg5MB, "5MB", 16)
      benchSHA256_openssl(msg5MB, "5MB", 16)
    block:
      let msg100MB = rng.random_byte_seq(100_000_000)
      benchSHA256_constantine(msg100MB, "100MB", 3)
      benchSHA256_openssl(msg100MB, "100MB", 3)
  main()
