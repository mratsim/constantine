# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
    ./platforms/abstractions,
    ./named/algebras,
    ./named/zoo_pairings,
    ./math/endomorphisms/frobenius,
    ./math/pairings/[
      cyclotomic_subgroups,
      lines_eval,
      miller_accumulators,
      pairings_generic,
      gt_exponentiations,
      gt_exponentiations_vartime]
# ############################################################
#
#       Low-level named Pairing-Friendly Curve API
#
# ############################################################

# Warning ⚠️:
#     The low-level APIs have no stability guarantee.
#     Use high-level protocols which are designed according to a stable specs
#     and with misuse resistance in mind.

{.push raises: [].} # No exceptions allowed in core cryptographic operations
{.push inline.}

# Base types
# ------------------------------------------------------------

export
  abstractions.SecretBool,
  abstractions.SecretWord,
  algebras.Algebra,
  algebras.getBigInt

# Pairings
# ------------------------------------------------------------

export frobenius.frobenius_psi

export lines_eval.Line
export lines_eval.line_double
export lines_eval.line_add
export lines_eval.mul_by_line
export lines_eval.mul_by_2_lines

export miller_accumulators.MillerAccumulator
export miller_accumulators.init
export miller_accumulators.update
export miller_accumulators.handover
export miller_accumulators.merge
export miller_accumulators.finish

export cyclotomic_subgroups.finalExpEasy
export cyclotomic_subgroups.cyclotomic_inv
export cyclotomic_subgroups.cyclotomic_square
export cyclotomic_subgroups.cycl_sqr_repeated
export cyclotomic_subgroups.cyclotomic_exp
export cyclotomic_subgroups.isInCyclotomicSubgroup

export zoo_pairings.cycl_exp_by_curve_param
export zoo_pairings.cycl_exp_by_curve_param_div2
export zoo_pairings.millerLoopAddchain
export zoo_pairings.isInPairingSubgroup

export pairings_generic.pairing
export pairings_generic.millerLoop
export pairings_generic.finalExp

export gt_exponentiations.gtExp
export gt_exponentiations_vartime.gtExp_vartime

# Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
# tend to generate useless memory moves or have difficulties to minimize stack allocation
# and our types might be large (Fp12 ...)
# See: https://github.com/mratsim/constantine/issues/145
#
# They are intended for rapid prototyping, testing and debugging.
export gt_exponentiations.`^`
export gt_exponentiations_vartime.`~^`
