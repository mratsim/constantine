# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ./ec_shortweierstrass_affine,
  ./ec_shortweierstrass_jacobian,
  ./ec_shortweierstrass_projective,
  ./ec_endomorphism_accel,
  ./ec_shortweierstrass_batch_ops,
  ../arithmetic,
  ../extension_fields,
  ../io/io_bigints,
  ../constants/zoo_endomorphisms,
  ../isogenies/frobenius,
  ../../platforms/abstractions,
  ../../math_arbitrary_precision/arithmetic/limbs_views

{.push raises: [].} # No exceptions allowed in core cryptographic operations
{.push checks: off.} # No defects due to array bound checking or signed integer overflow allowed

# Bit operations
# ------------------------------------------------------------------------------

iterator unpackBE(scalarByte: byte): bool =
  for i in countdown(7, 0):
    yield bool((scalarByte shr i) and 1)

# Variable-time scalar multiplication
# ------------------------------------------------------------------------------
template `+=`[F; G: static Subgroup](P: var (ECP_ShortW_Jac[F, G] or ECP_ShortW_Prj[F, G]), Q: ECP_ShortW_Aff[F, G]) =
  P.madd_vartime(P, Q)
template `-=`[F; G: static Subgroup](P: var (ECP_ShortW_Jac[F, G] or ECP_ShortW_Prj[F, G]), Q: ECP_ShortW_Aff[F, G]) =
  P.msub_vartime(P, Q)

func scalarMul_doubleAdd_vartime*[EC](P: var EC, scalar: BigInt) {.tags:[VarTime], meter.} =
  ## **Variable-time** Elliptic Curve Scalar Multiplication
  ##
  ##   P <- [k] P
  ##
  ## This uses the double-and-add algorithm
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks.
  var scalarCanonical: array[scalar.bits.ceilDiv_vartime(8), byte]
  scalarCanonical.marshal(scalar, bigEndian)

  var Paff {.noinit.}: affine(EC)
  Paff.affine(P)

  P.setInf()
  var isInf = true

  for scalarByte in scalarCanonical:
    for bit in unpackBE(scalarByte):
      if not isInf:
        P.double()
      if bit:
        if isInf:
          P.fromAffine(Paff)
          isInf = false
        else:
          P += Paff

func scalarMul_addchain_4bit_vartime[EC](P: var EC, scalar: BigInt) {.tags:[VarTime], meter.} =
  ## **Variable-time** Elliptic Curve Scalar Multiplication
  ## This can only handle for small scalars up to 2⁴ = 16 excluded
  let s = uint scalar.limbs[0]

  case s
  of 0:
    P.setInf()
  of 1:
    return
  of 2:
    P.double()
  of 3:
    var t {.noInit.}: EC
    t.double(P)
    P.sum_vartime(P, t)
  of 4:
    P.double()
    P.double()
  of 5:
    var t {.noInit.}: EC
    t.double(P)
    t.double(P)
    P.sum_vartime(P, t)
  of 6:
    var t {.noInit.}: EC
    t.double(P)
    P.sum_vartime(P, t)
    P.double()
  of 7:
    var t {.noInit.}: EC
    t.double(P)
    t.double()
    t.double()
    P.diff_vartime(t, P)
  of 8:
    P.double()
    P.double()
    P.double()
  of 9:
    var t {.noInit.}: EC
    t.double(P)
    t.double()
    t.double()
    P.sum_vartime(P, t)
  of 10:
    var t {.noInit.}: EC
    t.double(P)
    t.double()
    P.sum_vartime(P, t)
    P.double()
  of 11:
    var t1 {.noInit.}, t2 {.noInit.}: EC
    t1.double(P)  # [2]P
    t2.double(t1)
    t2.double()   # [8]P
    t1.sum_vartime(t1, t2)
    P.sum_vartime(P, t1)
  of 12:
    var t1 {.noInit.}, t2 {.noInit.}: EC
    t1.double(P)
    t1.double()   # [4]P
    t2.double(t1) # [8]P
    P.sum_vartime(t1, t2)
  of 13:
    var t1 {.noInit.}, t2 {.noInit.}: EC
    t1.double(P)
    t1.double()   # [4]P
    t2.double(t1) # [8]P
    t1.sum_vartime(t1, t2)
    P.sum_vartime(P, t1)
  of 14:
    var t {.noInit.}: EC
    t.double(P)
    t.double()
    t.double()
    t.diff_vartime(t, P) # [7]P
    P.double(t)
  of 15:
    var t {.noInit.}: EC
    t.double(P)
    t.double()
    t.double()
    t.double()
    P.diff_vartime(t, P)
  else:
    unreachable()

