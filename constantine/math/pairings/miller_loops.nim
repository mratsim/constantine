# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/curves,
  ../elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_projective
  ],
  ../arithmetic,
  ../isogenies/frobenius,
  ./lines_eval

# No exceptions allowed
{.push raises: [], checks: off.}

# ############################################################
#                                                            #
#                 Basic Miller Loop                          #
#                                                            #
# ############################################################

func recodeNafForPairing(ate: BigInt): seq[int8] {.compileTime.} =
  ## We need a NAF recoding and we need to skip the MSB for pairings
  var recoded: array[ate.bits+1, int8]
  let recodedLen = recoded.recode_r2l_signed_vartime(ate)
  var msbPos = recodedLen-1
  while true:
    if recoded[msbPos] != 0:
      break
    else:
      msbPos -= 1
      doAssert msbPos >= 0
  result = recoded[0 ..< msbPos]

func basicMillerLoop*[FT, F1, F2](
       f: var FT,
       T: var ECP_ShortW_Prj[F2, G2],
       P: ECP_ShortW_Aff[F1, G1],
       Q: ECP_ShortW_Aff[F2, G2],
       ate_param: static BigInt) =
  ## Basic Miller loop iterations
  ##
  ## Multiplications by constants in the Miller loop is eliminated by final exponentiation
  ## aka cofactor clearing in the pairing group.
  ##
  ## This means that there is no need to inverse/conjugate when `ate_param_isNeg` is false
  ## in the general case.
  ## If further processing is required, `ate_param_isNeg` must be taken into account by the caller.
  static:
    doAssert FT.C == F1.C
    doAssert FT.C == F2.C

  const naf = ate_param.recodeNafForPairing()
  var line0 {.noInit.}, line1 {.noInit.}: Line[F2]
  var nQ {.noInit.}: ECP_ShortW_Aff[F2, G2]
  f.setOne()
  nQ.neg(Q)

  block: # naf.len - 1
    line0.line_double(T, P)
    let bit = naf[naf.len-1]
    if bit == 1:
      line1.line_add(T, Q, P)
      f.prod_from_2_lines(line0, line1)
    elif bit == -1:
      line1.line_add(T, nQ, P)
      f.prod_from_2_lines(line0, line1)
    else:
      f.mul_by_line(line0)

  for i in countdown(naf.len-2, 0):
    let bit = naf[i]
    f.square()
    line0.line_double(T, P)

    if bit == 1:
      line1.line_add(T, Q, P)
      f.mul_by_2_lines(line0, line1)
    elif bit == -1:
      line1.line_add(T, nQ, P)
      f.mul_by_2_lines(line0, line1)
    else:
      f.mul_by_line(line0)

func millerCorrectionBN*[FT, F1, F2](
       f: var FT,
       T: var ECP_ShortW_Prj[F2, G2],
       Q: ECP_ShortW_Aff[F2, G2],
       P: ECP_ShortW_Aff[F1, G1]) =
  ## Ate pairing for BN curves need adjustment after basic Miller loop
  ## If `ate_param_isNeg` f must be cyclotomic inverted/conjugated
  ## and T must be negated by the caller.
  static:
    doAssert FT.C == F1.C
    doAssert FT.C == F2.C
    doAssert FT.C.family() == BarretoNaehrig

  var V {.noInit.}: typeof(Q)
  var line1 {.noInit.}, line2 {.noInit.}: Line[F2]

  V.frobenius_psi(Q)
  line1.line_add(T, V, P)

  V.frobenius_psi(Q, 2)
  V.neg()
  line2.line_add(T, V, P)

  f.mul_by_2_lines(line1, line2)

# ############################################################
#                                                            #
#                 Optimized Miller Loops                     #
#                                                            #
# ############################################################
#
# - Software Implementation, Algorithm 11.2 & 11.3
#   Aranha, Dominguez Perez, A. Mrabet, Schwabe,
#   Guide to Pairing-Based Cryptography, 2015
#
# - Physical Attacks,
#   N. El Mrabet, Goubin, Guilley, Fournier, Jauvart, Moreau, Rauzy, Rondepierre,
#   Guide to Pairing-Based Cryptography, 2015
#
# - Pairing Implementation Revisited
#   Mike Scott, 2019
#   https://eprint.iacr.org/2019/077.pdf
#
# Fault attacks:
# To limit exposure to some fault attacks (flipping bits with a laser on embedded):
# - changing the number of Miller loop iterations
# - flipping the bits in the Miller loop
# we hardcode unrolled addition chains.
# This should also contribute to performance.
#
# Miller Loop - single pairing
# ----------------------------------------------------------------------------

