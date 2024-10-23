# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  constantine/math/arithmetic,
  constantine/math/extension_fields,
  constantine/math/endomorphisms/split_scalars,
  constantine/math/io/io_bigints,
  constantine/platforms/abstractions,
  constantine/math_arbitrary_precision/arithmetic/limbs_views,
  constantine/named/zoo_endomorphisms,
  constantine/named/algebras,
  ./cyclotomic_subgroups

from constantine/math/elliptic/ec_shortweierstrass_affine import G2

{.push raises: [].} # No exceptions allowed in core cryptographic operations
{.push checks: off.} # No defects due to array bound checking or signed integer overflow allowed

# ############################################################
#                                                            #
#                 Exponentiation in 𝔾ₜ                       #
#                     variable-time                          #
#                                                            #
# ############################################################

iterator unpackBE(scalarByte: byte): bool =
  for i in countdown(7, 0):
    yield bool((scalarByte shr i) and 1)

func gtExp_sqrmul_vartime*[Gt: ExtensionField](r: var Gt, a: Gt, scalar: BigInt) {.tags:[VarTime], meter.} =
  ## **Variable-time** Exponentiation in 𝔾ₜ
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
        r.cyclotomic_square()
      if bit:
        if isNeutral:
          r = a
          isNeutral = false
        else:
          r *= a

func gtExp_addchain_4bit_vartime[Gt: ExtensionField](r: var Gt, a: Gt, scalar: BigInt) {.tags:[VarTime], meter.} =
  ## **Variable-time** Exponentiation in 𝔾ₜ
  ## This can only handle for small scalars up to 2⁴ = 16 excluded
  let s = uint scalar.limbs[0]

  case s
  of 0:
    r.setOne()
  of 1:
    r = a
  of 2:
    r.cyclotomic_square(a)
  of 3:
    var t {.noInit.}: Gt
    t.cyclotomic_square(a)
    r.prod(a, t)
  of 4:
    r.cyclotomic_square(a)
    r.cyclotomic_square()
  of 5:
    var t {.noInit.}: Gt
    t.cyclotomic_square(a)
    t.cyclotomic_square()
    r.prod(a, t)
  of 6:
    var t {.noInit.}: Gt
    t.cyclotomic_square(a)
    r.prod(a, t)
    r.cyclotomic_square()
  of 7:
    var t {.noInit.}: Gt
    t.cyclotomic_square(a)
    t.cyclotomic_square()
    t.cyclotomic_square()
    r.cyclotomic_inv(a)
    r *= t
  of 8:
    r.cyclotomic_square(a)
    r.cyclotomic_square()
    r.cyclotomic_square()
  of 9:
    var t {.noInit.}: Gt
    t.cyclotomic_square(a)
    t.cyclotomic_square()
    t.cyclotomic_square()
    r.prod(a, t)
  of 10:
    var t {.noInit.}: Gt
    t.cyclotomic_square(a)
    t.cyclotomic_square()
    r.prod(a, t)
    r.cyclotomic_square()
  of 11:
    var t1 {.noInit.}, t2 {.noInit.}: Gt
    t1.cyclotomic_square(a)  # [2]P
    t2.cyclotomic_square(t1)
    t2.cyclotomic_square()   # [8]P
    t1 *= t2
    r.prod(a, t1)
  of 12:
    var t1 {.noInit.}, t2 {.noInit.}: Gt
    t1.cyclotomic_square(a)
    t1.cyclotomic_square()   # [4]P
    t2.cyclotomic_square(t1) # [8]P
    r.prod(t1, t2)
  of 13:
    var t1 {.noInit.}, t2 {.noInit.}: Gt
    t1.cyclotomic_square(a)
    t1.cyclotomic_square()   # [4]P
    t2.cyclotomic_square(t1) # [8]P
    t1 *= t2
    r.prod(a, t1)
  of 14:
    var t {.noInit.}: Gt
    t.cyclotomic_square(a)
    t.cyclotomic_square()
    t.cyclotomic_square()
    r.cyclotomic_inv(a)
    t *= r  # [7]P
    r.cyclotomic_square(t)
  of 15:
    var t {.noInit.}: Gt
    t.cyclotomic_square(a)
    t.cyclotomic_square()
    t.cyclotomic_square()
    t.cyclotomic_square()
    r.cyclotomic_inv(a)
    r *= t
  else:
    unreachable()

