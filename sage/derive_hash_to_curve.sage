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

def dump_poly(name, poly, field, curve):
  result =  f'const {name}* = [\n'
  result += '  # Polynomial k₀ + k₁ x + k₂ x² + k₃ x³ + ... + kₙ xⁿ\n'
  result += '  # The polynomial is stored as an array of coefficients ordered from k₀ to kₙ\n'
  result += '\n'

  poly = list(poly)
  lastRow = len(poly) - 1

  for rowID, val in enumerate(reversed(poly)):
    (coef, power) = val
    result += textwrap.indent(
      field_to_nim(
        coef, field, curve,
        comment_above = str(power)
      ),
      '  ')
    result += ',\n' if rowID != lastRow else '\n'

  result += ']'
  return result

# Unused
# ---------------------------------------------------------

def find_z_sswu(F, A, B):
    """
    https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-11#ref-SAGE
    Arguments:
    - F, a field object, e.g., F = GF(2^521 - 1)
    - A and B, the coefficients of the curve equation y² = x³ + A * x + B
    """
    R.<xx> = F[]                        # Polynomial ring over F
    g = xx^3 + F(A) * xx + F(B)         # y² = g(x) = x³ + A * x + B
    ctr = F.gen()
    while True:
        for Z_cand in (F(ctr), F(-ctr)):
            if Z_cand.is_square():
                # Criterion 1: Z is non-square in F.
                continue
            if Z_cand == F(-1):
                # Criterion 2: Z != -1 in F.
                continue
            if not (g - Z_cand).is_irreducible():
                # Criterion 3: g(x) - Z is irreducible over F.
                continue
            if g(B / (Z_cand * A)).is_square():
                # Criterion 4: g(B / (Z * A)) is square in F.
                return Z_cand
        ctr += 1

# BLS12-381 G2
# ---------------------------------------------------------
# Hardcoding from spec:
# - https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-11#section-8.8.2
# - https://github.com/cfrg/draft-irtf-cfrg-hash-to-curve/blob/f7dd3761/poc/sswu_opt_9mod16.sage#L142-L148

def genBLS12381G2_H2C_constants(curve_config):
  curve_name = 'BLS12_381'

  # ------------------------------------------
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
  # ------------------------------------------

  # Hash to curve isogenous curve parameters
  # y² = x³ + A'*x + B'

  print('\n----> Hash-to-Curve map to isogenous BLS12-381 E\'2 <----\n')
  buf = inspect.cleandoc(f"""
      # Hash-to-Curve map to isogenous BLS12-381 E'2 constants
      # -----------------------------------------------------------------
      #
      # y² = x³ + A'*x + B' with p² = q ≡ 9 (mod 16), p the BLS12-381 characteristic (base modulus)
      #
      # Hardcoding from spec:
      # - https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-11#section-8.8.2
      # - https://github.com/cfrg/draft-irtf-cfrg-hash-to-curve/blob/f7dd3761/poc/sswu_opt_9mod16.sage#L142-L148
  """)
  buf += '\n\n'

  # Base constants
  Aprime_E2 = Fp2([0, 240])
  Bprime_E2 = Fp2([1012, 1012])
  Z = Fp2([-2, -1])
  # Extra
  minus_A = -Aprime_E2
  ZmulA = Z * Aprime_E2
  inv_Z3 = (Z^3)^-1               # modular inverse of Z³
  (a, b) = vector(inv_Z3)
  squared_norm_inv_Z3 = a^2 + b^2 # ||1/Z³||²
  # x^((p-3)/4)) ≡ 1/√x (mod p) if p ≡ 3 (mod 4)
  inv_norm_inv_Z3 = squared_norm_inv_Z3^((p-3)/4) # 1/||1/Z³||

  buf += f'const {curve_name}_h2c_G2_Aprime_E2* = '
  buf += field_to_nim(Aprime_E2, 'Fp2', curve_name, comment_right = "240𝑖")
  buf += '\n'

  buf += f'const {curve_name}_h2c_G2_Bprime_E2* = '
  buf += field_to_nim(Bprime_E2, 'Fp2', curve_name, comment_right = "1012 * (1 + 𝑖)")
  buf += '\n'

  buf += f'const {curve_name}_h2c_G2_Z* = '
  buf += field_to_nim(Z, 'Fp2', curve_name, comment_right = "-(2 + 𝑖)")
  buf += '\n'

  buf += f'const {curve_name}_h2c_G2_minus_A* = '
  buf += field_to_nim(minus_A, 'Fp2', curve_name, comment_right = "-240𝑖")
  buf += '\n'

  buf += f'const {curve_name}_h2c_G2_ZmulA* = '
  buf += field_to_nim(ZmulA, 'Fp2', curve_name, comment_right = "Z*A = 240-480𝑖")
  buf += '\n'

  buf += f'const {curve_name}_h2c_G2_inv_Z3* = '
  buf += field_to_nim(inv_Z3, 'Fp2', curve_name, comment_right = "1/Z³")
  buf += '\n'

  buf += f'const {curve_name}_h2c_G2_squared_norm_inv_Z3* = '
  buf += field_to_nim(squared_norm_inv_Z3, 'Fp', curve_name, comment_right = "||1/Z³||²")
  buf += '\n'

  buf += f'const {curve_name}_h2c_G2_inv_norm_inv_Z3* = '
  buf += field_to_nim(inv_norm_inv_Z3, 'Fp', curve_name, comment_right = "1/||1/Z³||")
  buf += '\n'

  return buf

