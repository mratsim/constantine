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
  ./lines_projective,
  ./mul_fp6_by_lines, ./mul_fp12_by_lines,
  ../curves/zoo_pairings

# ############################################################
#
#                 Basic Miller Loop
#
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
