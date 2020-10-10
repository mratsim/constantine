# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/macros,
  ../config/curves,
  ./bls12_377_frobenius,
  ./bls12_381_frobenius,
  ./bn254_nogami_frobenius,
  ./bn254_snarks_frobenius,
  ./bw6_761_frobenius

{.experimental: "dynamicBindSym".}

macro frobMapConst*(C: static Curve, coef, p_pow: static int): untyped =
  ## Access the field Frobenius map a -> a^(p^p_pow)
  ## Call with
  ## frobMapConst(Curve, coef, p_pow)
  ##
  ## With pow the
  return nnkBracketExpr.newTree(
    nnkBracketExpr.newTree(
      bindSym($C & "_FrobeniusMapCoefficients"),
      newLit(p_pow-1)
    ),
    newLit coef
  )

macro frobPsiConst*(C: static Curve, psipow, coefpow: static int): untyped =
  return bindSym($C & "_FrobeniusPsi_psi" & $psipow & "_coef" & $coefpow)
