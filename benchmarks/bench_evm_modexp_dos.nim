import
  ../constantine/ethereum_evm_precompiles,
  ./platforms, ./bench_blueprint,

  ../constantine/serialization/codecs

proc report(op: string, elapsedNs: int64, elapsedCycles: int64, iters: int) =
  let ns = elapsedNs div iters
  let cycles = elapsedCycles div iters
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    echo &"{op:<45} {throughput:>15.3f} ops/s {ns:>16} ns/op {cycles:>12} CPU cycles (approx)"
  else:
    echo &"{op:<45} {throughput:>15.3f} ops/s {ns:>16} ns/op"

template bench(fnCall: untyped, ticks, ns: var int64): untyped =
  block:
    let startTime = getMonotime()
    let startClock = getTicks()
    fnCall
    let stopClock = getTicks()
    let stopTime = getMonotime()

    ticks += stopClock - startClock
    ns += inNanoseconds(stopTime-startTime)

proc main() =

  let input = [
      # Length of base (32)
      (uint8)0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x20,

      # Length of exponent (32)
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x20,

      # Length of modulus (32)
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x20,

      # Base (96064778440517843452771003943013638877275214272712651271554889917016327417616)
      0xd4, 0x62, 0xbc, 0xde, 0x8f, 0x57, 0xb0, 0x4a, 0x3f, 0xe1, 0x16, 0xc8, 0x12, 0x8c, 0x44, 0x34,
      0xcf, 0x10, 0x25, 0x2e, 0x48, 0xa3, 0xcc, 0x0d, 0x28, 0xdf, 0x2b, 0xac, 0x4a, 0x8d, 0x6f, 0x10,

      # Exponent (96064778440517843452771003943013638877275214272712651271554889917016327417616)
      0xd4, 0x62, 0xbc, 0xde, 0x8f, 0x57, 0xb0, 0x4a, 0x3f, 0xe1, 0x16, 0xc8, 0x12, 0x8c, 0x44, 0x34,
      0xcf, 0x10, 0x25, 0x2e, 0x48, 0xa3, 0xcc, 0x0d, 0x28, 0xdf, 0x2b, 0xac, 0x4a, 0x8d, 0x6f, 0x10,

      # Modulus (57896044618658097711785492504343953926634992332820282019728792003956564819968)
      0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  ]

  var r = newSeq[byte](32)
  var ticks, nanoseconds: int64

  const Iters = 22058

  for i in 0 ..< Iters:
      bench(
        (let _ = r.eth_evm_modexp(input)),
        ticks, nanoseconds)

  report("EVM Modexp", nanoseconds, ticks, Iters)
  echo "Total time: ", nanoseconds.float64 / 1e6, " ms"

main()