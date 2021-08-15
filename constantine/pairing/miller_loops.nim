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

# ############################################################
#                                                            #
#                 Basic Miller Loop                          #
#                                                            #
# ############################################################

template basicMillerLoop*[FT, F1, F2](
       f: var FT,
       T: var ECP_ShortW_Prj[F2, OnTwist],
       line: var Line[F2],
       P: ECP_ShortW_Aff[F1, NotOnTwist],
       Q, nQ: ECP_ShortW_Aff[F2, OnTwist],
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
       T: var ECP_ShortW_Prj[F2, OnTwist],
       Q: ECP_ShortW_Aff[F2, OnTwist],
       P: ECP_ShortW_Aff[F1, NotOnTwist],
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
       T: var ECP_ShortW_Prj[F2, OnTwist],
       Q: ECP_ShortW_Aff[F2, OnTwist],
       P: ECP_ShortW_Aff[F1, NotOnTwist],
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
  T.projectiveFromAffine(Q)

  # f.square() -> square(1)
  line.line_double(T, P)

  # Doubling steps: 0b10...00
  # ----------------------------------------------------

  # Process all doublings, the second is special cased
  # as:
  # - The first line is squared (sparse * sparse)
  # - The second is (somewhat-sparse * sparse)
  when numDoublings >= 2:
    f.mul_sparse_sparse(line, line)
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
    # TODO: sparse * sparse
    # f *= line <=> f = line for the first iteration
    # With Fp2 -> Fp4 -> Fp12 towering and a M-Twist
    # The line corresponds to a sparse xy000z Fp12
    var line2 {.noInit.}: Line[F2]
    line2.line_add(T, Q, P)
    f.mul_sparse_sparse(line, line2)
  else:
    line.line_add(T, Q, P)
    f.mul(line)

  {.pop.} # No OverflowError or IndexError allowed

func miller_accum_double_then_add*[FT, F1, F2](
       f: var FT,
       T: var ECP_ShortW_Prj[F2, OnTwist],
       Q: ECP_ShortW_Aff[F2, OnTwist],
       P: ECP_ShortW_Aff[F1, NotOnTwist],
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

func miller_first_iter[N: static int, FT, F1, F2](
       f: var FT,
       Ts: var array[N, ECP_ShortW_Prj[F2, OnTwist]],
       Qs: array[N, ECP_ShortW_Aff[F2, OnTwist]],
       Ps: array[N, ECP_ShortW_Aff[F1, NotOnTwist]]
     ) =
  ## Start a Miller Loop
  ## This means
  ## - 1 doubling
  ## - 1 add
  ##
  ## f is overwritten
  ## Ts are overwritten by Qs
  static:
    doAssert N >= 1
    doAssert f.c0 is Fp4
    doAssert FT.C == F1.C
    doAssert FT.C == F2.C

  {.push checks: off.} # No OverflowError or IndexError allowed
  var line {.noInit.}: Line[F2]

  # First step: T <- Q, f = 1 (mod p¹²), f *= line
  # ----------------------------------------------
  for i in 0 ..< N:
    Ts[i].projectiveFromAffine(Qs[i])

  line.line_double(Ts[0], Ps[0])

  # f *= line <=> f = line for the first iteration
  # With Fp2 -> Fp4 -> Fp12 towering and a M-Twist
  # The line corresponds to a sparse xy000z Fp12
  f.c0.c0 = line.x
  f.c0.c1 = line.y
  f.c1.c0.setZero()
  f.c1.c1.setZero()
  f.c2.c0.setZero()
  f.c2.c1 = line.z

  when N >= 2:
    line.line_double(Ts[1], Ps[1])
    f.mul_sparse_by_line_xy000z(line)  # TODO: sparse-sparse mul

    # Sparse merge 2 by 2, starting from 2
    for i in countup(2, N-1, 2):
      if i+1 >= N:
        break

      # var f2 {.noInit.}: FT # TODO: sparse-sparse mul
      var line2 {.noInit.}: Line[F2]

      line.line_double(Ts[i], Ps[i])
      line2.line_double(Ts[i+1], Ps[i+1])

      # f2.mul_sparse_sparse(line, line2)
      # f.mul_somewhat_sparse(f2)
      f.mul_sparse_by_line_xy000z(line)
      f.mul_sparse_by_line_xy000z(line2)

    when (N and 1) == 1: # N >= 2 and N is odd, there is a leftover
      line.line_double(Ts[N-1], Ps[N-1])
      f.mul_sparse_by_line_xy000z(line)

  # 2nd step: Line addition as MSB is always 1
  # ----------------------------------------------
  when N >= 2: # f is dense, there are already many lines accumulated
    # Sparse merge 2 by 2, starting from 0
    for i in countup(0, N-1, 2):
      if i+1 >= N:
        break

      # var f2 {.noInit.}: FT # TODO: sparse-sparse mul
      var line2 {.noInit.}: Line[F2]

      line.line_add(Ts[i], Qs[i], Ps[i])
      line2.line_add(Ts[i+1], Qs[i+1], Ps[i+1])

      # f2.mul_sparse_sparse(line, line2)
      # f.mul_somewhat_sparse(f2)
      f.mul_sparse_by_line_xy000z(line)
      f.mul_sparse_by_line_xy000z(line2)

    when (N and 1) == 1: # N >= 2 and N is odd, there is a leftover
      line.line_add(Ts[N-1], Qs[N-1], Ps[N-1])
      f.mul_sparse_by_line_xy000z(line)

  else: # N = 1, f is sparse
    line.line_add(Ts[0], Qs[0], Ps[0])
    # f.mul_sparse_sparse(line)
    f.mul_sparse_by_line_xy000z(line)

  {.pop.} # No OverflowError or IndexError allowed

func miller_accum_doublings[N: static int, FT, F1, F2](
       f: var FT,
       Ts: var array[N, ECP_ShortW_Prj[F2, OnTwist]],
       Ps: array[N, ECP_ShortW_Aff[F1, NotOnTwist]],
       numDoublings: int
     ) =
  ## Accumulate `numDoublings` Miller loop doubling steps into `f`
  static: doAssert N >= 1
  {.push checks: off.} # No OverflowError or IndexError allowed

  var line {.noInit.}: Line[F2]

  for _ in 0 ..< numDoublings:
    f.square()
    when N >= 2:
      for i in countup(0, N-1, 2):
        if i+1 >= N:
          break

        # var f2 {.noInit.}: FT # TODO: sparse-sparse mul
        var line2 {.noInit.}: Line[F2]

        line.line_double(Ts[i], Ps[i])
        line2.line_double(Ts[i+1], Ps[i+1])

        # f2.mul_sparse_sparse(line, line2)
        # f.mul_somewhat_sparse(f2)
        f.mul_sparse_by_line_xy000z(line)
        f.mul_sparse_by_line_xy000z(line2)

      when (N and 1) == 1: # N >= 2 and N is odd, there is a leftover
        line.line_double(Ts[N-1], Ps[N-1])
        f.mul_sparse_by_line_xy000z(line)
    else:
      line.line_double(Ts[0], Ps[0])
      f.mul_sparse_by_line_xy000z(line)

  {.pop.} # No OverflowError or IndexError allowed

func miller_accum_addition[N: static int, FT, F1, F2](
       f: var FT,
       Ts: var array[N, ECP_ShortW_Prj[F2, OnTwist]],
       Qs: array[N, ECP_ShortW_Aff[F2, OnTwist]],
       Ps: array[N, ECP_ShortW_Aff[F1, NotOnTwist]]
     ) =
  ## Accumulate a Miller loop addition step into `f`
  static: doAssert N >= 1
  {.push checks: off.} # No OverflowError or IndexError allowed

  var line {.noInit.}: Line[F2]

  when N >= 2:
    # Sparse merge 2 by 2, starting from 0
    for i in countup(0, N-1, 2):
      if i+1 >= N:
        break

      # var f2 {.noInit.}: FT # TODO: sparse-sparse mul
      var line2 {.noInit.}: Line[F2]

      line.line_add(Ts[i], Qs[i], Ps[i])
      line2.line_add(Ts[i+1], Qs[i+1], Ps[i+1])

      # f2.mul_sparse_sparse(line, line2)
      # f.mul_somewhat_sparse(f2)
      f.mul_sparse_by_line_xy000z(line)
      f.mul_sparse_by_line_xy000z(line2)

    when (N and 1) == 1: # N >= 2 and N is odd, there is a leftover
      line.line_add(Ts[N-1], Qs[N-1], Ps[N-1])
      f.mul_sparse_by_line_xy000z(line)

  else:
    line.line_add(Ts[0], Qs[0], Ps[0])
    f.mul_sparse_by_line_xy000z(line)

  {.pop.} # No OverflowError or IndexError allowed

func miller_init_double_then_add*[N: static int, FT, F1, F2](
       f: var FT,
       Ts: var array[N, ECP_ShortW_Prj[F2, OnTwist]],
       Qs: array[N, ECP_ShortW_Aff[F2, OnTwist]],
       Ps: array[N, ECP_ShortW_Aff[F1, NotOnTwist]],
       numDoublings: static int
     ) =
  ## Start a Miller Loop with
  ## - `numDoubling` doublings
  ## - 1 add
  ##
  ## f is overwritten
  ## Ts is overwritten by Qs
  when numDoublings != 1:
    {.error: "Only 1 doubling is implemented at the moment".}

  f.miller_first_iter(Ts, Qs, Ps)

func miller_accum_double_then_add*[N: static int, FT, F1, F2](
       f: var FT,
       Ts: var array[N, ECP_ShortW_Prj[F2, OnTwist]],
       Qs: array[N, ECP_ShortW_Aff[F2, OnTwist]],
       Ps: array[N, ECP_ShortW_Aff[F1, NotOnTwist]],
       numDoublings: int,
       add = true
     ) =
  ## Continue a Miller Loop with
  ## - `numDoubling` doublings
  ## - 1 add
  ##
  ## f and T are updated
  f.miller_accum_doublings(Ts, Ps, numDoublings)
  if add:
    f.miller_accum_addition(Ts, Qs, Ps)