func miller_init_double_then_add*[FT, F1, F2](
       f: var FT,
       T: var ECP_ShortW_Prj[F2, G2],
       Q: ECP_ShortW_Aff[F2, G2],
       P: ECP_ShortW_Aff[F1, G1],
       numDoublings: static int) =
  ## Start a Miller Loop with
  ## - `numDoubling` doublings
  ## - 1 add
  ##
  ## f is overwritten
  ## T is overwritten by Q

  var line0 {.noInit.}, line1 {.noInit.}: Line[F2]
  T.fromAffine(Q)

  # First step: 0b1..., T <- Q, f = 1 (mod p¹²), f *= line
  line0.line_double(T, P)

  # Second step: 0b10 or 0b11
  # If we have more than 1 doubling, we square the line instead of squaring f
  when numDoublings >= 2:
    f.prod_from_2_lines(line0, line0)
    line0.line_double(T, P)

  # Doublings step: 0b10...0
  for _ in 2 ..< numDoublings:
    # Apply previous line0
    f.mul_by_line(line0)
    f.square()
    line0.line_double(T, P)

  # Addition step: 0b10...01
  line1.line_add(T, Q, P)
  when numDoublings == 1:
    f.prod_from_2_lines(line0, line1)
  else:
    f.mul_by_2_lines(line0, line1)

func miller_accum_double_then_add*[FT, F1, F2](
       f: var FT,
       T: var ECP_ShortW_Prj[F2, G2],
       Q: ECP_ShortW_Aff[F2, G2],
       P: ECP_ShortW_Aff[F1, G1],
       numDoublings: int, add = true) =
  ## Continue a Miller Loop with
  ## - `numDoubling` doublings
  ## - 1 add
  ##
  ## f and T are updated

  var line0 {.noInit.}, line1 {.noInit.}: Line[F2]

  f.square()
  line0.line_double(T, P)

  for _ in 1 ..< numDoublings:
    f.mul_by_line(line0)
    f.square()
    line0.line_double(T, P)

  if add:
    line1.line_add(T, Q, P)
    f.mul_by_2_lines(line0, line1)
  else:
    f.mul_by_line(line0)

# Miller Loop - multi-pairing
# ----------------------------------------------------------------------------
#
# Multi-pairing discussion:
# Aranha & Scott proposes 2 different approaches for multi-pairing.
# See `multi_pairing.md``
# We implement Aranha approach

func isOdd(n: int): bool {.inline.} = bool(n and 1)

func double_jToN[FT, F1, F2](
       f: var FT,
       j: static int,
       lineOddRemainder: var Line[F2],
       Ts: ptr UncheckedArray[ECP_ShortW_Prj[F2, G2]],
       Ps: ptr UncheckedArray[ECP_ShortW_Aff[F1, G1]],
       N: int) =
  ## Doubling steps for pairings j to N
  ## if N is odd, lineOddRemainder must be applied to `f`

  var line0{.noInit.}, line1{.noInit.}: Line[F2]
  # Sparse merge 2 by 2, starting from j
  for i in countup(j, N-2, 2):
    line0.line_double(Ts[i], Ps[i])
    line1.line_double(Ts[i+1], Ps[i+1])
    f.mul_by_2_lines(line0, line1)

  if N.isOdd(): # N >= 2 and N is odd, there is a leftover
    lineOddRemainder.line_double(Ts[N-1], Ps[N-1])

func add_jToN[FT, F1, F2](
       f: var FT,
       j: static int,
       lineOddRemainder: var Line[F2],
       Ts: ptr UncheckedArray[ECP_ShortW_Prj[F2, G2]],
       Qs: ptr UncheckedArray[ECP_ShortW_Aff[F2, G2]],
       Ps: ptr UncheckedArray[ECP_ShortW_Aff[F1, G1]],
       N: int)=
  ## Addition steps for pairings 0 to N

  var line0{.noInit.}, line1{.noInit.}: Line[F2]
  # Sparse merge 2 by 2, starting from 0
  for i in countup(j, N-2, 2):
    line0.line_add(Ts[i], Qs[i], Ps[i])
    line1.line_add(Ts[i+1], Qs[i+1], Ps[i+1])
    f.mul_by_2_lines(line0, line1)

  if N.isOdd(): # N >= 2 and N is odd, there is a leftover
    lineOddRemainder.line_add(Ts[N-1], Qs[N-1], Ps[N-1])

func add_jToN_negateQ[FT, F1, F2](
       f: var FT,
       j: static int,
       lineOddRemainder: var Line[F2],
       Ts: ptr UncheckedArray[ECP_ShortW_Prj[F2, G2]],
       Qs: ptr UncheckedArray[ECP_ShortW_Aff[F2, G2]],
       Ps: ptr UncheckedArray[ECP_ShortW_Aff[F1, G1]],
       N: int)=
  ## Addition steps for pairings 0 to N

  var nQ{.noInit.}: ECP_ShortW_Aff[F2, G2]
  var line0{.noInit.}, line1{.noInit.}: Line[F2]
  # Sparse merge 2 by 2, starting from 0
  for i in countup(j, N-2, 2):
    nQ.neg(Qs[i])
    line0.line_add(Ts[i], nQ, Ps[i])
    nQ.neg(Qs[i+1])
    line1.line_add(Ts[i+1], nQ, Ps[i+1])
    f.mul_by_2_lines(line0, line1)

  if N.isOdd(): # N >= 2 and N is odd, there is a leftover
    nQ.neg(Qs[N-1])
    lineOddRemainder.line_add(Ts[N-1], nQ, Ps[N-1])