func gtExp_jy00_vartime*[Gt: ExtensionField](r: var Gt, a: Gt, scalar: BigInt) {.tags:[VarTime].}  =
  ## **Variable-time** Exponentiation in 𝔾ₜ
  ##
  ##   r <- aᵏ
  ##
  ## This uses an online recoding with minimum Hamming Weight
  ## bassed on Joye, Yen, 2000 recoding.
  ##
  ## ⚠️ While the recoding is constant-time,
  ##   usage of this recoding is intended vartime
  ##   This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks
  let a {.noInit.} = a # Avoid aliasing issues
  var na {.noInit.}: Gt
  na.cyclotomic_inv(a)

  r.setOne()
  for bit in recoding_l2r_signed_vartime(scalar):
    r.cyclotomic_square()
    if bit == 1:
      r *= a
    elif bit == -1:
      r *= na

# Non-Adjacent Form (NAF) recoding
# ------------------------------------------------------------

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

func gtExp_wNAF_vartime*[Gt: ExtensionField](
        r: var Gt, a: Gt, scalar: BigInt, window: static int) {.tags:[VarTime], meter.} =
  ## **Variable-time** Exponentiation in 𝔾ₜ
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
  static: doAssert window <= 4, "Window of size " & $window & " is too large and precomputation would use " & $(precompSize * sizeof(Gt)) & " stack space."

  var tab {.noinit.}: array[precompSize, Gt]
  var a2{.noInit.}: Gt
  tab[0] = a
  a2.cyclotomic_square(a)
  for i in 1 ..< tab.len:
    tab[i].prod(tab[i-1], a2)

  var naf {.noInit.}: array[BigInt.bits+1, int8]
  let nafLen = naf.recode_r2l_signed_window_vartime(scalar, window)

  var isInit = false
  for i in 0 ..< nafLen:
    if isInit:
      r.cyclotomic_square()
      r.accumNAF(tab, naf, nafLen, i)
    else:
      isInit = r.initNAF(tab, naf, nafLen, i)

func gtExpEndo_wNAF_vartime*[Gt: ExtensionField, scalBits: static int](
        r: var Gt, a: Gt, scalar: BigInt[scalBits], window: static int) {.tags:[VarTime], meter.} =
  ## Endomorphism accelerated **Variable-time** Exponentiation in 𝔾ₜ
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
  static: doAssert window <= 4, "Window of size " & $window & " is too large and precomputation would use " & $(precompSize * sizeof(Gt)) & " stack space."

  # 1. Compute endomorphisms
  const M = when Gt.Name.getEmbeddingDegree() == 6:  2
            elif Gt.Name.getEmbeddingDegree() == 12: 4
            else: {.error: "Unconfigured".}

  var endos {.noInit.}: array[M-1, Gt]
  endos.computeEndomorphisms(a)

  # 2. Decompose scalar into mini-scalars
  const L = Fr[Gt.Name].bits().computeEndoRecodedLength(M)
  var miniScalars {.noInit.}: array[M, BigInt[L]]
  var negateElems {.noInit.}: array[M, SecretBool]
  miniScalars.decomposeEndo(negateElems, scalar, Fr[Gt.Name].bits(), Gt.Name, G2) # 𝔾ₜ has same decomposition as 𝔾₂

  # 3. Handle negative mini-scalars
  if negateElems[0].bool:
    r.cyclotomic_inv(a)
  else:
    r = a
  for m in 1 ..< M:
    if negateElems[m].bool:
      endos[m-1].cyclotomic_inv()

  # It's OK if r aliases a, we don't need a anymore

  # 4. Precomputed table
  var tab {.noinit.}: array[M, array[precompSize, Gt]]
  for m in 0 ..< M:
    var a2{.noInit.}: Gt
    if m == 0:
      tab[0][0] = r
      a2.cyclotomic_square(r)
    else:
      tab[m][0] = endos[m-1]
      a2.cyclotomic_square(endos[m-1])
    for i in 1 ..< tab[m].len:
      tab[m][i].prod(tab[m][i-1], a2)

  # 5. wNAF precomputed tables
  const NafLen = L+1
  var tabNaf {.noinit.}: array[M, array[NafLen, int8]]

  for m in 0 ..< M:
    # tabNaf returns NAF from least-significant to most significant bits
    let miniScalarLen = tabNaf[m].recode_r2l_signed_window_vartime(miniScalars[m], window)
    # We compute from most significant to least significant
    # so we pad with 0
    for i in miniScalarLen ..< NafLen:
      tabNaf[m][i] = 0

  # 6. Compute
  var isInit = false

  for i in 0 ..< NafLen:
    if isInit:
      r.cyclotomic_square()
    for m in 0 ..< M:
      if isInit:
        r.accumNAF(tab[m], tabNaf[m], NafLen, i)
      else:
        isInit = r.initNAF(tab[m], tabNaf[m], NafLen, i)

