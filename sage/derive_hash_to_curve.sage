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
import sage.schemes.elliptic_curves.isogeny_small_degree as isd

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

ZZR = PolynomialRing(ZZ, name='XX')
def sgn0(x):
    """
    Returns 1 if x is 'negative' (little-endian sense), else 0.
    """
    degree = x.parent().degree()
    if degree == 1:
        # not a field extension
        xi_values = (ZZ(x),)
    else:
        # field extension
        xi_values = ZZR(x)  # extract vector repr of field element (faster than x._vector_())
    sign = 0
    zero = 1
    # compute the sign in constant time
    for i in range(0, degree):
        zz_xi = xi_values[i]
        # sign of this digit
        sign_i = zz_xi % 2
        zero_i = zz_xi == 0
        # update sign and zero
        sign = sign | (zero & sign_i)
        zero = zero & zero_i
    return sign

# Generic Shallue-van de Woestijne map
# ---------------------------------------------------------

def find_z_svdw(F, A, B):
    """
    https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-14#appendix-H.1
    Arguments:
    - F, a field object, e.g., F = GF(2^521 - 1)
    - A and B, the coefficients of the curve y^2 = x^3 + A * x + B
    """
    g = lambda x: F(x)^3 + F(A) * F(x) + F(B)
    h = lambda Z: -(F(3) * Z^2 + F(4) * A) / (F(4) * g(Z))
    ctr = F.gen()
    while True:
        for Z_cand in (F(ctr), F(-ctr)):
            if g(Z_cand) == F(0):
                # Criterion 1: g(Z) != 0 in F.
                continue
            if h(Z_cand) == F(0):
                # Criterion 2: -(3 * Z^2 + 4 * A) / (4 * g(Z)) != 0 in F.
                continue
            if not h(Z_cand).is_square():
                # Criterion 3: -(3 * Z^2 + 4 * A) / (4 * g(Z)) is square in F.
                continue
            if g(Z_cand).is_square() or g(-Z_cand / F(2)).is_square():
                # Criterion 4: At least one of g(Z) and g(-Z / 2) is square in F.
                return Z_cand
        ctr += 1


# Isogenies for Simplified Shallue-van de Woestijne-Ulas map
# ---------------------------------------------------------

def find_iso(E):
  """
  Find an isogenous curve with j-invariant not in {0, 1728} so that
  Simplified Shallue-van de Woestijne method is directly applicable
  (i.e the Elliptic Curve coefficient y² = x³ + A*x + B have  AB != 0)
  """
  for p_test in primes(30):
    isos = [i for i in isd.isogenies_prime_degree(E, p_test)
            if i.codomain().j_invariant() not in (0, 1728) ]
    if len(isos) > 0:
      print(f'✔️✔️✔️ Found {len(isos)} isogenous curves of degree {p_test}')
      return isos[0].dual()
  print(f'⚠️⚠️⚠️ Found no isogenies for {E}')
  return None

