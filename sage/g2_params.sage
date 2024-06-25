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
#                    Frobenius constants
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

def fp2_to_hex(a):
    v = vector(a)
    return '0x' + Integer(v[0]).hex() + ' + β * ' + '0x' + Integer(v[1]).hex()

def field_to_nim(value, field, curve, prefix = "", comment_above = "", comment_right = ""):
  result = '# ' + comment_above + '\n' if comment_above else ''
  comment_right = ' # ' + comment_right if comment_right else ''

  if field == 'Fp2':
    v = vector(value)

    result += inspect.cleandoc(f"""
      {prefix}Fp2[{curve}].fromHex( {comment_right}
        "0x{Integer(v[0]).hex()}",
        "0x{Integer(v[1]).hex()}"
      )""")
  elif field == 'Fp':
    result += inspect.cleandoc(f"""
      {prefix}Fp[{curve}].fromHex( {comment_right}
        "0x{Integer(value).hex()}")
      """)
  else:
    raise NotImplementedError()

  return result

# Code generators
# ---------------------------------------------------------

def gen_coef_b_on_G2(curve_name, curve_config):
  p = curve_config[curve_name]['field']['modulus']
  r = curve_config[curve_name]['field']['order']
  form = curve_config[curve_name]['curve']['form']
  a = curve_config[curve_name]['curve']['a']
  b = curve_config[curve_name]['curve']['b']
  embedding_degree = curve_config[curve_name]['tower']['embedding_degree']
  twist_degree = curve_config[curve_name]['tower']['twist_degree']
  twist = curve_config[curve_name]['tower']['twist']

  G2_field_degree = embedding_degree // twist_degree
  G2_field = f'Fp{G2_field_degree}' if G2_field_degree > 1 else 'Fp'

  if G2_field_degree == 2:
    non_residue_fp = curve_config[curve_name]['tower']['QNR_Fp']
  elif G2_field_degree == 1:
    if twist_degree == 6:
      # Only for complete serialization
      non_residue_fp = curve_config[curve_name]['tower']['SNR_Fp']
    else:
      raise NotImplementedError()
  else:
    raise NotImplementedError()

  Fp = GF(p)
  K.<u> = PolynomialRing(Fp)

  if G2_field == 'Fp2':
    Fp2.<beta> = Fp.extension(u^2 - non_residue_fp)
    G2F = Fp2
    if twist_degree == 6:
      non_residue_twist = curve_config[curve_name]['tower']['SNR_Fp2']
    else:
      raise NotImplementedError()
  elif G2_field == 'Fp':
    G2F = Fp
    if twist_degree == 6:
      non_residue_twist = curve_config[curve_name]['tower']['SNR_Fp']
    else:
      raise NotImplementedError()
  else:
    raise NotImplementedError()

  if twist == 'D_Twist':
    G2B = b/G2F(non_residue_twist)
    G2 = EllipticCurve(G2F, [0, G2B])
  elif twist == 'M_Twist':
    G2B = b*G2F(non_residue_twist)
    G2 = EllipticCurve(G2F, [0, G2B])
  else:
    raise ValueError('G2 must be a D_Twist or M_Twist but found ' + twist)

  buf = inspect.cleandoc(f"""
      # Curve precomputed parameters
      # -----------------------------------------------------------------
  """)
  buf += '\n'

  buf += f'const {curve_name}_coefB_G2* = '
  buf += field_to_nim(G2B, G2_field, curve_name)
  buf += '\n'

  buf += f'const {curve_name}_coefB_G2_times_3* = '
  buf += field_to_nim(3*G2B, G2_field, curve_name)
  buf += '\n'

  return buf

# CLI
# ---------------------------------------------------------

if __name__ == "__main__":
  # Usage
  # BLS12-381
  # sage sage/precompute_params.sage BLS12_381

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
    G2B = gen_coef_b_on_G2(curve, Curves)

    with open(f'{curve.lower()}_constants.nim', 'w') as f:
      f.write(copyright())
      f.write('\n\n')

      f.write(inspect.cleandoc("""
          import
            constantine/named/algebra,
            constantine/math/io/[io_fields, io_extfields]
      """))

      f.write('\n\n')
      f.write(G2B)

    print(f'Successfully created {curve.lower()}_constants.nim')
