# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/[curves, type_ff],
  ./bigints,
  ../curves/zoo_inversions

export zoo_inversions

# ############################################################
#
#                 Finite field inversion
#
# ############################################################

# No exceptions allowed
{.push raises: [].}
{.push inline.}

func inv_euclid*(r: var FF, a: FF) =
  ## Inversion modulo p via
  ## Niels Moller constant-time version of
  ## Stein's GCD derived from extended binary Euclid algorithm
  r.mres.steinsGCD(a.mres, FF.getR2modP(), FF.fieldMod(), FF.getPrimePlus1div2())

func inv*(r: var FF, a: FF) =
  ## Inversion modulo p
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  # For now we don't activate the addition chains
  # Performance is slower than Euclid-based inversion on newer CPUs
  #
  # - Montgomery multiplication/squaring can skip the final substraction
  # - For generalized Mersenne Prime curves, modular reduction can be made extremely cheap.
  # - For BW6-761 the addition chain is over 2x slower than Euclid-based inversion
  #   due to multiplication being so costly with 12 limbs (grows quadratically)
  #   while Euclid costs grows linearly.
  when false and
       FF is Fp and FF.C.hasInversionAddchain() and
       FF.C notin {BW6_761}:
    r.inv_addchain(a)
  else:
    r.inv_euclid(a)

func inv*(a: var FF) =
  ## Inversion modulo p
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  a.inv(a)

{.pop.} # inline
{.pop.} # raises no exceptions
