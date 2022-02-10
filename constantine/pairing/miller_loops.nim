# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_projective
  ],
  ../isogeny/frobenius,
  ./lines_projective,
  ./mul_fp6_by_lines, ./mul_fp12_by_lines

# No exceptions allowed
{.push raises: [].}

# ############################################################
#                                                            #
#                 Basic Miller Loop                          #
#                                                            #
# ############################################################

template basicMillerLoop*[FT, F1, F2](
       f: var FT,
       T: var ECP_ShortW_Prj[F2, G2],
       line: var Line[F2],
       P: ECP_ShortW_Aff[F1, G1],
       Q, nQ: ECP_ShortW_Aff[F2, G2],
       ate_param: untyped,
       ate_param_isNeg: untyped
    ) =
  ## Basic Miller loop iterations
  mixin pairing # symbol from zoo_pairings

  static:
    doAssert FT.C == F1.C
    doAssert FT.C == F2.C

  f.setOne()

  template u: untyped = pairing(C, ate_param)
  var u3 = pairing(C, ate_param)
  u3 *= 3
  for i in countdown(u3.bits - 2, 1):
    square(f)
    line_double(line, T, P)
    mul(f, line)

    let naf = bit(u3, i).int8 - bit(u, i).int8 # This can throw exception
    if naf == 1:
      line_add(line, T, Q, P)
      mul(f, line)
    elif naf == -1:
      line_add(line, T, nQ, P)
      mul(f, line)

  when pairing(C, ate_param_isNeg):
    # In GT, x^-1 == conjugate(x)
    # Remark 7.1, chapter 7.1.1 of Guide to Pairing-Based Cryptography, El Mrabet, 2017
    conj(f)

func millerCorrectionBN*[FT, F1, F2](
       f: var FT,
       T: var ECP_ShortW_Prj[F2, G2],
       Q: ECP_ShortW_Aff[F2, G2],
       P: ECP_ShortW_Aff[F1, G1],
       ate_param_isNeg: static bool
     ) =
  ## Ate pairing for BN curves need adjustment after basic Miller loop
  static:
    doAssert FT.C == F1.C
    doAssert FT.C == F2.C

  when ate_param_isNeg:
    T.neg()
  var V {.noInit.}: typeof(Q)
  var line {.noInit.}: Line[F2]

  V.frobenius_psi(Q)
  line.line_add(T, V, P)
  f.mul(line)

  V.frobenius_psi(Q, 2)
  V.neg()
  line.line_add(T, V, P)
  f.mul(line)

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
       numDoublings: static int
     ) =
  ## Start a Miller Loop with
  ## - `numDoubling` doublings
  ## - 1 add
  ##
  ## f is overwritten
  ## T is overwritten by Q
  static:
    doAssert f.c0 is Fp4
    doAssert FT.C == F1.C
    doAssert FT.C == F2.C
    doAssert numDoublings >= 1

  {.push checks: off.} # No OverflowError or IndexError allowed
  var line {.noInit.}: Line[F2]

  # First step: 0b10, T <- Q, f = 1 (mod p¹²), f *= line
  # ----------------------------------------------------
  T.fromAffine(Q)

  # f.square() -> square(1)
  line.line_double(T, P)

  # Doubling steps: 0b10...00
  # ----------------------------------------------------

  # Process all doublings, the second is special cased
  # as:
  # - The first line is squared (sparse * sparse)
  # - The second is (somewhat-sparse * sparse)
  when numDoublings >= 2:
    f.prod_sparse_sparse(line, line)
    line.line_double(T, P)
    f.mul(line)
    for _ in 2 ..< numDoublings:
      f.square()
      line.line_double(T, P)
      f.mul(line)

  # Addition step: 0b10...01
  # ------------------------------------------------

  # If there was only a single doubling needed,
  # we special case the addition as
  # - The first line and second are sparse (sparse * sparse)
  when numDoublings == 1:
    # f *= line <=> f = line for the first iteration
    var line2 {.noInit.}: Line[F2]
    line2.line_add(T, Q, P)
    f.prod_sparse_sparse(line, line2)
  else:
    line.line_add(T, Q, P)
    f.mul(line)

  {.pop.} # No OverflowError or IndexError allowed

func miller_accum_double_then_add*[FT, F1, F2](
       f: var FT,
       T: var ECP_ShortW_Prj[F2, G2],
       Q: ECP_ShortW_Aff[F2, G2],
       P: ECP_ShortW_Aff[F1, G1],
       numDoublings: int,
       add = true
     ) =
  ## Continue a Miller Loop with
  ## - `numDoubling` doublings
  ## - 1 add
  ##
  ## f and T are updated
  #
  # `numDoublings` and `add` can be hardcoded at compile-time
  # to prevent fault attacks.
  # But fault attacks only happen on embedded
  # and embedded is likely to want to minimize codesize.
  # What to do?
  {.push checks: off.} # No OverflowError or IndexError allowed

  var line {.noInit.}: Line[F2]
  for _ in 0 ..< numDoublings:
    f.square()
    line.line_double(T, P)
    f.mul(line)

  if add:
    line.line_add(T, Q, P)
    f.mul(line)

