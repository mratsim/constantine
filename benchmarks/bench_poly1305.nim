import
  # Internals
  constantine/mac/mac_poly1305,
  # Helpers
  helpers/prng_unsafe,
  ./bench_blueprint

proc separator*() = separator(69)

# --------------------------------------------------------------------

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

proc benchPoly1305_constantine[T](msg: openarray[T], msgComment: string, iters: int) =
  var tag: array[16, byte]
  let ikm = [
      byte 0x85, 0xd6, 0xbe, 0x78, 0x57, 0x55, 0x6d, 0x33,
           0x7f, 0x44, 0x52, 0xfe, 0x42, 0xd5, 0x06, 0xa8,
           0x01, 0x03, 0x80, 0x8a, 0xfb, 0x0d, 0xb2, 0xfd,
           0x4a, 0xbf, 0xf6, 0xaf, 0x41, 0x49, 0xf5, 0x1b
    ]
  bench("Poly1305 - Constantine - " & msgComment, msg.len, iters):
    poly1305.mac(tag, msg, ikm)

when isMainModule:
  proc main() =
    block:
      let msg32B = rng.random_byte_seq(32)
      benchPoly1305_constantine(msg32B, "32B", 100)
    block:
      let msg64B = rng.random_byte_seq(64)
      benchPoly1305_constantine(msg64B, "64B", 100)
    block:
      let msg128B = rng.random_byte_seq(128)
      benchPoly1305_constantine(msg128B, "128B", 100)
    block:
      let msg576B = rng.random_byte_seq(576)
      benchPoly1305_constantine(msg576B, "576B", 50)
    block:
      let msg8192B = rng.random_byte_seq(8192)
      benchPoly1305_constantine(msg8192B, "8192B", 25)
    block:
      let msg1MB = rng.random_byte_seq(1_000_000)
      benchPoly1305_constantine(msg1MB, "1MB", 16)
    block:
      let msg10MB = rng.random_byte_seq(10_000_000)
      benchPoly1305_constantine(msg10MB, "10MB", 16)
    block:
      let msg100MB = rng.random_byte_seq(100_000_000)
      benchPoly1305_constantine(msg100MB, "100MB", 3)
  main()
