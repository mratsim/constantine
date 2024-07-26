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

def genSqrtFp2Constants(curve_name, curve_config):
  embdeg = curve_config[curve_name]['tower']['embedding_degree']
  twdeg = curve_config[curve_name]['tower']['twist_degree']
  g2field = f'Fp{embdeg//twdeg}' if (embdeg//twdeg) > 1 else 'Fp'

  p = curve_config[curve_name]['field']['modulus']
  Fp = GF(p)
  K.<u> = PolynomialRing(Fp)
  if g2field == 'Fp2':
    QNR_Fp = curve_config[curve_name]['tower']['QNR_Fp']
    Fp2.<beta> = Fp.extension(u^2 - QNR_Fp)
  else:
    SNR_Fp = curve_config[curve_name]['tower']['SNR_Fp']
    Fp2.<beta> = Fp.extension(u^2 - SNR_Fp)

  sqrt_QNR = Fp2([0, 1])
  sqrt_sqrt_QNR = sqrt_QNR.sqrt()
  sqrt_minus_sqrt_QNR = (-sqrt_QNR).sqrt()

  print('\n----> Square root on Fp2 constants <----\n')
  buf = inspect.cleandoc(f"""
      # Square Root Fp2 constants
      # -----------------------------------------------------------------
  """)
  buf += '\n'

  buf += f'const {curve_name}_sqrt_QNR* = '
  buf += field_to_nim(sqrt_QNR, 'Fp2', curve_name)
  buf += '\n'

  buf += f'const {curve_name}_sqrt_sqrt_QNR* = '
  buf += field_to_nim(sqrt_sqrt_QNR, 'Fp2', curve_name)
  buf += '\n'

  buf += f'const {curve_name}_sqrt_minus_sqrt_QNR* = '
  buf += field_to_nim(sqrt_minus_sqrt_QNR, 'Fp2', curve_name)
  buf += '\n'

  return buf

# CLI
# ---------------------------------------------------------

if __name__ == "__main__":
  # Usage
  # BLS12-381
  # sage sage/derive_sqrt.sage BLS12_381

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
    sqrt = genSqrtFp2Constants(curve, Curves)

    with open(f'{curve.lower()}_square_root.nim', 'w') as f:
      f.write(copyright())
      f.write('\n\n')

      f.write(inspect.cleandoc("""
          import
            constantine/named/algebra,
            constantine/math/io/io_extfields
      """))

      f.write('\n\n')
      f.write(sqrt)

    print(f'Successfully created {curve}_sqrt_fp2.nim')