func scalarMul_minHammingWeight_vartime*[EC](P: var EC, scalar: BigInt) {.tags:[VarTime].}  =
  ## **Variable-time** Elliptic Curve Scalar Multiplication
  ##
  ##   P <- [k] P
  ##
  ## This uses an online recoding with minimum Hamming Weight
  ## (which is not NAF, NAF is least-significant bit to most)
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks
  var Paff {.noinit.}: affine(EC)
  Paff.affine(P)

  P.setInf()
  for bit in recoding_l2r_signed_vartime(scalar):
    P.double()
    if bit == 1:
      P += Paff
    elif bit == -1:
      P -= Paff

func initNAF[precompSize, NafMax: static int, EC, ECaff](
       P: var EC,
       tab: array[precompSize, ECaff],
       naf: array[NafMax, int8], nafLen: int,
       nafIteratorIdx: int): bool {.inline.} =

  let digit = naf[nafLen-1-nafIteratorIdx]
  if digit > 0:
    P.fromAffine(tab[digit shr 1])
    return true
  elif digit < 0:
    P.fromAffine(tab[digit shr 1])
    P.neg()
    return true
  else:
    P.setInf()
    return false

func accumNAF[precompSize, NafMax: static int, EC, ECaff](
       P: var EC,
       tab: array[precompSize, ECaff],
       naf: array[NafMax, int8], nafLen: int,
       nafIteratorIdx: int) {.inline.} =

    let digit = naf[nafLen-1-nafIteratorIdx]
    if digit > 0:
      P += tab[digit shr 1]
    elif digit < 0:
      P -= tab[-digit shr 1]

func scalarMul_minHammingWeight_windowed_vartime*[EC](P: var EC, scalar: BigInt, window: static int) {.tags:[VarTime, Alloca], meter.} =
  ## **Variable-time** Elliptic Curve Scalar Multiplication
  ##
  ##   P <- [k] P
  ##
  ## This uses windowed-NAF (wNAF)
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks

  # Signed digits divides precomputation table size by 2
  # Odd-only divides precomputation table size by another 2

  const precompSize = 1 shl (window - 2)
  static: doAssert window < 8, "Window is too large and precomputation would use " & $(precompSize * sizeof(EC)) & " stack space."

  var tabEC {.noinit.}: array[precompSize, EC]
  var P2{.noInit.}: EC
  tabEC[0] = P
  P2.double(P)
  for i in 1 ..< tabEC.len:
    tabEC[i].sum_vartime(tabEC[i-1], P2)

  var tab {.noinit.}: array[precompSize, affine(EC)]
  tab.batchAffine(tabEC)

  var naf {.noInit.}: array[BigInt.bits+1, int8]
  let nafLen = naf.recode_r2l_signed_window_vartime(scalar, window)

  var isInit = false
  for i in 0 ..< nafLen:
    if isInit:
      P.double()
      P.accumNAF(tab, naf, nafLen, i)
    else:
      isInit = P.initNAF(tab, naf, nafLen, i)

