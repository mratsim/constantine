import
  constantine/math/arithmetic,
  constantine/math/io/[io_bigints, io_fields],
  constantine/named/algebras,
  constantine/platforms/abstractions,
  constantine/serialization/codecs,
  constantine/math_arbitrary_precision/arithmetic/bigints_views,
  helpers/prng_unsafe,
  ./platforms, ./bench_blueprint

import stint, gmp
from bigints import nil # force qualified import to avoid conflicts on BigInt

# Benchmarks for modular exponentiation implementations:
#
# - Constantine has 2 backends
#   - The cryptographic backend uses fixed-sized integer.
#     Often the modulus is known at compile-time (specific elliptic curves),
#     except for RSA.
#
#     This allows reducing precomputation time,
#     and unrolling all loops.
#     This is significant as incrementing a loop counter messes up carry propagation.
#
#     That backend requires the modulus to be prime.
#
#     As cryptography only uses primes (which are odd), this is not a limitation.
#     However it is not suitable for general-purpose
#
#   - The arbitrary-sized integer backend.
#     Some protocol like Ethereum modexp (EIP-198) require
#     modular exponentiation on arbitrary inputs.
#
# - Stint, GMP, nim-bigints are also benchmarked
#   for reference. GMP and nim-bigints require dynamic allocation.
#   - For GMP, we reuse buffers to limit allocation to the first benchmark
#   - nim-bigints doesn't allow reusing buffers
#
# Stint requires all inputs to be the same size
# so we use 256-bits for all.
#
# To benchmark the cryptographic backend, we use Secp256k1 (the Bitcoin curve).
# Note that Constantine implements it generically,
# due to the special form of the prime (2²⁵⁶ - 2³² - 977),
# even faster algorithms can be used.
# This gives an upper-bound

proc report(op: string, elapsedNs: int64, elapsedCycles: int64, iters: int) =
  let ns = elapsedNs div iters
  let cycles = elapsedCycles div iters
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    echo &"{op:<45} {throughput:>15.3f} ops/s {ns:>16} ns/op {cycles:>12} CPU cycles (approx)"
  else:
    echo &"{op:<45} {throughput:>15.3f} ops/s {ns:>16} ns/op"

const # https://gmplib.org/manual/Integer-Import-and-Export.html
  GMP_WordLittleEndian = -1'i32
  GMP_WordNativeEndian = 0'i32
  GMP_WordBigEndian = 1'i32

  GMP_MostSignificantWordFirst = 1'i32
  GMP_LeastSignificantWordFirst = -1'i32

const bits = 256

type BenchDesc = object
  # Hex strings
  a: string
  e: string
  M: string

proc genBench(iters: int): seq[BenchDesc] =
  for _ in 0 ..< iters:
    let a = rng.random_long01Seq(BigInt[bits])
    let e = rng.random_long01Seq(BigInt[bits])
    let M = rng.random_long01Seq(BigInt[bits])
    result.add BenchDesc(
      a: a.toHex(),
      e: e.toHex(),
      M: M.toHex())

template bench(fnCall: untyped, ticks, ns: var int64): untyped =
  block:
    let startTime = getMonotime()
    let startClock = getTicks()
    fnCall
    let stopClock = getTicks()
    let stopTime = getMonotime()

    ticks += stopClock - startClock
    ns += inNanoseconds(stopTime-startTime)

