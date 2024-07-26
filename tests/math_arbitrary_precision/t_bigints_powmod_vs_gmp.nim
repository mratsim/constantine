# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/math_arbitrary_precision/arithmetic/[bigints_views, limbs_views],
  constantine/platforms/abstractions,
  constantine/serialization/codecs,
  helpers/prng_unsafe,

  std/[times, strformat],
  gmp

const # https://gmplib.org/manual/Integer-Import-and-Export.html
  GMP_WordLittleEndian = -1'i32
  GMP_WordNativeEndian = 0'i32
  GMP_WordBigEndian = 1'i32

  GMP_MostSignificantWordFirst = 1'i32
  GMP_LeastSignificantWordFirst = -1'i32

const
  moduleName = "t_powmod_vs_gmp"
  Iters = 100

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "\n------------------------------------------------------\n"
echo moduleName, " xoshiro512** seed: ", seed

proc fromHex(T: typedesc, hex: string): T =
  result.unmarshal(array[sizeof(T), byte].fromHex(hex), WordBitWidth, bigEndian)

proc toHex(a: mpz_t): string =
  let size = mpz_sizeinbase(a, 16)
  result.setLen(size+2)

  result[0] = '0'
  result[1] = 'x'
  discard mpz_get_str(cast[cstring](result[2].addr), 16, a)

proc test(rng: var RngState) =
  let
    aLen = rng.random_unsafe(1..100)
    eLen = rng.random_unsafe(1..400)
    mLen = rng.random_unsafe(1..100)

  var
    a = newSeq[SecretWord](aLen)
    e = newSeq[byte](eLen)
    M = newSeq[SecretWord](mLen)

    rGMP = newSeq[SecretWord](mLen)
    rCtt = newSeq[SecretWord](mLen)

  for word in a.mitems():
    word = SecretWord rng.next()
  for octet in e.mitems():
    octet = byte rng.next()
  for word in M.mitems():
    word = SecretWord rng.next()

  var aa, ee, mm, rr: mpz_t
  mpz_init(aa)
  mpz_init(ee)
  mpz_init(mm)
  mpz_init(rr)

  aa.mpz_import(aLen, GMP_LeastSignificantWordFirst, sizeof(SecretWord), GMP_WordNativeEndian, 0, a[0].addr)
  ee.mpz_import(eLen, GMP_MostSignificantWordFirst, sizeof(byte), GMP_WordNativeEndian, 0, e[0].addr)
  mm.mpz_import(mLen, GMP_LeastSignificantWordFirst, sizeof(SecretWord), GMP_WordNativeEndian, 0, M[0].addr)

  rr.mpz_powm(aa, ee, mm)

  var rWritten: csize
  discard rGMP[0].addr.mpz_export(rWritten.addr, GMP_LeastSignificantWordFirst, sizeof(SecretWord), GMP_WordNativeEndian, 0, rr)

  mpz_clear(rr)
  mpz_clear(mm)
  mpz_clear(ee)
  mpz_clear(aa)

  let
    aBits = a.getBits_LE_vartime()
    eBits = e.getBits_BE_vartime()
    mBits = M.getBits_LE_vartime()

  rCtt.powMod_vartime(a, e, M, window = 4)

  doAssert (seq[BaseType])(rGMP) == (seq[BaseType])(rCtt), block:
    "\nModular exponentiation failure:\n" &
    &"  a.len (word): {a.len:>3}, a.bits: {aBits:>4}\n" &
    &"  e.len (byte): {e.len:>3}, e.bits: {eBits:>4}\n" &
    &"  M.len (word): {M.len:>3}, M.bits: {mBits:>4}\n" &
    "  ------------------------------------------------\n" &
    &"  a: {aa.toHex()}\n" &
    &"  e: {ee.toHex()}\n" &
    &"  M: {mm.toHex()}\n" &
    "  ------------------------------------------------\n" &
    &"  r (GMP): {rGMP.toString()}\n" &
    &"  r (Ctt): {rCtt.toString()}\n"


for _ in 0 ..< Iters:
  rng.test()
  stdout.write'.'
stdout.write'\n'