func scalarMulEndo_minHammingWeight_windowed_vartime*[scalBits: static int; EC](
       P: var EC,
       scalar: BigInt[scalBits],
       window: static int) {.tags:[VarTime, Alloca], meter.} =
  ## Endomorphism-accelerated windowed vartime scalar multiplication
  ##
  ##   P <- [k] P
  ##
  ## This uses windowed-NAF (wNAF)
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks

  # Signed digits divides precomputation table size by 2
  # Odd-only divides precomputation table size by another 2
  const precompSize = 1 shl (window - 2)
  static: doAssert window < 8, "Window is too large and precomputation would use " & $(precompSize * sizeof(EC)) & " stack space."

  when P.F is Fp:
    const M = 2
    # 1. Compute endomorphisms
    var endomorphisms {.noInit.}: array[M-1, EC]
    when P.G == G1:
      endomorphisms[0] = P
      endomorphisms[0].x *= EC.F.C.getCubicRootOfUnity_mod_p()
    else:
      endomorphisms[0].frobenius_psi(P, 2)

  elif P.F is Fp2:
    const M = 4
    # 1. Compute endomorphisms
    var endomorphisms {.noInit.}: array[M-1, EC]
    endomorphisms[0].frobenius_psi(P)
    endomorphisms[1].frobenius_psi(P, 2)
    endomorphisms[2].frobenius_psi(P, 3)
  else:
    {.error: "Unconfigured".}

  # 2. Decompose scalar into mini-scalars
  const L = scalBits.ceilDiv_vartime(M) + 1
  var miniScalars {.noInit.}: array[M, BigInt[L]]
  var negatePoints {.noInit.}: array[M, SecretBool]
  miniScalars.decomposeEndo(negatePoints, scalar, EC.F)

  # 3. Handle negative mini-scalars
  if negatePoints[0].bool:
    P.neg()
  for m in 1 ..< M:
    if negatePoints[m].bool:
      endomorphisms[m-1].neg()

  # 4. EC precomputed table
  var tabEC {.noinit.}: array[M, array[precompSize, EC]]
  for m in 0 ..< M:
    var P2{.noInit.}: EC
    if m == 0:
      tabEC[0][0] = P
      P2.double(P)
    else:
      tabEC[m][0] = endomorphisms[m-1]
      P2.double(endomorphisms[m-1])
    for i in 1 ..< tabEC[m].len:
      tabEC[m][i].sum_vartime(tabEC[m][i-1], P2)

  var tab {.noinit.}: array[M, array[precompSize, affine(EC)]]
  tab.batchAffine(tabEC)

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
      P.double()
    for m in 0 ..< M:
      if isInit:
        P.accumNAF(tab[m], tabNaf[m], NafLen, i)
      else:
        isInit = P.initNAF(tab[m], tabNaf[m], NafLen, i)

func scalarMul_vartime*[scalBits; EC](
       P: var EC,
       scalar: BigInt[scalBits]
     ) =
  ## Elliptic Curve Scalar Multiplication
  ##
  ##   P <- [k] P
  ##
  ## This select the best algorithm depending on heuristics
  ## and the scalar being multiplied.
  ## The scalar MUST NOT be a secret as this does not use side-channel countermeasures
  ##
  ## This may use endomorphism acceleration.
  ## As endomorphism acceleration requires:
  ## - Cofactor to be cleared
  ## - 0 <= scalar < curve order
  ## Those conditions will be assumed.

  when P.F is Fp:
    const M = 2
  elif P.F is Fp2:
    const M = 4
  else:
    {.error: "Unconfigured".}

  const L = scalBits.ceilDiv_vartime(M) + 1

  let usedBits = scalar.limbs.getBits_LE_vartime()

  when scalBits == EC.F.C.getCurveOrderBitwidth() and
       EC.F.C.hasEndomorphismAcceleration():
    if usedBits >= L:
      when EC.F is Fp:
        P.scalarMulEndo_minHammingWeight_windowed_vartime(scalar, window = 4)
      elif EC.F is Fp2:
        P.scalarMulEndo_minHammingWeight_windowed_vartime(scalar, window = 3)
      else: # Curves defined on Fp^m with m > 2
        {.error: "Unreachable".}
      return

  if 64 < usedBits:
    # With a window of 5, we precompute 2^3 = 8 points
    P.scalarMul_minHammingWeight_windowed_vartime(scalar, window = 5)
  elif 16 < usedBits:
    # With a window of 3, we precompute 2^1 = 2 points
    P.scalarMul_minHammingWeight_windowed_vartime(scalar, window = 3)
  elif 4 < usedBits:
    P.scalarMul_doubleAdd_vartime(scalar)
  else:
    P.scalarMul_addchain_4bit_vartime(scalar)