proc benchAll(desc: seq[BenchDesc]) =

  var perfCttArb, perfCttCrypto, perfGmp, perfStint, perfNimBigInt: int64

  block: # Constantine Arbitrary-precision
    var ticks, nanoseconds: int64

    for i in 0 ..< desc.len:
      # The implementation is view based and uses unowned-buffers (seq or arrays)
      # but for hex parsing simplicity we reuse BigInt buffers
      # and we directly access the array behind with .limbs
      var r:  BigInt[bits]
      let a = BigInt[bits].fromHex(desc[i].a)
      let M = BigInt[bits].fromHex(desc[i].M)
      let e = array[bits div 8, byte].fromHex(desc[i].e)

      bench(
        r.limbs.powMod_varTime(a.limbs, e, M.limbs, window = 4),
        ticks, nanoseconds)

    report("Constantine (generic arbitrary-precision)", nanoseconds, ticks, desc.len)
    perfCttArb = nanoseconds

  block: # Constantine Cryptographic backend
    var ticks, nanoseconds: int64
    var e = newSeq[byte](bits div 8)

    for i in 0 ..< desc.len:
      var r: Fp[Secp256k1]
      let a = Fp[Secp256k1].fromHex(desc[i].a)
      e.paddedFromHex(desc[i].e, bigEndian)

      bench(
        (r = a; r.pow_varTime(e)),
        ticks, nanoseconds)

    report("Constantine (crypto fixed 256-bit precision)", nanoseconds, ticks, desc.len)
    perfCttCrypto = nanoseconds

  block: # GMP
    var ticks, nanoseconds: int64
    var a, e, M, r: mpz_t
    mpz_init(a)
    mpz_init(e)
    mpz_init(M)
    mpz_init(r)

    for i in 0 ..< desc.len:
      let aCtt = BigInt[bits].fromHex(desc[i].a)
      a.mpz_import(aCtt.limbs.len, GMP_LeastSignificantWordFirst, sizeof(SecretWord), GMP_WordNativeEndian, 0, aCtt.limbs[0].unsafeAddr)
      let eCtt = BigInt[bits].fromHex(desc[i].e)
      e.mpz_import(eCtt.limbs.len, GMP_LeastSignificantWordFirst, sizeof(SecretWord), GMP_WordNativeEndian, 0, eCtt.limbs[0].unsafeAddr)
      let mCtt = BigInt[bits].fromHex(desc[i].M)
      M.mpz_import(mCtt.limbs.len, GMP_LeastSignificantWordFirst, sizeof(SecretWord), GMP_WordNativeEndian, 0, mCtt.limbs[0].unsafeAddr)

      bench(
        r.mpz_powm(a, e, M),
        ticks, nanoseconds)

    report("GMP", nanoseconds, ticks, desc.len)
    perfGMP = nanoseconds

    mpz_clear(r)
    mpz_clear(M)
    mpz_clear(e)
    mpz_clear(a)

  block: # Stint
    var ticks, nanoseconds: int64

    for i in 0 ..< desc.len:
      let a = Stuint[bits].fromHex(desc[i].a)
      let e = Stuint[bits].fromHex(desc[i].e)
      let M = Stuint[bits].fromHex(desc[i].M)

      bench(
        (let r = powmod(a, e, M)),
        ticks, nanoseconds)

    report("Stint", nanoseconds, ticks, desc.len)
    perfStint = nanoseconds

  block: # Nim bigints
    var ticks, nanoseconds: int64

    for i in 0 ..< desc.len:
      # Drop the 0x prefix
      let a = bigints.initBigInt(desc[i].a[2..^1], base = 16)
      let e = bigints.initBigInt(desc[i].e[2..^1], base = 16)
      let M = bigints.initBigInt(desc[i].M[2..^1], base = 16)

      bench(
        (let r = bigints.powmod(a, e, M)),
        ticks, nanoseconds)

    report("nim-bigints", nanoseconds, ticks, desc.len)
    perfNimBigInt = nanoseconds

  let ratioCrypto =     float64(perfCttCrypto) / float64(perfCttArb)
  let ratioGMP =        float64(perfGMP)       / float64(perfCttArb)
  let ratioStint =      float64(perfStint)     / float64(perfCttArb)
  let ratioNimBigInt =  float64(perfNimBigInt) / float64(perfCttArb)

  echo ""
  echo &"Perf ratio Constantine generic vs crypto fixed precision: {ratioCrypto:>8.3f}x"
  echo &"Perf ratio Constantine generic vs GMP:                    {ratioGMP:>8.3f}x"
  echo &"Perf ratio Constantine generic vs Stint:                  {ratioStint:>8.3f}x"
  echo &"Perf ratio Constantine generic vs nim-bigints:            {ratioNimBigInt:>8.3f}x"


when isMainModule:
  let benchDesc = genBench(100)
  benchDesc.benchAll()
