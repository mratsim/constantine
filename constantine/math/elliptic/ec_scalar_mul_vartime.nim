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
  ./ec_twistededwards_affine,
  ./ec_twistededwards_projective,
  ./ec_shortweierstrass_batch_ops,
  ./ec_twistededwards_batch_ops,
  constantine/math/arithmetic,
  constantine/math/extension_fields,
  constantine/math/endomorphisms/split_scalars,
  constantine/math/io/io_bigints,
  constantine/platforms/abstractions,
  constantine/math_arbitrary_precision/arithmetic/limbs_views,
  constantine/named/zoo_endomorphisms,
  constantine/named/algebras

{.push raises: [].} # No exceptions allowed in core cryptographic operations
{.push checks: off.} # No defects due to array bound checking or signed integer overflow allowed

# ############################################################
#                                                            #
#                 Scalar Multiplication                      #
#                     variable-time                          #
#                                                            #
# ############################################################

iterator unpackBE(scalarByte: byte): bool =
  for i in countdown(7, 0):
    yield bool((scalarByte shr i) and 1)

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

  P.setNeutral()
  var isNeutral = true

  for scalarByte in scalarCanonical:
    for bit in unpackBE(scalarByte):
      if not isNeutral:
        P.double()
      if bit:
        if isNeutral:
          P.fromAffine(Paff)
          isNeutral = false
        else:
          P ~+= Paff

