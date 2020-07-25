# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/[common, curves, type_bigint],
  ./bigints,
  ./finite_fields,
  ./limbs_generic,
  ./limbs_double_width

template matchingLimbs2x*(C: Curve): untyped =
  const N2 = wordsRequired(getCurveBitwidth(C)) * 2 # TODO upstream, not precomputing N2 breaks semcheck
  array[N2, SecretWord] # TODO upstream, using Limbs[N2] breaks semcheck

type FpDbl*[C: static Curve] = object
  ## Double-width Fp element
  ## This allows saving on reductions
  # We directly work with double the number of limbs
  limbs2x*: matchingLimbs2x(C)

func mul*(r: var FpDbl, a, b: Fp) {.inline.} =
  ## Store the product of ``a`` by ``b`` into ``r``
  r.limbs2x.prod(a.mres.limbs, b.mres.limbs)

func reduce*(r: var Fp, a: FpDbl) {.inline.} =
  ## Reduce a double-width field element into r
  const N = r.mres.limbs.len
  montyRed[N](r.mres.limbs, a.limbs2x, Fp.C.Mod.limbs, Fp.C.getNegInvModWord())
