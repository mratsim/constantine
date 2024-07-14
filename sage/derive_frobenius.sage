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
  else:
    SNR_Fp = curve_config[curve_name]['tower']['SNR_Fp']
    Fp2.<beta> = Fp.extension(u^2 - SNR_Fp)

  if g2field == 'Fp2':
    SNR = curve_config[curve_name]['tower']['SNR_Fp2']
    SNR = Fp2(SNR)
  else:
    # To build the Fp6 extension, since we use a SexticNonResidue
    # to build Fp2, we can reuse it as a cubic non-residue
    # It always has [0, 1] coordinates in Fp2
    SNR = Fp2([0, 1])

  halfK = embdeg//2

  print('\n----> Frobenius extension field constants <----\n')
  buf = inspect.cleandoc(f"""
      # Frobenius map - on extension fields
      # -----------------------------------------------------------------

      # We start from base frobenius constant for a {embdeg} embedding degree.
      # with
      # - a sextic twist, SNR being the Sextic Non-Residue.
      # - coef being the Frobenius coefficient "ID"
      # c = SNR^((p-1)/{halfK})^coef
      #
      # On Fp2 frobenius(c) = conj(c) so we have
      # For n=2, with n the number of Frobenius applications
      # c2 = c * (c^p) = c * frobenius(c) = c * conj(c)
      # c2 = (SNR * conj(SNR))^((p-1)/{halfK})^coef)
      # c2 = (norm(SNR))^((p-1)/{halfK})^coef)
      # For k=3
      # c3 = c * c2^p = c * frobenius(c2) = c * conj(c2)
      # with conj(norm(SNR)) = norm(SNR) as a norm is strictly on the base field.
      # c3 = (SNR * norm(SNR))^((p-1)/{halfK})^coef)
      #
      # A more generic formula can be derived by observing that
      # c3 = c * c2^p = c * (c * c^p)^p
      # c3 = c * c^p * c^p²
      # with 4, we have
      # c4 = c * c3^p = c * (c * c^p * c^p²)^p
      # c4 = c * c^p * c^p² * c^p³
      # with n we have
      # cn = c * c^p * c^p² ... * c^p^(n-1)
      # cn = c^(1+p+p² + ... + p^(n-1))
      # This is the sum of first n terms of a geometric series
      # hence cn = c^((p^n-1)/(p-1))
      # We now expand c
      # cn = SNR^((p-1)/{halfK})^coef^((p^n-1)/(p-1))
      # cn = SNR^((p^n-1)/{halfK})^coef
      # cn = SNR^(coef * (p^n-1)/{halfK})

      const {curve_name}_FrobeniusMapCoefficients* = [
  """)

  arr = ""
  maxN = 3 # We only need up to f^(p^3) in final exponentiation

  for n in range(1, maxN + 1):
    for coef in range(halfK):
      if coef == 0:
        arr += f'\n# frobenius({n}) -----------------------\n'
        arr += '['
      frobmapcoef = SNR^(coef*((p^n-1)/halfK))
      hatN = '^' + str(n) if n>1 else ''
      arr += field_to_nim(frobmapcoef, 'Fp2', curve_name, comment_right = f'SNR^((p{hatN}-1)/{halfK})^{coef}')
      if coef != halfK - 1:
        arr += ',\n'
    arr += '],\n'

  buf += textwrap.indent(arr, '  ')
  buf += ']'
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

  if g2field == 'Fp2':
    SNR = curve_config[curve_name]['tower']['SNR_Fp2']
    SNR = Fp2(SNR)
  else:
    SNR = curve_config[curve_name]['tower']['SNR_Fp']
    SNR = Fp(SNR)

  print('\n----> ψ (Psi) - Untwist-Frobenius-Twist Endomorphism constants <----\n')
  buf = inspect.cleandoc(f"""
      # ψ (Psi) - Untwist-Frobenius-Twist Endomorphisms on twisted curves
      # -----------------------------------------------------------------
  """)
  buf += '\n'
  if twkind == 'D_Twist':
    buf += f'# {curve_name} is a D-Twist: psi1_coef1 = SNR^((p-1)/{twdeg})\n\n'
    xi = SNR
    snrUsed = 'SNR'
  else:
    buf += f'# {curve_name} is a M-Twist: psi1_coef1 = (1/SNR)^((p-1)/{twdeg})\n\n'
    xi = 1/SNR
    snrUsed = '(1/SNR)'

  maxPsi = CyclotomicField(embdeg).degree()

  for n in range(1, maxPsi+1):
    for coef in range(2, 3+1):
      # Same formula as FrobeniusMap constants
      # except that
      # - we only need 2 coefs for elliptic curve twists
      # - xi = SNR or 1/SNR depending on D-Twist or M-Twist respectively
      # - the divisor is the twist degree isntead of half the embedding degree
      frobpsicoef = xi^(coef*(p^n - 1)/twdeg)
      hatN = '^' + str(n) if n>1 else ''
      buf += field_to_nim(
        frobpsicoef, g2field, curve_name,
        prefix = f'const {curve_name}_FrobeniusPsi_psi{n}_coef{coef}* = ',
        comment_above = f'{snrUsed}^({coef}(p{hatN}-1)/{twdeg})'
      ) + '\n'

  buf += '\n'

  buf += inspect.cleandoc(f"""
    # For a sextic twist
    # - p ≡ 1 (mod 2)
    # - p ≡ 1 (mod 3)
    #
    # psi2_coef3 is always -1 (mod p^m) with m = embdeg/twdeg
    # Recap, with ξ (xi) the sextic non-residue for D-Twist or 1/SNR for M-Twist
    # psi_2 ≡ ξ^((p-1)/6)^2 ≡ ξ^((p-1)/3)
    # psi_3 ≡ psi_2 * ξ^((p-1)/6) ≡ ξ^((p-1)/3) * ξ^((p-1)/6) ≡ ξ^((p-1)/2)
    #
    # In Fp² (i.e. embedding degree of 12, 𝔾₂ on Fp2)
    # - quadratic non-residues respect the equation a^((p²-1)/2) ≡ -1 (mod p²) by the Legendre symbol
    # - sextic non-residues are also quadratic non-residues so ξ^((p²-1)/2) ≡ -1 (mod p²)
    # - QRT(1/a) = QRT(a) with QRT the quadratic residuosity test
    #
    # We have psi2_3 ≡ psi_3 * psi_3^p ≡ psi_3^(p+1)
    #                ≡ (ξ^(p-1)/2)^(p+1) (mod p²)
    #                ≡ ξ^((p-1)(p+1)/2) (mod p²)
    #                ≡ ξ^((p²-1)/2) (mod p²)
    # And ξ^((p²-1)/2) ≡ -1 (mod p²) since ξ is a quadratic non-residue
    # So psi2_3 ≡ -1 (mod p²)
    #
    #
    # In Fp (i.e. embedding degree of 6, 𝔾₂ on Fp)
    # - Fermat's Little Theorem gives us a^(p-1) ≡ 1 (mod p)
    #
    # psi2_3 ≡ ξ^((p-1)(p+1)/2) (mod p)
    #        ≡ ξ^((p+1)/2)^(p-1) (mod p) as we have 2|p+1
    #        ≡ 1 (mod p) by Fermat's Little Theorem
  """)

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
    trace = Curves[curve]['field']['trace']
    print(f'trace of Frobenius ({int(trace).bit_length()}-bit): 0x{Integer(trace).hex()}')

    FrobMap = genFrobeniusMapConstants(curve, Curves)
    FrobPsi = genFrobeniusPsiConstants(curve, Curves)

    with open(f'{curve.lower()}_frobenius.nim', 'w') as f:
      f.write(copyright())
      f.write('\n\n')

      embdeg = Curves[curve]['tower']['embedding_degree']
      twdeg = Curves[curve]['tower']['twist_degree']

      if embdeg//twdeg >= 2:
        f.write(inspect.cleandoc("""
          import
            constantine/named/algebra,
            constantine/math/extension_fields,
            constantine/math/io/io_extfields
        """))
      else:
        f.write(inspect.cleandoc("""
          import
            constantine/named/algebra,
            constantine/math/extension_fields,
            constantine/math/io/[io_fields, io_extfields]
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