func scalarMul_addchain_5bit_vartime[EC](P: var EC, scalar: BigInt) {.tags:[VarTime], meter.} =
  ## **Variable-time** Elliptic Curve Scalar Multiplication
  ## This only handles small scalars up to 2⁵ = 32 excluded
  let s = uint scalar.limbs[0]
  case s
  of 0:
    P.setNeutral()                                     # P = [0]
  of 1:
    discard                                            # P = [1]P
  of 2:
    P.double()                                         # P = [2]P
  of 3:
    var t {.noInit.}: EC
    t.double(P)                                        # t = [2]P
    P ~+= t                                            # P = [1]P + [2]P = [3]P
  of 4:
    P.double()                                         # P = [2]P
    P.double()                                         # P = [4]P
  of 5:
    var t {.noInit.}: EC
    t.double(P)                                        # t = [2]P
    t.double()                                         # t = [4]P
    P ~+= t                                            # P = [1]P + [4]P = [5]P
  of 6:
    var t {.noInit.}: EC
    t.double(P)                                        # t = [2]P
    P ~+= t                                            # P = [1]P + [2]P = [3]P
    P.double()                                         # P = [6]P
  of 7:
    var t {.noInit.}: EC
    t.double(P)                                        # t = [2]P
    t.double()                                         # t = [4]P
    t.double()                                         # t = [8]P
    P.diff_vartime(t, P)                               # P = [8]P - [1]P = [7]P
  of 8:
    P.double()                                         # P = [2]P
    P.double()                                         # P = [4]P
    P.double()                                         # P = [8]P
  of 9:
    var t {.noInit.}: EC
    t.double(P)                                        # t = [2]P
    t.double()                                         # t = [4]P
    t.double()                                         # t = [8]P
    P ~+= t                                            # P = [1]P + [8]P = [9]P
  of 10:
    var t {.noInit.}: EC
    t.double(P)                                        # t = [2]P
    t.double()                                         # t = [4]P
    P ~+= t                                            # P = [1]P + [4]P = [5]P
    P.double()                                         # P = [10]P
  of 11:
    var t1 {.noInit.}, t2 {.noInit.}: EC
    t1.double(P)                                       # t1 = [2]P
    t2.double(t1)                                      # t2 = [4]P
    t2.double()                                        # t2 = [8]P
    t1 ~+= t2                                          # t1 = [2]P + [8]P = [10]P
    P ~+= t1                                           # P = [1]P + [10]P = [11]P
  of 12:
    var t {.noInit.}: EC
    t.double(P)                                        # t = [2]P
    t.double()                                         # t = [4]P
    P.double(t)                                        # P = [8]P
    P ~+= t                                            # P = [4]P + [8]P = [12]P
  of 13:
    var t1 {.noInit.}, t2 {.noInit.}: EC
    t1.double(P)                                       # t1 = [2]P
    t1.double()                                        # t1 = [4]P
    t2.double(t1)                                      # t2 = [8]P
    t1 ~+= t2                                          # t1 = [4]P + [8]P = [12]P
    P ~+= t1                                           # P = [1]P + [12]P = [13]P
  of 14:
    var t {.noInit.}: EC
    t.double(P)                                        # t = [2]P
    t.double()                                         # t = [4]P
    t.double()                                         # t = [8]P
    t ~-= P                                            # t = [8]P - [1]P = [7]P
    P.double(t)                                        # P = [14]P
  of 15:
    var t {.noInit.}: EC
    t.double(P)                                        # t = [2]P
    t.double()                                         # t = [4]P
    t.double()                                         # t = [8]P
    t.double()                                         # t = [16]P
    P.diff_vartime(t, P)                               # P = [16]P - [1]P = [15]P
  of 16:
    P.double()                                         # P = [2]P
    P.double()                                         # P = [4]P
    P.double()                                         # P = [8]P
    P.double()                                         # P = [16]P

  # --- 17 to 32 ---
  of 17:
    var t {.noInit.}: EC
    t.double(P)                                        # t = [2]P
    t.double()                                         # t = [4]P
    t.double()                                         # t = [8]P
    t.double()                                         # t = [16]P
    P ~+= t                                            # P = [1]P + [16]P = [17]P
  of 18:
    var t {.noInit.}: EC
    t.double(P)                                        # t = [2]P
    t.double()                                         # t = [4]P
    t.double()                                         # t = [8]P
    t ~+= P                                            # t = [1]P + [8]P = [9]P
    P.double(t)                                        # P = 2 * [9]P = [18]P
  of 19:
    var t {.noInit.}: EC
    t.double(P)                                        # t = [2]P
    t.double()                                         # t = [4]P
    t.double()                                         # t = [8]P
    t ~+= P                                            # t = [1]P + [8]P = [9]P
    t.double()                                         # t = 2 * [9]P = [18]P
    P ~+= t                                            # P = [18]P + [1]P = [19]P
  of 20:
    var t {.noInit.}: EC
    t.double(P)                                        # t = [2]P
    t.double()                                         # t = [4]P
    t ~+= P                                            # t = [1]P + [4]P = [5]P
    t.double()                                         # t = [10]P
    P.double(t)                                        # P = 2 * [10]P = [20]P
  of 21:
    var t {.noInit.}: EC
    t.double(P)                                        # t = [2]P
    t.double()                                         # t = [4]P
    t ~+= P                                            # t = [1]P + [4]P = [5]P
    t.double()                                         # t = [10]P
    t.double()                                         # t = [20]P
    P ~+= t                                            # P = [1]P + [20]P = [21]P
  of 22:
    var t {.noInit.}: EC
    t.double(P)                                        # t = [2]P
    t.double()                                         # t = [4]P
    t ~+= P                                            # t = [1]P + [4]P = [5]P
    t.double()                                         # t = [10]P
    t ~+= P                                            # t = [10]P + [1]P = [11]P
    P.double(t)                                        # P = 2 * [11]P = [22]P
  of 23:
    var t {.noInit.}: EC
    t.double(P)                                        # t = [2]P
    t ~+= P                                            # t = [1]P + [2]P = [3]P
    t.double()                                         # t = [6]P
    t.double()                                         # t = [12]P
    t.double()                                         # t = 2 * [12]P = [24]P
    P.diff_vartime(t, P)                               # P = [24]P - [1]P = [23]P
  of 24:
    var t {.noInit.}: EC
    t.double(P)                                        # t = [2]P
    t ~+= P                                            # t = [1]P + [2]P = [3]P
    t.double()                                         # t = [6]P
    t.double()                                         # t = [12]P
    P.double(t)                                        # P = 2 * [12]P = [24]P
  of 25:
    var t {.noInit.}: EC
    t.double(P)                                        # t = [2]P
    t ~+= P                                            # t = [1]P + [2]P = [3]P
    t.double()                                         # t = [6]P
    t.double()                                         # t = [12]P
    t.double()                                         # t = [24]P
    P ~+= t                                            # P = [1]P + [24]P = [25]P
  of 26:
    var t {.noInit.}: EC
    t.double(P)                                        # t = [2]P
    t ~+= P                                            # t = [1]P + [2]P = [3]P
    t.double()                                         # t = [6]P
    t.double()                                         # t = [12]P
    t ~+= P                                            # t = [12]P + [1]P = [13]P
    P.double(t)                                        # P = 2 * [13]P = [26]P
  of 27:
    var t {.noInit.}: EC
    t.double(P)                                        # t = [2]P
    t.double()                                         # t = [4]P
    t.double()                                         # t = [8]P
    t ~+= P                                            # t = [1]P + [8]P = [9]P
    P.double(t)                                        # P = 2 * [9]P = [18]P
    P ~+= t                                            # P = [18]P + [9]P = [27]P
  of 28:
    var t {.noInit.}: EC
    t.double(P)                                        # t = [2]P
    t.double()                                         # t = [4]P
    t.double()                                         # t = [8]P
    t ~-= P                                            # t = [8]P - [1]P = [7]P
    t.double()                                         # t = [14]P
    P.double(t)                                        # P = 2 * [14]P = [28]P
  of 29:
    var t {.noInit.}: EC
    t.double(P)                                        # t = [2]P
    t.double()                                         # t = [4]P
    t.double()                                         # t = [8]P
    t ~-= P                                            # t = [8]P - [1]P = [7]P
    t.double()                                         # t = [14]P
    t.double()                                         # t = [28]P
    P ~+= t                                            # P = [1]P + [28]P = [29]P
  of 30:
    var t {.noInit.}: EC
    t.double(P)                                        # t = [2]P
    P.double(t)                                        # P = [4]P
    P.double()                                         # P = [8]P
    P.double()                                         # P = [16]P
    P.double()                                         # P = [32]P
    P ~-= t                                            # P = [32]P - [2]P = [30]P
  of 31:
    var t {.noInit.}: EC
    t.double(P)                                        # t = [2]P
    t.double()                                         # t = [4]P
    t.double()                                         # t = [8]P
    t.double()                                         # t = [16]P
    t.double()                                         # t = [32]P
    P.diff_vartime(t, P)                               # P = [32]P - [1]P = [31]P
  else:
    unreachable()