# ############################################################
#
#                 Public API
#
# ############################################################

func gtExp_vartime*[Gt: ExtensionField, scalBits: static int](
      r: var Gt, a: Gt, scalar: BigInt[scalBits]) {.tags:[VarTime], meter.} =
  ## Exponentiation in 𝔾ₜ
  ##
  ##   r <- aᵏ
  ##
  ## This selects the best algorithm depending on heuristics
  ## and the scalar being multiplied.
  ## The scalar MUST NOT be a secret as this does not use side-channel countermeasures
  ##
  ## This may use endomorphism acceleration.
  ## As endomorphism acceleration requires:
  ## - Cofactor to be cleared
  ## - 0 <= scalar < curve order
  ## Those conditions will be assumed.

  let usedBits = scalar.limbs.getBits_LE_vartime()

  when Gt.Name.hasEndomorphismAcceleration():
    when scalBits >= EndomorphismThreshold: # Skip static: doAssert when multiplying by intentionally small scalars.
      if usedBits >= EndomorphismThreshold:
        when Gt.Name.getEmbeddingDegree() == 6:
          r.gtExpEndo_wNAF_vartime(a, scalar, window = 4)
        elif Gt.Name.getEmbeddingDegree() == 12:
          r.gtExpEndo_wNAF_vartime(a, scalar, window = 3)
        else: # Curves defined on Fp^m with m > 2
          {.error: "Unconfigured".}
        return

  if 64 < usedBits:
    # With a window of 4, we precompute 2^4 = 4 elements
    r.gtExp_wNAF_vartime(a, scalar, window = 4)
  elif 16 < usedBits:
    # With a window of 3, we precompute 2^1 = 2 elements
    r.gtExp_wNAF_vartime(a, scalar, window = 3)
  elif 4 < usedBits:
    r.gtExp_jy00_vartime(a, scalar)
  else:
    r.gtExp_addchain_4bit_vartime(a, scalar)

func gtExp_vartime*[Gt](r: var Gt, a: Gt, scalar: Fr) {.inline.} =
  ## Exponentiation in 𝔾ₜ
  ##
  ##   r <- aᵏ
  ##
  ## This select the best algorithm depending on heuristics
  ## and the scalar being multiplied.
  ## The scalar MUST NOT be a secret as this does not use side-channel countermeasures
  r.gtExp_vartime(a, scalar.toBig())

func gtExp_vartime*[Gt](a: var Gt, scalar: Fr or BigInt) {.inline.} =
  ## Exponentiation in 𝔾ₜ
  ##
  ##   r <- aᵏ
  ##
  ## This selects the best algorithm depending on heuristics
  ## and the scalar being multiplied.
  ## The scalar MUST NOT be a secret as this does not use side-channel countermeasures
  ##
  ## This may use endomorphism acceleration.
  ## As endomorphism acceleration requires:
  ## - Cofactor to be cleared
  ## - 0 <= scalar < curve order
  ## Those conditions will be assumed.
  a.gtExp_vartime(a, scalar)

# ############################################################
#
#                 Out-of-Place functions
#
# ############################################################
#
# Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
# tend to generate useless memory moves or have difficulties to minimize stack allocation
# and our types might be large (Fp12 ...)
# See: https://github.com/mratsim/constantine/issues/145

func `~^`*[Gt: ExtensionField](a: Gt, scalar: Fr or BigInt): Gt {.noInit, inline.} =
  ## Elliptic Curve variable-time Scalar Multiplication
  ##
  ##   r <- aᵏ
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.gtExp_vartime(a, scalar)