def find_z_sswu(F, A, B):
    """
    https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-14#appendix-H.2
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

def search_isogeny(curve_name, curve_config):
    p = curve_config[curve_name]['field']['modulus']
    Fp = GF(p)

    # Base constants - E1
    A = curve_config[curve_name]['curve']['a']
    B = curve_config[curve_name]['curve']['b']
    E1 =  EllipticCurve(Fp, [A, B])

    # Base constants - E2
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
        G2B = B/G2F(non_residue_twist)
        E2 = EllipticCurve(G2F, [0, G2B])
    elif twist == 'M_Twist':
        G2B = B*G2F(non_residue_twist)
        E2 = EllipticCurve(G2F, [0, G2B])
    else:
        raise ValueError('E2 must be a D_Twist or M_Twist but found ' + twist)

    # Isogenies:
    iso_G1 = find_iso(E1)
    iso_G2 = find_iso(E2)

    if iso_G1 == None or iso_G2 == None:
      # TODO: case when G1 has a cheap isogeny but G2 does not
      Z_G1 = find_z_svdw(Fp, A, B)
      print(f"Z G1 (svdw): {Z_G1}")
      Z_G2 = find_z_svdw(Fp2, A, G2B)
      print(f"Z G2 (svdw): {fp2_to_hex(Z_G2)}")
      return

    a_G1 = iso_G1.domain().a4()
    b_G1 = iso_G1.domain().a6()

    a_G2 = iso_G2.domain().a4()
    b_G2 = iso_G2.domain().a6()

    # Z
    Z_G1 = find_z_sswu(Fp, a_G1, b_G1)
    Z_G2 = find_z_sswu(Fp2, a_G2, b_G2)

    print(f"{curve_name} G1 - isogeny of degree {iso_G1.degree()} with eq y² = x³ + A'x + B':")
    print(f"  A': 0x{Integer(a_G1).hex()}")
    print(f"  B': 0x{Integer(b_G1).hex()}")
    print(f"  Z (sswu): {Z_G1}")

    print(f"{curve_name} G2 - isogeny of degree {iso_G2.degree()} with eq y² = x³ + A'x + B':")
    print(f"  A': {fp2_to_hex(a_G2)}")
    print(f"  B': {fp2_to_hex(b_G2)}")
    print(f"  Z (sswu): {fp2_to_hex(Z_G2)}")

# BLS12-381 G1
# ---------------------------------------------------------
# Hardcoding from spec:
# - https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-11#section-8.8.1
# - https://github.com/cfrg/draft-irtf-cfrg-hash-to-curve/blob/f7dd3761/poc/sswu_opt_3mod4.sage#L126-L132

def genBLS12381G1_H2C_constants(curve_config):
  curve_name = 'BLS12_381'

  # ------------------------------------------
  p = curve_config[curve_name]['field']['modulus']
  Fp = GF(p)
  # ------------------------------------------

  # Hash to curve isogenous curve parameters
  # y² = x³ + A'*x + B'

  print('\n----> Hash-to-Curve map to isogenous BLS12-381 E\'1 <----\n')
  buf = inspect.cleandoc(f"""
      # Hash-to-Curve map to isogenous BLS12-381 E'1 constants
      # -----------------------------------------------------------------
      #
      # y² = x³ + A'*x + B' with p ≡ 3 (mod 4) the BLS12-381 characteristic (base modulus)
      #
      # Hardcoding from spec:
      # - https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-11#section-8.8.1
      # - https://github.com/cfrg/draft-irtf-cfrg-hash-to-curve/blob/f7dd3761/poc/sswu_opt_3mod4.sage#L126-L132
  """)
  buf += '\n\n'

  # Base constants
  Aprime_E1 = Fp('0x144698a3b8e9433d693a02c96d4982b0ea985383ee66a8d8e8981aefd881ac98936f8da0e0f97f5cf428082d584c1d')
  Bprime_E1 = Fp('0x12e2908d11688030018b12e8753eee3b2016c1f0f24f4070a0b9c14fcef35ef55a23215a316ceaa5d1cc48e98e172be0')
  Z = Fp(11)
  # Extra
  minus_A = -Aprime_E1
  ZmulA = Z * Aprime_E1
  sqrt_minus_Z3 = sqrt(-Z^3)

  buf += f'const {curve_name}_h2c_G1_Aprime_E1* = '
  buf += field_to_nim(Aprime_E1, 'Fp', curve_name)
  buf += '\n'

  buf += f'const {curve_name}_h2c_G1_Bprime_E1* = '
  buf += field_to_nim(Bprime_E1, 'Fp', curve_name)
  buf += '\n'

  buf += f'const {curve_name}_h2c_G1_Z* = '
  buf += field_to_nim(Z, 'Fp', curve_name)
  buf += '\n'

  buf += f'const {curve_name}_h2c_G1_minus_A* = '
  buf += field_to_nim(minus_A, 'Fp', curve_name)
  buf += '\n'

  buf += f'const {curve_name}_h2c_G1_ZmulA* = '
  buf += field_to_nim(ZmulA, 'Fp', curve_name)
  buf += '\n'

  buf += f'const {curve_name}_h2c_G1_sqrt_minus_Z3* = '
  buf += field_to_nim(sqrt_minus_Z3, 'Fp', curve_name)
  buf += '\n'

  return buf

def genBLS12381G1_H2C_isogeny_map(curve_config):
  curve_name = 'BLS12_381'

  # Hash to curve isogenous curve parameters
  # y² = x³ + A'*x + B'

  print('\n----> Hash-to-Curve 3-isogeny map BLS12-381 E\'1 constants <----\n')
  buf = inspect.cleandoc(f"""
      # Hash-to-Curve 11-isogeny map BLS12-381 E'1 constants
      # -----------------------------------------------------------------
      #
      # The polynomials map a point (x', y') on the isogenous curve E'1
      # to (x, y) on E1, represented as (xnum/xden, y' * ynum/yden)

  """)
  buf += '\n\n'

  p = curve_config[curve_name]['field']['modulus']
  Fp = GF(p)

  # Base constants - E1
  A = curve_config[curve_name]['curve']['a']
  B = curve_config[curve_name]['curve']['b']
  E1 =  EllipticCurve(Fp, [A, B])

  # Base constants - Isogenous curve E'1, degree 11
  Aprime_E1 = Fp('0x144698a3b8e9433d693a02c96d4982b0ea985383ee66a8d8e8981aefd881ac98936f8da0e0f97f5cf428082d584c1d')
  Bprime_E1 = Fp('0x12e2908d11688030018b12e8753eee3b2016c1f0f24f4070a0b9c14fcef35ef55a23215a316ceaa5d1cc48e98e172be0')
  Eprime1 = EllipticCurve(Fp, [Aprime_E1, Bprime_E1])

  iso = EllipticCurveIsogeny(E=E1, kernel=None, codomain=Eprime1, degree=11).dual()
  if (- iso.rational_maps()[1])(1, 1) > iso.rational_maps()[1](1, 1):
      iso.switch_sign()

  (xm, ym) = iso.rational_maps()
  maps = (xm.numerator(), xm.denominator(), ym.numerator(), ym.denominator())

  buf += dump_poly(
    'BLS12_381_h2c_G1_11_isogeny_map_xnum',
    xm.numerator(), 'Fp', curve_name)
  buf += '\n'
  buf += dump_poly(
    'BLS12_381_h2c_G1_11_isogeny_map_xden',
    xm.denominator(), 'Fp', curve_name)
  buf += '\n'
  buf += dump_poly(
    'BLS12_381_h2c_G1_11_isogeny_map_ynum',
    ym.numerator(), 'Fp', curve_name)
  buf += '\n'
  buf += dump_poly(
    'BLS12_381_h2c_G1_11_isogeny_map_yden',
    ym.denominator(), 'Fp', curve_name)

  return buf

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

  E2 = EllipticCurve(Fp2, [A, Btwist])

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

def genSVDW_H2C_G1_constants(curve, curve_config, Z):
  p = curve_config[curve]['field']['modulus']
  a = curve_config[curve]['curve']['a']
  b = curve_config[curve]['curve']['b']

  Fp = GF(p)

  print(f'\n----> Hash-to-Curve Shallue-van de Woestijne {curve} G1 map <----\n')
  buf = inspect.cleandoc(f"""
      # Hash-to-Curve Shallue-van de Woestijne {curve} G1 map
      # -----------------------------------------------------------------
      # Spec:
      # - https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-14#appendix-F.1
  """)
  buf += '\n\n'

  c1 = Z^3 + a*Z + b
  c2 = -Z/2
  t = 3 * Z^2 + 4 * a
  c3 = sqrt(-c1 * t)
  if sgn0(c3) == 1:
    c3 = -c3
  c4 = -4 * c1 / t

  buf += f'const {curve}_h2c_svdw_G1_Z* = '
  buf += field_to_nim(Z, 'Fp', curve)
  buf += '\n'

  buf += f'const {curve}_h2c_svdw_G1_curve_eq_rhs_Z* = '
  buf += field_to_nim(c1, 'Fp', curve)
  buf += '\n'

  buf += f'const {curve}_h2c_svdw_G1_minus_Z_div_2* = '
  buf += field_to_nim(c2, 'Fp', curve)
  buf += '\n'

  buf += f'const {curve}_h2c_svdw_G1_z3* = '
  buf += field_to_nim(c3, 'Fp', curve)
  buf += '\n'

  buf += f'const {curve}_h2c_svdw_G1_z4* = '
  buf += field_to_nim(c4, 'Fp', curve)
  buf += '\n'

  return buf

def genSVDW_H2C_G2_constants(curve, curve_config, Z):
  p = curve_config[curve]['field']['modulus']
  a = curve_config[curve]['curve']['a']
  b = curve_config[curve]['curve']['b']

  embedding_degree = curve_config[curve]['tower']['embedding_degree']
  twist_degree = curve_config[curve]['tower']['twist_degree']
  twist = curve_config[curve]['tower']['twist']

  G2_field_degree = embedding_degree // twist_degree
  G2_field = f'Fp{G2_field_degree}' if G2_field_degree > 1 else 'Fp'

  if G2_field_degree == 2:
      non_residue_fp = curve_config[curve]['tower']['QNR_Fp']
  elif G2_field_degree == 1:
      if twist_degree == 6:
          # Only for complete serialization
          non_residue_fp = curve_config[curve]['tower']['SNR_Fp']
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
          non_residue_twist = curve_config[curve]['tower']['SNR_Fp2']
      else:
          raise NotImplementedError()
  elif G2_field == 'Fp':
      G2F = Fp
      if twist_degree == 6:
          non_residue_twist = curve_config[curve]['tower']['SNR_Fp']
      else:
          raise NotImplementedError()
  else:
      raise NotImplementedError()

  if twist == 'D_Twist':
      G2B = b/G2F(non_residue_twist)
  elif twist == 'M_Twist':
      G2B = b*G2F(non_residue_twist)
  else:
      raise ValueError('E2 must be a D_Twist or M_Twist but found ' + twist)

  print(f'\n----> Hash-to-Curve Shallue-van de Woestijne {curve} G2 map <----\n')
  buf = inspect.cleandoc(f"""
      # Hash-to-Curve Shallue-van de Woestijne {curve} G2 map
      # -----------------------------------------------------------------
      # Spec:
      # - https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-14#appendix-F.1
  """)
  buf += '\n\n'

  c1 = Z^3 + a*Z + G2B
  c2 = -Z/2
  t = 3 * Z^2 + 4 * a
  c3 = sqrt(-c1 * t)
  if sgn0(c3) == 1:
    c3 = -c3
  c4 = -4 * c1 / t

  buf += f'const {curve}_h2c_svdw_G2_Z* = '
  buf += field_to_nim(Z, G2_field, curve)
  buf += '\n'

  buf += f'const {curve}_h2c_svdw_G2_curve_eq_rhs_Z* = '
  buf += field_to_nim(c1, G2_field, curve)
  buf += '\n'

  buf += f'const {curve}_h2c_svdw_G2_minus_Z_div_2* = '
  buf += field_to_nim(c2, G2_field, curve)
  buf += '\n'

  buf += f'const {curve}_h2c_svdw_G2_z3* = '
  buf += field_to_nim(c3, G2_field, curve)
  buf += '\n'

  buf += f'const {curve}_h2c_svdw_G2_z4* = '
  buf += field_to_nim(c4, G2_field, curve)
  buf += '\n'

  return buf

# CLI
# ---------------------------------------------------------

if __name__ == "__main__":
  # Usage
  # BLS12-381
  #   sage sage/derive_hash_to_curve.sage BLS12_381 G2
  # for Hash-to-Curve
  # or
  #   sage sage/derive_hash_to_curve.sage BLS12_381 iso
  # to search for a suitable isogeny

  from argparse import ArgumentParser

  parser = ArgumentParser()
  parser.add_argument("curve",nargs="+")
  args = parser.parse_args()

  curve = args.curve[0]
  group_or_iso = args.curve[1]

  if group_or_iso == 'iso':
    search_isogeny(curve, Curves)

  elif curve == 'BLS12_381' and group_or_iso == 'G1':
    h2c = genBLS12381G1_H2C_constants(Curves)
    h2c += '\n\n'
    h2c += genBLS12381G1_H2C_isogeny_map(Curves)

    with open(f'{curve.lower()}_hash_to_curve_g1.nim', 'w') as f:
      f.write(copyright())
      f.write('\n\n')

      f.write(inspect.cleandoc("""
          import
            constantine/named/algebra,
            constantine/math/io/io_fields
      """))

      f.write('\n\n')
      f.write(h2c)

    print(f'Successfully created {curve.lower()}_hash_to_curve_g1.nim')

  elif curve == 'BLS12_381' and group_or_iso == 'G2':
    h2c = genBLS12381G2_H2C_constants(Curves)
    h2c += '\n\n'
    h2c += genBLS12381G2_H2C_isogeny_map(Curves)

    with open(f'{curve.lower()}_hash_to_curve_g2.nim', 'w') as f:
      f.write(copyright())
      f.write('\n\n')

      f.write(inspect.cleandoc("""
          import
            constantine/named/algebra,
            constantine/math/io/[io_fields, io_extfields]
      """))

      f.write('\n\n')
      f.write(h2c)

    print(f'Successfully created {curve.lower()}_hash_to_curve_g2.nim')

  elif curve == 'BN254_Snarks' and group_or_iso == 'G1':
    p = Curves['BN254_Snarks']['field']['modulus']

    Z = GF(p)(1)
    h2c = genSVDW_H2C_G1_constants('BN254_Snarks', Curves, Z)

    with open(f'{curve.lower()}_hash_to_curve_g1.nim', 'w') as f:
      f.write(copyright())
      f.write('\n\n')

      f.write(inspect.cleandoc("""
          import
            constantine/named/algebra,
            constantine/math/io/io_fields
      """))

      f.write('\n\n')
      f.write(h2c)

    print(f'Successfully created {curve.lower()}_hash_to_curve_g1.nim')

  elif curve == 'BN254_Snarks' and group_or_iso == 'G2':
    p = Curves['BN254_Snarks']['field']['modulus']
    non_residue_fp = Curves['BN254_Snarks']['tower']['QNR_Fp']
    Fp = GF(p)
    K.<u> = PolynomialRing(Fp)
    Fp2.<beta> = Fp.extension(u^2 - non_residue_fp)

    Z = Fp2([0, 1])
    h2c = genSVDW_H2C_G2_constants('BN254_Snarks', Curves, Z)

    with open(f'{curve.lower()}_hash_to_curve_g2.nim', 'w') as f:
      f.write(copyright())
      f.write('\n\n')

      f.write(inspect.cleandoc("""
          import
            constantine/named/algebra,
            constantine/math/io/[io_fields, io_extfields]
      """))

      f.write('\n\n')
      f.write(h2c)

    print(f'Successfully created {curve.lower()}_hash_to_curve_g2.nim')
  else:
    raise ValueError(
      curve + group_or_iso +
      ' is not configured '
    )