func scalarMul_jy00_vartime*[EC](P: var EC, scalar: BigInt) {.tags:[VarTime].}  =
  ## **Variable-time** Elliptic Curve Scalar Multiplication
  ##
  ##   P <- [k] P
  ##
  ## This uses an online recoding with minimum Hamming Weight
  ## based on Joye, Yen, 2000 recoding.
  ##
  ## ⚠️ While the recoding is constant-time,
  ##   usage of this recoding is intended vartime
  ##   This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks
  var paff {.noinit.}: affine(EC)
  paff.affine(P)

  var npaff {.noinit.}: affine(EC)
  npaff.neg(paff)

  P.setNeutral()
  var init = false
  for bit in recoding_l2r_signed_vartime(scalar):
    if init:
      P.double()
    if bit == 1:
      if not init:
        P.fromAffine(paff)
        init = true
      else:
        P ~+= paff
    elif bit == -1:
      if not init:
        P.fromAffine(npaff)
        init = true
      else:
        P ~+= npaff

# Non-Adjacent Form (NAF) recoding
# ------------------------------------------------------------

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
    P.fromAffine(tab[-digit shr 1])
    P.neg()
    return true
  else:
    P.setNeutral()
    return false

func accumNAF[precompSize, NafMax: static int, EC, ECaff](
       P: var EC,
       tab: array[precompSize, ECaff],
       naf: array[NafMax, int8], nafLen: int,
       nafIteratorIdx: int) {.inline.} =

    let digit = naf[nafLen-1-nafIteratorIdx]
    if digit > 0:
      P ~+= tab[digit shr 1]
    elif digit < 0:
      P ~-= tab[-digit shr 1]

func scalarMul_wNAF_vartime*[EC](P: var EC, scalar: BigInt, window: static int) {.tags:[VarTime], meter.} =
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
  static: doAssert window < 8, "Window of size " & $window & " is too large and precomputation would use " & $(precompSize * sizeof(EC)) & " stack space."

  var tabEC {.noinit.}: array[precompSize, EC]
  var P2{.noInit.}: EC
  tabEC[0] = P
  P2.double(P)
  for i in 1 ..< tabEC.len:
    tabEC[i].sum_vartime(tabEC[i-1], P2)

  var tab {.noinit.}: array[precompSize, affine(EC)]
  tab.batchAffine_vartime(tabEC)

  var naf {.noInit.}: array[BigInt.bits+1, int8]
  let nafLen = naf.recode_r2l_signed_window_vartime(scalar, window)

  var isInit = false
  for i in 0 ..< nafLen:
    if isInit:
      P.double()
      P.accumNAF(tab, naf, nafLen, i)
    else:
      isInit = P.initNAF(tab, naf, nafLen, i)