# Miller Loop - multi-pairing
# ----------------------------------------------------------------------------
#
# Multi-pairing discussion:
# Aranha & Scott proposes 2 different approaches for multi-pairing.
# See `multi_pairing.md``
# We implement Aranha approach

func double_jToN[N: static int, FT, F1, F2](
       f: var FT,
       j: static int,
       line0, line1: var Line[F2],
       Ts: var array[N, ECP_ShortW_Prj[F2, G2]],
       Ps: array[N, ECP_ShortW_Aff[F1, G1]]) =
  ## Doubling steps for pairings j to N

  {.push checks: off.} # No OverflowError or IndexError allowed
  # Sparse merge 2 by 2, starting from j
  for i in countup(j, N-1, 2):
    if i+1 >= N:
      break

    line0.line_double(Ts[i], Ps[i])
    line1.line_double(Ts[i+1], Ps[i+1])
    f.mul_3way_sparse_sparse(line0, line1)

  when (N and 1) == 1: # N >= 2 and N is odd, there is a leftover
    line0.line_double(Ts[N-1], Ps[N-1])
    f.mul(line0)

  {.pop.}

func add_jToN[N: static int, FT, F1, F2](
       f: var FT,
       j: static int,
       line0, line1: var Line[F2],
       Ts: var array[N, ECP_ShortW_Prj[F2, G2]],
       Qs: array[N, ECP_ShortW_Aff[F2, G2]],
       Ps: array[N, ECP_ShortW_Aff[F1, G1]])=
  ## Addition steps for pairings 0 to N

  {.push checks: off.} # No OverflowError or IndexError allowed
  # Sparse merge 2 by 2, starting from 0
  for i in countup(j, N-1, 2):
    if i+1 >= N:
      break

    line0.line_add(Ts[i], Qs[i], Ps[i])
    line1.line_add(Ts[i+1], Qs[i+1], Ps[i+1])
    f.mul_3way_sparse_sparse(line0, line1)

  when (N and 1) == 1: # N >= 2 and N is odd, there is a leftover
    line0.line_add(Ts[N-1], Qs[N-1], Ps[N-1])
    f.mul(line0)

  {.pop.}

func miller_init_double_then_add*[N: static int, FT, F1, F2](
       f: var FT,
       Ts: var array[N, ECP_ShortW_Prj[F2, G2]],
       Qs: array[N, ECP_ShortW_Aff[F2, G2]],
       Ps: array[N, ECP_ShortW_Aff[F1, G1]],
       numDoublings: static int
     ) =
  ## Start a Miller Loop
  ## This means
  ## - 1 doubling
  ## - 1 add
  ##
  ## f is overwritten
  ## Ts are overwritten by Qs
  static:
    doAssert f.c0 is Fp4
    doAssert FT.C == F1.C
    doAssert FT.C == F2.C

  {.push checks: off.} # No OverflowError or IndexError allowed
  var line0 {.noInit.}, line1 {.noInit.}: Line[F2]

  # First step: T <- Q, f = 1 (mod p¹²), f *= line
  # ----------------------------------------------
  for i in 0 ..< N:
    Ts[i].fromAffine(Qs[i])

  line0.line_double(Ts[0], Ps[0])
  when N >= 2:
    line1.line_double(Ts[1], Ps[1])
    f.prod_sparse_sparse(line0, line1)
    f.double_jToN(j=2, line0, line1, Ts, Ps)

  # Doubling steps: 0b10...00
  # ------------------------------------------------
  when numDoublings > 1: # Already did the MSB doubling
    when N == 1:         # f = line0
      f.prod_sparse_sparse(line0, line0) # f.square()
      line0.line_double(Ts[1], Ps[1])
      f.mul(line0)
      for _ in 2 ..< numDoublings:
        f.square()
        f.double_jtoN(j=0, line0, line1, Ts, Ps)
    else:
      for _ in 0 ..< numDoublings:
        f.square()
        f.double_jtoN(j=0, line0, line1, Ts, Ps)

  # Addition step: 0b10...01
  # ------------------------------------------------

  when numDoublings == 1 and N == 1: # f = line0
    line1.line_add(Ts[0], Qs[0], Ps[0])
    f.prod_sparse_sparse(line0, line1)
  else:
    f.add_jToN(j=0,line0, line1, Ts, Qs, Ps)

  {.pop.} # No OverflowError or IndexError allowed

func miller_accum_double_then_add*[N: static int, FT, F1, F2](
       f: var FT,
       Ts: var array[N, ECP_ShortW_Prj[F2, G2]],
       Qs: array[N, ECP_ShortW_Aff[F2, G2]],
       Ps: array[N, ECP_ShortW_Aff[F1, G1]],
       numDoublings: int,
       add = true
     ) =
  ## Continue a Miller Loop with
  ## - `numDoubling` doublings
  ## - 1 add
  ##
  ## f and T are updated
  var line0{.noInit.}, line1{.noinit.}: Line[F2]
  for _ in 0 ..< numDoublings:
    f.square()
    f.double_jtoN(j=0, line0, line1, Ts, Ps)

  if add:
    f.add_jToN(j=0, line0, line1, Ts, Qs, Ps)
