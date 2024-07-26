#!/usr/bin/sage
# vim: syntax=python
# vim: set ts=2 sw=2 et:

# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                      Pairing constants
#
# ############################################################

# Imports
# ---------------------------------------------------------

import os
import inspect, textwrap

# Working directory
# ---------------------------------------------------------

os.chdir(os.path.dirname(__file__))

# Sage imports
# ---------------------------------------------------------
# Accelerate arithmetic by accepting probabilistic proofs
from sage.structure.proof.all import arithmetic
arithmetic(False)

load('curves.sage')

# Utilities
# ---------------------------------------------------------

# Code generators
# ---------------------------------------------------------

def genAteParam(curve_name, curve_config):
  u = curve_config[curve_name]['field']['param']
  family = curve_config[curve_name]['field']['family']
  if family == 'BLS12':
    ate_param = u
    ate_comment = '  # BLS12 Miller loop is parametrized by u\n'
  elif family == 'BN':
    ate_param = 6*u+2
    ate_comment = '  # BN Miller loop is parametrized by 6u+2\n'
  elif family == 'BW6':
    result = genAteParam_BW6_unoptimized(curve_name, curve_config)
    result += '\n\n'
    result += genAteParam_BW6_opt(curve_name, curve_config)
    return result
  else:
    raise ValueError(f'family: {family} is not implemented')

  buf = '# The bit count must be exact for the Miller loop\n'
  buf += f'const {curve_name}_pairing_ate_param* = block:\n'
  buf += ate_comment

  ate_bits = int(ate_param).bit_length()
  buf += f'  BigInt[{ate_bits}].fromHex"0x{Integer(abs(ate_param)).hex()}"\n\n'

  buf += f'const {curve_name}_pairing_ate_param_isNeg* = {"true" if ate_param < 0 else "false"}'

  return buf

def genAteParam_BW6_unoptimized(curve_name, curve_config):
  u = curve_config[curve_name]['field']['param']
  family = curve_config[curve_name]['field']['family']
  assert family == 'BW6'

  # Algorithm 5 - https://eprint.iacr.org/2020/351.pdf
  ate_param = u+1
  ate_param_2 = u*(u^2 - u - 1)

  ate_comment = '  # BW6-761 unoptimized Miller loop first part is parametrized by u+1\n'
  ate_comment_2 = '  # BW6 unoptimized Miller loop second part is parametrized by u*(u²-u-1)\n'

  # Note we can use the fact that
  #  f_{u+1,Q}(P) = f_{u,Q}(P) . l_{[u]Q,Q}(P)
  #  f_{u³-u²-u,Q}(P) = f_{u (u²-u-1),Q}(P)
  #                   = (f_{u,Q}(P))^(u²-u-1) * f_{v,[u]Q}(P)
  #
  #  to have a common computation f_{u,Q}(P)
  # but this require a scalar mul [u]Q
  # and then its inversion to plug it back in the second Miller loop

  # f_{u+1,Q}(P)
  # ---------------------------------------------------------
  buf = '# 1st part: f_{u+1,Q}(P)\n'
  buf += f'const {curve_name}_pairing_ate_param_1_unopt* = block:\n'
  buf += ate_comment

  ate_bits = int(ate_param).bit_length()
  naf_bits = int(3*ate_param).bit_length() - ate_bits

  buf += f'  # +{naf_bits} to bitlength so that we can mul by 3 for NAF encoding\n'
  buf += f'  BigInt[{ate_bits}+{naf_bits}].fromHex"0x{Integer(abs(ate_param)).hex()}"\n\n'

  buf += f'const {curve_name}_pairing_ate_param_1_unopt_isNeg* = {"true" if ate_param < 0 else "false"}'

  # frobenius(f_{u*(u²-u-1),Q}(P))
  # ---------------------------------------------------------

  buf += '\n\n\n'
  buf += '# 2nd part: f_{u*(u²-u-1),Q}(P) followed by Frobenius application\n'
  buf += f'const {curve_name}_pairing_ate_param_2_unopt* = block:\n'
  buf += ate_comment_2

  ate_2_bits = int(ate_param_2).bit_length()
  naf_2_bits = int(3*ate_param_2).bit_length() - ate_2_bits

  buf += f'  # +{naf_2_bits} to bitlength so that we can mul by 3 for NAF encoding\n'
  buf += f'  BigInt[{ate_2_bits}+{naf_2_bits}].fromHex"0x{Integer(abs(ate_param_2)).hex()}"\n\n'

  buf += f'const {curve_name}_pairing_ate_param_2_unopt_isNeg* = {"true" if ate_param_2 < 0 else "false"}'

  buf += '\n'
  return buf