func scalarMulEndo_wNAF_vartime*[scalBits: static int; EC](
       P: var EC,
       scalar: BigInt[scalBits],
       window: static int) {.tags:[VarTime], meter.} =
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
  static: doAssert window < 8, "Window of size " & $window & " is too large and precomputation would use " & $(precompSize * sizeof(EC)) & " stack space."

  # 1. Compute endomorphisms
  const M = when P.F is Fp:  2
            elif P.F is Fp2: 4
            else: {.error: "Unconfigured".}
  const G = when EC isnot EC_ShortW_Aff|EC_ShortW_Jac|EC_ShortW_Prj: G1
            else: EC.G

  var endos {.noInit.}: array[M-1, EC]
  endos.computeEndomorphisms(P)

  # 2. Decompose scalar into mini-scalars
  const L = EC.getScalarField().bits().ceilDiv_vartime(M) + 1
  var miniScalars {.noInit.}: array[M, BigInt[L]]
  var negatePoints {.noInit.}: array[M, SecretBool]
  miniScalars.decomposeEndo(negatePoints, scalar, EC.getScalarField().bits(), EC.getName(), G)

  # 3. Handle negative mini-scalars
  if negatePoints[0].bool:
    P.neg()
  for m in 1 ..< M:
    if negatePoints[m].bool:
      endos[m-1].neg()

  # 4. EC precomputed table
  var tabEC {.noinit.}: array[M, array[precompSize, EC]]
  for m in 0 ..< M:
    var P2{.noInit.}: EC
    if m == 0:
      tabEC[0][0] = P
      P2.double(P)
    else:
      tabEC[m][0] = endos[m-1]
      P2.double(endos[m-1])
    for i in 1 ..< tabEC[m].len:
      tabEC[m][i].sum_vartime(tabEC[m][i-1], P2)

  var tab {.noinit.}: array[M, array[precompSize, affine(EC)]]
  tab.batchAffine_vartime(tabEC)

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

# ############################################################
#
#                 Public API
#
# ############################################################

func scalarMul_vartime*[scalBits; EC](P: var EC, scalar: BigInt[scalBits]) {.meter.} =
  ## Elliptic Curve Scalar Multiplication
  ##
  ##   P <- [k] P
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

  when EC.getName().hasEndomorphismAcceleration():
    when scalBits >= EndomorphismThreshold: # Skip static: doAssert when multiplying by intentionally small scalars.
      if usedBits >= EndomorphismThreshold:
        when EC.F is Fp:
          P.scalarMulEndo_wNAF_vartime(scalar, window = 4)
        elif EC.F is Fp2:
          P.scalarMulEndo_wNAF_vartime(scalar, window = 3)
        else: # Curves defined on Fp^m with m > 2
          {.error: "Unreachable".}
        return

  if usedBits > 64:
    # With a window of 4, we precompute 2^4 = 4 points
    P.scalarMul_wNAF_vartime(scalar, window = 4)
  elif usedBits >= 8:
    # With a window of 3, we precompute 2^1 = 2 points
    P.scalarMul_wNAF_vartime(scalar, window = 3)
  elif usedBits > 5:
    P.scalarMul_doubleAdd_vartime(scalar)
  else: # 5-bit: [0, 32)
    P.scalarMul_addchain_5bit_vartime(scalar)

func scalarMul_vartime*[EC](P: var EC, scalar: Fr) {.inline.} =
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
  P.scalarMul_vartime(scalar.toBig())

func scalarMul_vartime*[EC](R: var EC, scalar: Fr or BigInt, P: EC) {.inline.} =
  ## Elliptic Curve Scalar Multiplication
  ##
  ##   R <- [k] P
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
  R = P
  R.scalarMul_vartime(scalar)

func scalarMul_vartime*[EC; Ecaff: not EC](R: var EC, scalar: Fr or BigInt, P: ECaff) {.inline.} =
  ## Elliptic Curve Scalar Multiplication
  ##
  ##   R <- [k] P
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
  R.fromAffine(P)
  R.scalarMul_vartime(scalar)

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

func `~*`*[EC: EC_ShortW_Jac or EC_ShortW_Prj or EC_TwEdw_Prj](
      scalar: Fr or BigInt, P: EC): EC {.noInit, inline.} =
  ## Elliptic Curve variable-time Scalar Multiplication
  ##
  ##   R <- [k] P
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.scalarMul_vartime(scalar, P)

func `~*`*[F, G](
      scalar: Fr or BigInt,
      P: EC_ShortW_Aff[F, G],
      T: typedesc[EC_ShortW_Jac[F, G] or EC_ShortW_Prj[F, G]]
      ): T {.noInit, inline.} =
  ## Elliptic Curve variable-time Scalar Multiplication
  ##
  ##   R <- [k] P
  ##
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks.
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.scalarMul_vartime(scalar, P)

func `~*`*[F, G](
      scalar: Fr or BigInt,
      P: EC_ShortW_Aff[F, G],
      ): EC_ShortW_Jac[F, G] {.noInit, inline.} =
  ## Elliptic Curve variable-time Scalar Multiplication
  ##
  ##   R <- [k] P
  ##
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks.
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.scalarMul_vartime(scalar, P)