func basicMillerLoop*[FT, F1, F2](
       f: var FT,
       Ts: ptr UncheckedArray[ECP_ShortW_Prj[F2, G2]],
       Ps: ptr UncheckedArray[ECP_ShortW_Aff[F1, G1]],
       Qs: ptr UncheckedArray[ECP_ShortW_Aff[F2, G2]],
       N: int,
       ate_param: static Bigint) =
  ## Basic Miller loop iterations
  ##
  ## Multiplications by constants in the Miller loop is eliminated by final exponentiation
  ## aka cofactor clearing in the pairing group.
  ##
  ## This means that there is no need to inverse/conjugate when `ate_param_isNeg` is false
  ## in the general case.
  ## If further processing is required, `ate_param_isNeg` must be taken into account by the caller.

  const naf = ate_param.recodeNafForPairing()
  var lineOddRemainder0{.noInit.}, lineOddRemainder1{.noinit.}: Line[F2]
  f.setOne()

  for i in countdown(naf.len-1, 0):
    let bit = naf[i]
    if i != naf.len-1:
      f.square()
    f.double_jToN(j=0, lineOddRemainder0, Ts, Ps, N)

    if bit == 1:
      f.add_jToN(j=0, lineOddRemainder1, Ts, Qs, Ps, N)
    elif bit == -1:
      f.add_jToN_negateQ(j=0, lineOddRemainder1, Ts, Qs, Ps, N)

    if N.isOdd():
      if bit == 0:
        f.mul_by_line(lineOddRemainder0)
      else:
        f.mul_by_2_lines(lineOddRemainder0, lineOddRemainder1)

func miller_init_double_then_add*[FT, F1, F2](
       f: var FT,
       Ts: ptr UncheckedArray[ECP_ShortW_Prj[F2, G2]],
       Qs: ptr UncheckedArray[ECP_ShortW_Aff[F2, G2]],
       Ps: ptr UncheckedArray[ECP_ShortW_Aff[F1, G1]],
       N: int,
       numDoublings: static int) =
  ## Start a Miller Loop
  ## This means
  ## - 1 doubling
  ## - 1 add
  ##
  ## f is overwritten
  ## Ts are overwritten by Qs

  if N == 1:
    f.miller_init_double_then_add(Ts[0], Qs[0], Ps[0], numDoublings)
    return

  var lineOddRemainder0 {.noInit.}, lineOddRemainder1 {.noInit.}: Line[F2]
  for i in 0 ..< N:
    Ts[i].fromAffine(Qs[i])

  # First step: T <- Q, f = 1 (mod p¹²), f *= line
  lineOddRemainder0.line_double(Ts[0], Ps[0])
  lineOddRemainder1.line_double(Ts[1], Ps[1])
  f.prod_from_2_lines(lineOddRemainder0, lineOddRemainder1)
  f.double_jToN(j=2, lineOddRemainder0, Ts, Ps, N)

  # Doublings step: 0b10...0
  for _ in 1 ..< numDoublings:
    if N.isOdd():
      f.mul_by_line(lineOddRemainder0)
    f.square()
    f.double_jToN(j=0, lineOddRemainder0, Ts, Ps, N)

  # Addition step: 0b10...01
  f.add_jToN(j=0, lineOddRemainder1, Ts, Qs, Ps, N)
  if N.isOdd():
    f.mul_by_2_lines(lineOddRemainder0, lineOddRemainder1)

func miller_accum_double_then_add*[FT, F1, F2](
       f: var FT,
       Ts: ptr UncheckedArray[ECP_ShortW_Prj[F2, G2]],
       Qs: ptr UncheckedArray[ECP_ShortW_Aff[F2, G2]],
       Ps: ptr UncheckedArray[ECP_ShortW_Aff[F1, G1]],
       N: int,
       numDoublings: int, add = true) =
  ## Continue a Miller Loop with
  ## - `numDoubling` doublings
  ## - 1 add
  ##
  ## f and T are updated

  if N == 1:
    f.miller_accum_double_then_add(Ts[0], Qs[0], Ps[0], numDoublings, add)
    return

  var lineOddRemainder0 {.noInit.}, lineOddRemainder1 {.noInit.}: Line[F2]

  f.square()
  f.double_jtoN(j=0, lineOddRemainder0, Ts, Ps, N)
  for _ in 1 ..< numDoublings:
    if N.isOdd():
      f.mul_by_line(lineOddRemainder0)
    f.square()
    f.double_jtoN(j=0, lineOddRemainder0, Ts, Ps, N)

  if add:
    f.add_jToN(j=0, lineOddRemainder1, Ts, Qs, Ps, N)
    if N.isOdd():
      f.mul_by_2_lines(lineOddRemainder0, lineOddRemainder1)
  else:
    if N.isOdd():
      f.mul_by_line(lineOddRemainder0)