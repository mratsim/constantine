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
#                                                            #
# ############################################################

func cinv[Gt](r{.noalias.}: var Gt, a{.noalias.}: Gt, ctl: SecretBool) {.inline.} =
  r.cyclotomic_inv(a)
  r.ccopy(a, not ctl)

func cinv[Gt](a: var Gt, ctl: SecretBool) {.inline.} =
  var t{.noInit.}: Gt
  t.cyclotomic_inv(a)
  a.ccopy(t, ctl)

func quot[Gt](r: var Gt, a{.noalias.}, b: Gt) {.inline.} =
  r.cyclotomic_inv(b)
  r *= a

func gtExpEndo*[Gt: ExtensionField, scalBits: static int](
       r: var Gt,
       a: Gt,
       scalar: BigInt[scalBits]) {.meter.} =
  ## Endomorphism accelerated **Variable-time** Exponentiation in 𝔾ₜ
  ##
  ##   r <- aᵏ
  ##
  ## Requires:
  ## - Cofactor to be cleared
  ## - 0 <= scalar < curve order
  static: doAssert scalBits <= Fr[Gt.Name].bits(), "Do not use endomorphism to multiply beyond the curve order"

  # 1. Compute endomorphisms
  const M = when Gt is Fp6:  2
            elif Gt is Fp12: 4
            else: {.error: "Unconfigured".}

  var endos {.noInit.}: array[M-1, Gt]
  endos.computeEndomorphisms(a)

  # 2. Decompose scalar into mini-scalars
  const L = Fr[Gt.Name].bits().computeEndoRecodedLength(M)
  var miniScalars {.noInit.}: array[M, BigInt[L]]
  var negateElems {.noInit.}: array[M, SecretBool]
  miniScalars.decomposeEndo(negateElems, scalar, Fr[Gt.Name].bits(), Gt.Name, G2) # 𝔾ₜ has same decomposition as 𝔾₂

  # 3. Handle negative mini-scalars
  # A scalar decomposition might lead to negative miniscalar.
  # For proper handling it requires either:
  # 1. Negating it and then negating the corresponding curve point P
  # 2. Adding an extra bit to L for the recoding, which will do the right thing™
  block:
    r.cinv(a, negateElems[0])
    staticFor i, 1, M:
      endos[i-1].cinv(negateElems[i])

  # 4. Precompute lookup table
  var lut {.noInit.}: array[1 shl (M-1), Gt]
  buildEndoLookupTable(
    r, endos, lut,
    groupLawAdd = prod, # 𝔾ₜ is a multiplicative subgroup
  )

  # 5. Recode the miniscalars
  #    we need the base miniscalar (that encodes the sign)
  #    to be odd, and this in constant-time to protect the secret least-significant bit.
  let k0isOdd = miniScalars[0].isOdd()
  discard miniScalars[0].cadd(One, not k0isOdd)

  var recoded: GLV_SAC[M, L] # zero-init required
  recoded.nDimMultiScalarRecoding(miniScalars)

  # 6. Proceed to GLV accelerated scalar multiplication
  var Q {.noInit.}, t {.noInit.}: Gt
  Q.secretLookup(lut, recoded.getRecodedIndex(L-1))

  for i in countdown(L-2, 0):
    Q.cyclotomic_square()
    t.secretLookup(lut, recoded.getRecodedIndex(i))
    t.cinv(SecretBool recoded.getRecodedNegate(i))
    Q *= t

  # Now we need to correct if the sign miniscalar was not odd
  r.quot(Q, r)
  r.ccopy(Q, k0isOdd)