def genBLS12381G2_H2C_isogeny_map(curve_config):
  curve_name = 'BLS12_381'

  # ------------------------------------------
  p = curve_config[curve_name]['field']['modulus']
  # This extension field construction
  # does not work with isogenies :/
  #
  # embdeg = curve_config[curve_name]['tower']['embedding_degree']
  # twdeg = curve_config[curve_name]['tower']['twist_degree']
  # g2field = f'Fp{embdeg//twdeg}' if (embdeg//twdeg) > 1 else 'Fp'
  #
  # Fp = GF(p)
  # K.<u> = PolynomialRing(Fp)
  # if g2field == 'Fp2':
  #   QNR_Fp = curve_config[curve_name]['tower']['QNR_Fp']
  #   Fp2.<beta> = Fp.extension(u^2 - QNR_Fp)
  # else:
  #   SNR_Fp = curve_config[curve_name]['tower']['SNR_Fp']
  #   Fp2.<beta> = Fp.extension(u^2 - SNR_Fp)
  # ------------------------------------------

  QNR_Fp = curve_config[curve_name]['tower']['QNR_Fp']
  Fp2.<beta> = GF(p^2, modulus=(x^2-QNR_Fp))

  # Hash to curve isogenous curve parameters
  # y² = x³ + A'*x + B'

  print('\n----> Hash-to-Curve 3-isogeny map BLS12-381 E\'2 constants <----\n')
  buf = inspect.cleandoc(f"""
      # Hash-to-Curve 3-isogeny map BLS12-381 E'2 constants
      # -----------------------------------------------------------------
      #
      # The polynomials map a point (x', y') on the isogenous curve E'2
      # to (x, y) on E2, represented as (xnum/xden, y' * ynum/yden)

  """)
  buf += '\n\n'

  # Base constants - E2
  A = curve_config[curve_name]['curve']['a']
  B = curve_config[curve_name]['curve']['b']
  twist = curve_config[curve_name]['tower']['twist']
  SNR_Fp2 = curve_config[curve_name]['tower']['SNR_Fp2']

  if twist == 'M_twist':
    Btwist = B * Fp2(SNR_Fp2)
  else:
    Btwist = B / Fp2(SNR_Fp2)

  E2 = EllipticCurve(Fp2, [A, B * Fp2(SNR_Fp2)])

  # Base constants - Isogenous curve E'2, degree 3
  Aprime_E2 = Fp2([0, 240])
  Bprime_E2 = Fp2([1012, 1012])
  Eprime2 = EllipticCurve(Fp2, [Aprime_E2, Bprime_E2])

  iso_kernel = [6 * (1 - beta), 1]
  iso = EllipticCurveIsogeny(E=Eprime2, kernel=iso_kernel, codomain=E2, degree=3)
  if (- iso.rational_maps()[1])(1, 1) > iso.rational_maps()[1](1, 1):
      iso.switch_sign()

  (xm, ym) = iso.rational_maps()
  maps = (xm.numerator(), xm.denominator(), ym.numerator(), ym.denominator())

  buf += dump_poly(
    'BLS12_381_h2c_G2_3_isogeny_map_xnum',
    xm.numerator(), 'Fp2', curve_name)
  buf += '\n'
  buf += dump_poly(
    'BLS12_381_h2c_G2_3_isogeny_map_xden',
    xm.denominator(), 'Fp2', curve_name)
  buf += '\n'
  buf += dump_poly(
    'BLS12_381_h2c_G2_3_isogeny_map_ynum',
    ym.numerator(), 'Fp2', curve_name)
  buf += '\n'
  buf += dump_poly(
    'BLS12_381_h2c_G2_3_isogeny_map_yden',
    ym.denominator(), 'Fp2', curve_name)

  return buf

# CLI
# ---------------------------------------------------------

if __name__ == "__main__":
  # Usage
  # BLS12-381
  # sage sage/derive_hash_to_curve.sage BLS12_381 G2

  from argparse import ArgumentParser

  parser = ArgumentParser()
  parser.add_argument("curve",nargs="+")
  args = parser.parse_args()

  curve = args.curve[0]
  group = args.curve[1]

  if curve == 'BLS12_381' and group == 'G2':
    h2c = genBLS12381G2_H2C_constants(Curves)
    h2c += '\n\n'
    h2c += genBLS12381G2_H2C_isogeny_map(Curves)

    with open(f'{curve.lower()}_g2_hash_to_curve.nim', 'w') as f:
      f.write(copyright())
      f.write('\n\n')

      f.write(inspect.cleandoc("""
          import
            ../config/curves,
            ../io/[io_fields, io_towers]
      """))

      f.write('\n\n')
      f.write(h2c)

    print(f'Successfully created {curve.lower()}_g2_hash_to_curve.nim')
  else:
    raise ValueError(
      curve + group +
      ' is not configured '
    )