def genAteParam_BW6_opt(curve_name, curve_config):
  u = curve_config[curve_name]['field']['param']
  family = curve_config[curve_name]['field']['family']
  assert family == 'BW6'

  # Algorithm 5 - https://eprint.iacr.org/2020/351.pdf
  ate_param = u
  ate_param_2 = u^2 - u - 1

  ate_comment = '  # BW6 Miller loop first part is parametrized by u\n'
  ate_comment_2 = '  # BW6 Miller loop second part is parametrized by u²-u-1\n'

  # Note we can use the fact that
  #  f_{u+1,Q}(P) = f_{u,Q}(P) . l_{[u]Q,Q}(P)
  #  f_{u³-u²-u,Q}(P) = f_{u (u²-u-1),Q}(P)
  #                   = (f_{u,Q}(P))^(u²-u-1) * f_{v,[u]Q}(P)
  #
  #  to have a common computation f_{u,Q}(P)
  # but this require a scalar mul [u]Q
  # and then its inversion to plug it back in the second Miller loop

  # f_{u,Q}(P)
  # ---------------------------------------------------------
  buf = '# 1st part: f_{u,Q}(P)\n'
  buf += f'const {curve_name}_pairing_ate_param_1_opt* = block:\n'
  buf += ate_comment

  ate_bits = int(ate_param).bit_length()
  naf_bits = 0 # int(3*ate_param).bit_length() - ate_bits

  buf += f'  # no NAF for the optimized first Miller loop\n'
  buf += f'  BigInt[{ate_bits}].fromHex"0x{Integer(abs(ate_param)).hex()}"\n\n'

  buf += f'const {curve_name}_pairing_ate_param_1_opt_isNeg* = {"true" if ate_param < 0 else "false"}'

  # frobenius(f_{u²-u-1,Q}(P))
  # ---------------------------------------------------------

  buf += '\n\n\n'
  buf += '# 2nd part: f_{u²-u-1,Q}(P) followed by Frobenius application\n'
  buf += f'const {curve_name}_pairing_ate_param_2_opt* = block:\n'
  buf += ate_comment_2

  ate_2_bits = int(ate_param_2).bit_length()
  naf_2_bits = int(3*ate_param_2).bit_length() - ate_2_bits

  buf += f'  # +{naf_2_bits} to bitlength so that we can mul by 3 for NAF encoding\n'
  buf += f'  BigInt[{ate_2_bits}+{naf_2_bits}].fromHex"0x{Integer(abs(ate_param_2)).hex()}"\n\n'

  buf += f'const {curve_name}_pairing_ate_param_2_opt_isNeg* = {"true" if ate_param_2 < 0 else "false"}'

  buf += '\n'
  return buf

def genFinalExp(curve_name, curve_config):
  p = curve_config[curve_name]['field']['modulus']
  r = curve_config[curve_name]['field']['order']
  k = curve_config[curve_name]['tower']['embedding_degree']
  family = curve_config[curve_name]['field']['family']

  # For BLS12 and BW6, 3*hard part has a better expression
  # in the q basis with LLL algorithm
  scale = 1
  scaleDesc = ''
  if family == 'BLS12':
    scale = 3
    scaleDesc = ' * 3'
  if family == 'BW6':
    u = curve_config[curve_name]['field']['param']
    scale = 3*(u^3-u^2+1)
    scaleDesc = ' * 3*(u^3-u^2+1)'

  fexp = (p^k - 1)//r
  fexp *= scale

  buf = f'const {curve_name}_pairing_finalexponent* = block:\n'
  buf += f'  # (p^{k} - 1) / r' + scaleDesc
  buf += '\n'
  buf += f'  BigInt[{int(fexp).bit_length()}].fromHex"0x{Integer(fexp).hex()}"'

  return buf

# CLI
# ---------------------------------------------------------

if __name__ == "__main__":
  # Usage
  # BLS12-381
  # sage sage/derive_pairing.sage BLS12_381

  from argparse import ArgumentParser

  parser = ArgumentParser()
  parser.add_argument("curve",nargs="+")
  args = parser.parse_args()

  curve = args.curve[0]

  if curve not in Curves:
    raise ValueError(
      curve +
      ' is not one of the available curves: ' +
      str(Curves.keys())
    )
  else:
    ate = genAteParam(curve, Curves)
    fexp = genFinalExp(curve, Curves)

    with open(f'{curve.lower()}_pairing.nim', 'w') as f:
      f.write(copyright())
      f.write('\n\n')
      f.write(inspect.cleandoc("""
        import
          constantine/named/algebra,
          constantine/math/io/io_bigints

        # Slow generic implementation
        # ------------------------------------------------------------
      """))
      f.write('\n\n')
      f.write(ate)
      f.write('\n\n')
      f.write(fexp)
      f.write('\n\n')
      f.write(inspect.cleandoc("""
        # Addition chain
        # ------------------------------------------------------------
      """))

    print(f'Successfully created {curve}_pairing.nim')
