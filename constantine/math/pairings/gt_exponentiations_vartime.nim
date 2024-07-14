# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  constantine/math/elliptic/ec_endomorphism_accel,
  constantine/math/arithmetic,
  constantine/math/extension_fields,
  constantine/math/io/io_bigints,
  constantine/platforms/abstractions,
  constantine/math_arbitrary_precision/arithmetic/limbs_views,
  constantine/named/zoo_endomorphisms,
  constantine/named/algebras,
  ./cyclotomic_subgroups

{.push raises: [].} # No exceptions allowed in core cryptographic operations
{.push checks: off.} # No defects due to array bound checking or signed integer overflow allowed

iterator unpackBE(scalarByte: byte): bool =
  for i in countdown(7, 0):
    yield bool((scalarByte shr i) and 1)

func gtExp_sqrmul_vartime*[Gt: ExtensionField](r: var Gt, a: Gt, scalar: BigInt) {.tags:[VarTime], meter.} =
  ## **Variable-time** Exponentiation in Gt
  ##
  ##   r <- aᵏ
  ##
  ## This uses the square-and-multiply algorithm
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks.
  var scalarCanonical: array[scalar.bits.ceilDiv_vartime(8), byte]
  scalarCanonical.marshal(scalar, bigEndian)

  let a {.noInit.} = a # Avoid aliasing issues

  r.setOne()
  var isNeutral = true

  for scalarByte in scalarCanonical:
    for bit in unpackBE(scalarByte):
      if not isNeutral:
        r.square()
      if bit:
        if isNeutral:
          r = a
          isNeutral = false
        else:
          r *= a

func gtExp_addchain_4bit_vartime[Gt: ExtensionField](r: var Gt, a: Gt, scalar: BigInt) {.tags:[VarTime], meter.} =
  ## **Variable-time** Exponentiation in Gt
  ## This can only handle for small scalars up to 2⁴ = 16 excluded
  let s = uint scalar.limbs[0]

  case s
  of 0:
    r.setNeutral()
  of 1:
    discard
  of 2:
    r.square(a)
  of 3:
    var t {.noInit.}: Gt
    t.square(a)
    r.prod(a, t)
  of 4:
    r.square(a)
    r.square()
  of 5:
    var t {.noInit.}: Gt
    t.square(a)
    t.square()
    r.prod(a, t)
  of 6:
    var t {.noInit.}: Gt
    t.square(a)
    r.prod(a, t)
    r.square()
  of 7:
    var t {.noInit.}: Gt
    t.square(a)
    t.square()
    t.square()
    r.cyclotomic_inv(a)
    r *= t
  of 8:
    r.square(a)
    r.square()
    r.square()
  of 9:
    var t {.noInit.}: Gt
    t.square(a)
    t.square()
    t.square()
    r.prod(a, t)
  of 10:
    var t {.noInit.}: Gt
    t.square(a)
    t.square()
    r.prod(a, t)
    r.square()
  of 11:
    var t1 {.noInit.}, t2 {.noInit.}: Gt
    t1.square(a)  # [2]P
    t2.square(t1)
    t2.square()   # [8]P
    t1 *= t2
    r.prod(a, t1)
  of 12:
    var t1 {.noInit.}, t2 {.noInit.}: Gt
    t1.square(a)
    t1.square()   # [4]P
    t2.square(t1) # [8]P
    r.prod(t1, t2)
  of 13:
    var t1 {.noInit.}, t2 {.noInit.}: Gt
    t1.square(a)
    t1.square()   # [4]P
    t2.square(t1) # [8]P
    t1 *= t2
    r.prod(a, t1)
  of 14:
    var t {.noInit.}: Gt
    t.square(a)
    t.square()
    t.square()
    r.cyclotomic_inv(a)
    t *= r  # [7]P
    r.square(t)
  of 15:
    var t {.noInit.}: Gt
    t.square(a)
    t.square()
    t.square()
    t.square()
    r.cyclotomic_inv(a)
    r *= t
  else:
    unreachable()

func gtExp_minHammingWeight_vartime*[Gt: ExtensionField](r: var Gt, a: Gt, scalar: BigInt) {.tags:[VarTime].}  =
  ## **Variable-time** Exponentiation in Gt
  ##
  ##   r <- aᵏ
  ##
  ## This uses an online recoding with minimum Hamming Weight
  ## (which is not NAF, NAF is least-significant bit to most)
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks
  let a {.noInit.} = a # Avoid aliasing issues
  var na {.noInit.}: Gt
  na.cyclotomic_inv(a)

  r.setOne()
  for bit in recoding_l2r_signed_vartime(scalar):
    r.square()
    if bit == 1:
      r *= a
    elif bit == -1:
      r *= na

func initNAF[precompSize, NafMax: static int, Gt: ExtensionField](
       acc: var Gt,
       tab: array[precompSize, Gt],
       naf: array[NafMax, int8], nafLen: int,
       nafIteratorIdx: int): bool {.inline.} =

  let digit = naf[nafLen-1-nafIteratorIdx]
  if digit > 0:
    acc = tab[digit shr 1]
    return true
  elif digit < 0:
    acc.cyclotomic_inv(tab[digit shr 1])
    return true
  else:
    acc.setOne()
    return false

func accumNAF[precompSize, NafMax: static int, Gt: ExtensionField](
       acc: var Gt,
       tab: array[precompSize, Gt],
       naf: array[NafMax, int8], nafLen: int,
       nafIteratorIdx: int) {.inline.} =

    let digit = naf[nafLen-1-nafIteratorIdx]
    if digit > 0:
      acc *= tab[digit shr 1]
    elif digit < 0:
      var neg {.noInit.}: Gt
      neg.cyclotomic_inv(tab[-digit shr 1])
      acc *= neg

func gtExp_minHammingWeight_windowed_vartime*[Gt: ExtensionField](
        r: var Gt, a: Gt, scalar: BigInt, window: static int) {.tags:[VarTime], meter.} =
  ## **Variable-time** Exponentiation in Gt
  ##
  ##   r <- aᵏ
  ##
  ## This uses windowed-NAF (wNAF)
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks

  # Signed digits divides precomputation table size by 2
  # Odd-only divides precomputation table size by another 2

  const precompSize = 1 shl (window - 2)
  static: doAssert window < 8, "Window is too large and precomputation would use " & $(precompSize * sizeof(Gt)) & " stack space."

  var tab {.noinit.}: array[precompSize, Gt]
  var a2{.noInit.}: Gt
  tab[0] = a
  a2.square(a)
  for i in 1 ..< tab.len:
    tab[i].prod(tab[i-1], a2)

  var naf {.noInit.}: array[BigInt.bits+1, int8]
  let nafLen = naf.recode_r2l_signed_window_vartime(scalar, window)

  var isInit = false
  for i in 0 ..< nafLen:
    if isInit:
      r.square()
      r.accumNAF(tab, naf, nafLen, i)
    else:
      isInit = r.initNAF(tab, naf, nafLen, i)
