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
    return genAteParam_BW6(curve_name, curve_config)
  else:
    raise ValueError(f'family: {family} is not implemented')

  buf = '# The bit count must be exact for the Miller loop\n'
  buf += f'const {curve_name}_pairing_ate_param* = block:\n'
  buf += ate_comment

  ate_bits = int(ate_param).bit_length()
  naf_bits = int(3*ate_param).bit_length() - ate_bits

  buf += f'  # +{naf_bits} to bitlength so that we can mul by 3 for NAF encoding\n'
  buf += f'  BigInt[{ate_bits}+{naf_bits}].fromHex"0x{Integer(abs(ate_param)).hex()}"\n\n'

  buf += f'const {curve_name}_pairing_ate_param_isNeg* = {"true" if ate_param < 0 else "false"}'

  return buf

def genAteParam_BW6(curve_name, curve_config):
  u = curve_config[curve_name]['field']['param']
  family = curve_config[curve_name]['field']['family']
  assert family == 'BW6'

  # Algorithm 5 - https://eprint.iacr.org/2020/351.pdf
  ate_param = u
  ate_comment = '  # BW6 Miller loop first part is parametrized by u\n'
  ate_comment_2 = '  # BW6 Miller loop second part is parametrized by u²-u-1\n'

  # fu,Q(P)
  # ---------------------------------------------------------
  buf = '# 1st part: fu,Q(P)\n'
  buf += f'const {curve_name}_pairing_ate_param_1* = block:\n'
  buf += ate_comment

  ate_bits = int(ate_param).bit_length()
  naf_bits = int(3*ate_param).bit_length() - ate_bits

  buf += f'  # +{naf_bits} to bitlength so that we can mul by 3 for NAF encoding\n'
  buf += f'  BigInt[{ate_bits}+{naf_bits}].fromHex"0x{Integer(abs(ate_param)).hex()}"\n\n'

  buf += f'const {curve_name}_pairing_ate_param_isNeg* = {"true" if ate_param < 0 else "false"}'

  # f(u²-u-1),Q(P)
  # ---------------------------------------------------------

  buf += '\n\n\n'
  buf += '# 2nd part: f(u²-u-1),Q(P)\n'
  buf += f'const {curve_name}_pairing_ate_param_2* = block:\n'
  buf += ate_comment_2

  ate_param_2 = ate_param^2 - ate_param - 1

  ate_2_bits = int(ate_param_2).bit_length()
  naf_2_bits = int(3*ate_param_2).bit_length() - ate_2_bits

  buf += f'  # +{naf_2_bits} to bitlength so that we can mul by 3 for NAF encoding\n'
  buf += f'  BigInt[{ate_2_bits}+{naf_2_bits}].fromHex"0x{Integer(abs(ate_param_2)).hex()}"\n\n'

  buf += f'const {curve_name}_pairing_ate_param_2_isNeg* = {"true" if ate_param_2 < 0 else "false"}'

  buf += '\n'
  return buf

def genFinalExp(curve_name, curve_config):
  p = curve_config[curve_name]['field']['modulus']
  r = curve_config[curve_name]['field']['order']
  k = curve_config[curve_name]['tower']['embedding_degree']
  family = curve_config[curve_name]['field']['family']

  fexp = (p^k - 1)//r
  if family == 'BLS12':
    fexp *= 3

  buf = f'const {curve_name}_pairing_finalexponent* = block:\n'
  buf += f'  # (p^{k} - 1) / r' + (' * 3' if family == 'BLS12' else '')
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
          ../config/[curves, type_bigint],
          ../io/io_bigints

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
