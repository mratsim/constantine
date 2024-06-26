import
  constantine/math/arithmetic,
  constantine/math/io/io_bigints,
  constantine/math_arbitrary_precision/arithmetic/bigints_views,
  constantine/platforms/abstractions,
  constantine/serialization/codecs,
  helpers/prng_unsafe,
  std/[times, monotimes, strformat]

import gmp
# import stint

const # https://gmplib.org/manual/Integer-Import-and-Export.html
  GMP_WordLittleEndian = -1'i32
  GMP_WordNativeEndian = 0'i32
  GMP_WordBigEndian = 1'i32

  GMP_MostSignificantWordFirst = 1'i32
  GMP_LeastSignificantWordFirst = -1'i32

const bits = 256
const expBits = bits # Stint only supports same size args

var rng: RngState
rng.seed(1234)

for i in 0 ..< 5:
  echo "i: ", i
  # -------------------------
  let M = rng.random_long01Seq(BigInt[bits])
  let a = rng.random_long01Seq(BigInt[bits])

  var exponent = newSeq[byte](expBits div 8)
  for i in 0 ..< expBits div 8:
    exponent[i] = byte rng.next()

  # -------------------------

  let aHex = a.toHex()
  let eHex = exponent.toHex()
  let mHex = M.toHex()

  echo "  base:     ", a.toHex()
  echo "  exponent: ", exponent.toHex()
  echo "  modulus:  ", M.toHex()

  # -------------------------

  var elapsedCtt, elapsedStint, elapsedGMP: int64

  block:
    var r: BigInt[bits]
    let start = getMonotime()
    r.limbs.powMod_vartime(a.limbs, exponent, M.limbs, window = 4)
    let stop = getMonotime()

    elapsedCtt = inNanoseconds(stop-start)

    echo "  r Constantine:       ", r.toHex()
    echo "  elapsed Constantine: ", elapsedCtt, " ns"

  # -------------------------

  # block:
  #   let aa = Stuint[bits].fromHex(aHex)
  #   let ee = Stuint[expBits].fromHex(eHex)
  #   let mm = Stuint[bits].fromHex(mHex)

  #   var r: Stuint[bits]
  #   let start = getMonotime()
  #   r = powmod(aa, ee, mm)
  #   let stop = getMonotime()

  #   elapsedStint = inNanoseconds(stop-start)

  #   echo "  r stint:             ", r.toHex()
  #   echo "  elapsed Stint:       ", elapsedStint, " ns"

  block:
    var aa, ee, mm, rr: mpz_t
    mpz_init(aa)
    mpz_init(ee)
    mpz_init(mm)
    mpz_init(rr)

    aa.mpz_import(a.limbs.len, GMP_LeastSignificantWordFirst, sizeof(SecretWord), GMP_WordNativeEndian, 0, a.limbs[0].unsafeAddr)
    let e = BigInt[expBits].unmarshal(exponent, bigEndian)
    ee.mpz_import(e.limbs.len, GMP_LeastSignificantWordFirst, sizeof(SecretWord), GMP_WordNativeEndian, 0, e.limbs[0].unsafeAddr)
    mm.mpz_import(M.limbs.len, GMP_LeastSignificantWordFirst, sizeof(SecretWord), GMP_WordNativeEndian, 0, M.limbs[0].unsafeAddr)

    let start = getMonotime()
    rr.mpz_powm(aa, ee, mm)
    let stop = getMonotime()

    elapsedGMP = inNanoSeconds(stop-start)

    var r: BigInt[bits]
    var rWritten: csize
    discard r.limbs[0].addr.mpz_export(rWritten.addr, GMP_LeastSignificantWordFirst, sizeof(SecretWord), GMP_WordNativeEndian, 0, rr)

    echo "  r GMP:               ", r.toHex()
    echo "  elapsed GMP:         ", elapsedGMP, " ns"

    mpz_clear(rr)
    mpz_clear(mm)
    mpz_clear(ee)
    mpz_clear(aa)

  # echo &"\n  ratio Stint/Constantine: {float64(elapsedStint)/float64(elapsedCtt):.3f}x"
  echo &"  ratio GMP/Constantine: {float64(elapsedGMP)/float64(elapsedCtt):.3f}x"
  echo "---------------------------------------------------------"
