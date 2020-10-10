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
  if field == 'Fp2':
    v = vector(value)

    result = '# ' + comment_above + '\n' if comment_above else ''
    comment_right = ' # ' + comment_right if comment_right else ''

    result += inspect.cleandoc(f"""
      {prefix}Fp2[{curve}].fromHex( {comment_right}
        "0x{Integer(v[0]).hex()}",
        "0x{Integer(v[1]).hex()}"
      )""")
    return result
  else:
    raise newException(NotImplementedError)

# Code generators
# ---------------------------------------------------------

def genFrobeniusMapConstants(curve_name, curve_config):
  embdeg = curve_config[curve_name]['tower']['embedding_degree']
  twdeg = curve_config[curve_name]['tower']['twist_degree']
  g2field = f'Fp{embdeg//twdeg}' if (embdeg//twdeg) > 1 else 'Fp'

  p = curve_config[curve_name]['field']['modulus']
  Fp = GF(p)
  K.<u> = PolynomialRing(Fp)
  if g2field == 'Fp2':
    QNR_Fp = curve_config[curve_name]['tower']['QNR_Fp']
    Fp2.<beta> = Fp.extension(u^2 - QNR_Fp)

  SNR = curve_config[curve_name]['tower']['SNR_Fp2']
  if g2field == 'Fp2':
    cur = Fp2([1, 0])
    SNR = Fp2(SNR)
  else:
    cur = Fp(1)
    SNR = Fp(SNR)

  print('\n----> Frobenius extension field constants <----\n')
  buf = inspect.cleandoc(f"""
      # Frobenius map - on extension fields
      # -----------------------------------------------------------------

      # c = (SNR^((p-1)/{twdeg})^coef).
      # Then for frobenius(2): c  * conjugate(c)
      # And for frobenius(3):  c² * conjugate(c)
      const {curve_name}_FrobeniusMapCoefficients* = [
  """)

  FrobConst_map = SNR^((p-1)/6)
  FrobConst_map_list = []

  arr = ""

  for i in range(twdeg):
    if i == 0:
      arr += '\n# frobenius(1) -----------------------\n'
      arr += '['
    arr += field_to_nim(cur, g2field, curve_name, comment_right = f'SNR^((p-1)/{twdeg})^{i}')
    FrobConst_map_list.append(cur)
    cur *= FrobConst_map
    if i == twdeg - 1:
      arr += ']'
    arr += ',\n'

  for i in range(twdeg):
    if i == 0:
      arr += '# frobenius(2) -----------------------\n'
      arr += '['

    val = FrobConst_map_list[i]*conjugate(FrobConst_map_list[i])
    arr += field_to_nim(val, g2field, curve_name, comment_right = f'norm(SNR)^((p-1)/{twdeg})^{i}')

    if i == twdeg - 1:
      arr += ']'
    arr += ',\n'

  for i in range(twdeg):
    if i == 0:
      arr += '# frobenius(3) -----------------------\n'
      arr += '['

    val = FrobConst_map_list[i]^2 * conjugate(FrobConst_map_list[i])
    arr += field_to_nim(val, g2field, curve_name, comment_right = f'(SNR²)^((p-1)/{twdeg})^{i}')

    if i == twdeg - 1:
      arr += ']]'
    else:
      arr += ',\n'

  buf += textwrap.indent(arr, '  ')
  return buf

def genFrobeniusPsiConstants(curve_name, curve_config):
  embdeg = curve_config[curve_name]['tower']['embedding_degree']
  twdeg = curve_config[curve_name]['tower']['twist_degree']
  twkind = curve_config[curve_name]['tower']['twist']
  g2field = f'Fp{embdeg//twdeg}' if (embdeg//twdeg) > 1 else 'Fp'

  p = curve_config[curve_name]['field']['modulus']
  Fp = GF(p)
  K.<u> = PolynomialRing(Fp)
  if g2field == 'Fp2':
    QNR_Fp = curve_config[curve_name]['tower']['QNR_Fp']
    Fp2.<beta> = Fp.extension(u^2 - QNR_Fp)

  SNR = curve_config[curve_name]['tower']['SNR_Fp2']
  if g2field == 'Fp2':
    cur = Fp2([1, 0])
    SNR = Fp2(SNR)
  else:
    cur = Fp(1)
    SNR = Fp(SNR)

  print('\n----> ψ (Psi) - Untwist-Frobenius-Twist Endomorphism constants <----\n')
  buf = inspect.cleandoc(f"""
      # ψ (Psi) - Untwist-Frobenius-Twist Endomorphisms on twisted curves
      # -----------------------------------------------------------------
  """)
  buf += '\n'
  if twkind == 'D_Twist':
    buf += f'# {curve_name} is a D-Twist: psi1_coef1 = SNR^((p-1)/{twdeg})\n\n'
    FrobConst_psi = SNR^((p-1)/twdeg)
    snrUsed = 'SNR'
  else:
    buf += f'# {curve_name} is a M-Twist: psi1_coef1 = (1/SNR)^((p-1)/{twdeg})\n\n'
    FrobConst_psi = (1/SNR)^((p-1)/twdeg)
    snrUsed = '(1/SNR)'

  FrobConst_psi1_coef2 = FrobConst_psi^2
  FrobConst_psi1_coef3 = FrobConst_psi1_coef2 * FrobConst_psi

  buf += field_to_nim(
    FrobConst_psi1_coef2, g2field, curve_name,
    prefix = f'const {curve_name}_FrobeniusPsi_psi1_coef2* = ',
    comment_above = f'{snrUsed}^((p-1)/{twdeg//2})'
  ) + '\n'

  buf += field_to_nim(
    FrobConst_psi1_coef3, g2field, curve_name,
    prefix = f'const {curve_name}_FrobeniusPsi_psi1_coef3* = ',
    comment_above = f'{snrUsed}^((p-1)/{twdeg//3})'
  ) + '\n'

  FrobConst_psi2_coef2 = FrobConst_psi1_coef2 * FrobConst_psi1_coef2**p

  buf += field_to_nim(
    FrobConst_psi2_coef2, g2field, curve_name,
    prefix = f'const {curve_name}_FrobeniusPsi_psi2_coef2* = ',
    comment_above = f'norm({snrUsed})^((p-1)/{twdeg//2})'
  )

  # psi2_coef3 is always -1 (mod p^m) with m = embdeg/twdeg
  # Recap, with ξ (xi) the sextic non-residue
  # psi_2 = ((1/ξ)^((p-1)/6))^2 = (1/ξ)^((p-1)/3)
  # psi_3 = psi_2 * (1/ξ)^((p-1)/6) = (1/ξ)^((p-1)/3) * (1/ξ)^((p-1)/6) = (1/ξ)^((p-1)/2)
  #
  # Reminder, in 𝔽p2, frobenius(a) = a^p = conj(a)
  # psi2_2 = psi_2 * psi_2^p = (1/ξ)^((p-1)/3) * (1/ξ)^((p-1)/3)^p = (1/ξ)^((p-1)/3) * frobenius((1/ξ))^((p-1)/3)
  #        = norm(1/ξ)^((p-1)/3)
  # psi2_3 = psi_3 * psi_3^p = (1/ξ)^((p-1)/2) * (1/ξ)^((p-1)/2)^p = (1/ξ)^((p-1)/2) * frobenius((1/ξ))^((p-1)/2)
  #        = norm(1/ξ)^((p-1)/2)
  #
  # In Fp²:
  # - quadratic non-residues respect the equation a^((p²-1)/2) ≡ -1 (mod p²) by the Legendre symbol
  # - sextic non-residues are also quadratic non-residues so ξ^((p²-1)/2) ≡ -1 (mod p²)
  # - QRT(1/a) = QRT(a) with QRT the quadratic residuosity test
  #
  # We have norm(ξ)^((p-1)/2) = (ξ*frobenius(ξ))^((p-1)/2) = (ξ*(ξ^p))^((p-1)/2) = ξ^(p+1)^(p-1)/2
  #                           = ξ^((p²-1)/2)
  # And ξ^((p²-1)/2) ≡ -1 (mod p²)
  # So psi2_3 ≡ -1 (mod p²)

  return buf

# CLI
# ---------------------------------------------------------

if __name__ == "__main__":
  # Usage
  # BLS12-381
  # sage sage/derive_frobenius.sage BLS12_381

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
    FrobMap = genFrobeniusMapConstants(curve, Curves)
    FrobPsi = genFrobeniusPsiConstants(curve, Curves)

    with open(f'{curve.lower()}_frobenius.nim', 'w') as f:
      f.write(copyright())
      f.write('\n\n')
      f.write(inspect.cleandoc("""
        import
          ../config/curves,
          ../towers,
          ../io/io_towers
      """))
      f.write('\n\n')
      f.write(FrobMap)
      f.write('\n\n')
      f.write(FrobPsi)

    print(f'Successfully created {curve}_frobenius.nim')

    print(inspect.cleandoc("""\n
        For testing you can verify the following invariants:

        Galbraith-Lin-Scott, 2008, Theorem 1
        Fuentes-Castaneda et al, 2011, Equation (2)
          ψ(ψ(P)) - t*ψ(P) + p*P == Infinity

        Galbraith-Scott, 2008, Lemma 1
        The cyclotomic polynomial with GΦ(ψ(P)) == Infinity
        Hence for embedding degree k=12
          ψ⁴(P) - ψ²(P) + P == Infinity
        for embedding degree k=6
          ψ²(P) - ψ(P) + P == Infinity
      """))
