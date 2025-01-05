import
  # Internals
  constantine/hashes,
  # Helpers
  helpers/prng_unsafe,
  ./bench_blueprint

## NOTE: For a reason that evades me at the moment, if we only `import`
## the wrapper, we get a linker error of the form:
##
## @mopenssl_wrapper.nim.c:(.text+0x110): undefined reference to `Dl_1073742356_'
## /usr/bin/ld: warning: creating DT_TEXTREL in a PIE
##
## So for the moment, we just include the wrapper.
include ../tests/openssl_wrapper

proc separator*() = separator(69)

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
      when not defined(windows): # not available on Windows in GH actions atm
        benchSHA256_openssl(msg, $s & "B", iters)

  main()
