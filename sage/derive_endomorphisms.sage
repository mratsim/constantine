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
#             Endomorphism acceleration constants
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

def pretty_print_lattice(Lat):
  print('Lattice:')
  latHex = [['0x' + x.hex() if x >= 0 else '-0x' + (-x).hex() for x in vec] for vec in Lat]
  maxlen = max([len(cell) for row in latHex for cell in row])
  for row in latHex:
    row = ' '.join(cell.rjust(maxlen + 2) for cell in row)
    print(row)

def pretty_print_babai(Basis):
  print('Babai:')
  for i, v in enumerate(Basis):
    if v < 0:
      print(f'  𝛼\u0305{i}: -0x{Integer(int(-v)).hex()}')
    else:
      print(f'  𝛼\u0305{i}:  0x{Integer(int(v)).hex()}')

def derive_lattice(r, lambdaR, m):
  lat = Matrix(matrix.identity(m))
  lat[0, 0] = r
  for i in range(1, m):
     lat[i, 0] = -lambdaR^i

  return lat.LLL()

def derive_babai(r, lattice, m):
  basis = m * [0]
  basis[0] = r

  ahat = vector(basis) * lattice.inverse()
  v = int(r).bit_length()
  v = int(((v + 64 - 1) // 64) * 64)

  return [(a << v) // r for a in ahat]

# TODO: maximum infinity norm

# G1 Endomorphism
# ---------------------------------------------------------

def check_cubic_root_endo(G1, Fp, r, cofactor, lambdaR, phiP):
  ## Check the Endomorphism for p mod 3 == 1
  ## Endomorphism can be field multiplication by one of the non-trivial cube root of unity 𝜑
  ##   Rationale:
  ##     curve equation is y² = x³ + b, and y² = (x𝜑)³ + b <=> y² = x³ + b (with 𝜑³ == 1) so we are still on the curve
  ##     this means that multiplying by 𝜑 the x-coordinate is equivalent to a scalar multiplication by some λᵩ
  ##     with λᵩ² + λᵩ + 1 ≡ 0 (mod r) and 𝜑² + 𝜑 + 1 ≡ 0 (mod p), see below.
  ##     Hence we have a 2 dimensional decomposition of the scalar multiplication
  ##     i.e. For any [s]P, we can find a corresponding [k1]P + [k2][λᵩ]P with [λᵩ]P being a simple field multiplication by 𝜑
  ##   Finding cube roots:
  ##      x³−1=0 <=> (x−1)(x²+x+1) = 0, if x != 1, x solves (x²+x+1) = 0 <=> x = (-1±√3)/2

  assert phiP^3 == Fp(1)
  assert lambdaR^3 % r == 1

  Prand = G1.random_point()
  P = Prand * cofactor
  assert P != G1([0, 1, 0])

  (Px, Py, Pz) = P

  Qendo = G1([Px*phiP, Py, Pz])
  Qlambda = lambdaR * P

  assert P != Qendo
  assert P != Qlambda

  assert Qendo == Qlambda
  print('Endomorphism OK')

def genCubicRootEndo(curve_name, curve_config):
  p = curve_config[curve_name]['field']['modulus']
  r = curve_config[curve_name]['field']['order']
  b = curve_config[curve_name]['curve']['b']

  print('Constructing G1')
  Fp = GF(p)
  G1 = EllipticCurve(Fp, [0, b])
  print('Computing cofactor')
  cofactor = G1.order() // r
  print('cofactor: 0x' + Integer(cofactor).hex())

  # slow for large inputs - https://pari.math.u-bordeaux.fr/archives/pari-dev-0412/msg00020.html
  if curve_name != 'BW6_761':
    print('Finding cube roots')
    (phi1, phi2) = (Fp(root) for root in Fp(1).nth_root(3, all=True) if root != 1)
    (lambda1, lambda2) = (GF(r)(root) for root in GF(r)(1).nth_root(3, all=True) if root != 1)
  else:
    print('Skip finding cube roots for BW6_761, too slow, use values from paper https://eprint.iacr.org/2020/351')
    phi1 = Integer('0x531dc16c6ecd27aa846c61024e4cca6c1f31e53bd9603c2d17be416c5e4426ee4a737f73b6f952ab5e57926fa701848e0a235a0a398300c65759fc45183151f2f082d4dcb5e37cb6290012d96f8819c547ba8a4000002f962140000000002a')
    phi2 = Integer('0xcfca638f1500e327035cdf02acb2744d06e68545f7e64c256ab7ae14297a1a823132b971cdefc65870636cb60d217ff87fa59308c07a8fab8579e02ed3cddca5b093ed79b1c57b5fe3f89c11811c1e214983de300000535e7bc00000000060')
    lambda1 = Integer('0x9b3af05dd14f6ec619aaf7d34594aabc5ed1347970dec00452217cc900000008508c00000000001')
    lambda2 = Integer('-0x9b3af05dd14f6ec619aaf7d34594aabc5ed1347970dec00452217cc900000008508c00000000002')

  print('𝜑1 (mod p):  0x' + Integer(phi1).hex())
  print('λᵩ1 (mod r): 0x' + Integer(lambda1).hex())
  print('𝜑2 (mod p):  0x' + Integer(phi2).hex())
  print('λᵩ2 (mod r): 0x' + Integer(lambda2).hex())

  # TODO: is there a better way than spray-and-pray?
  # TODO: Should we maximize or minimize lambda
  #       to maximize/minimize the scalar norm?
  # TODO: Or is there a way to ensure
  #       that the Babai basis is mostly positive?
  if lambda1 < lambda2:
    lambda1, lambda2 = lambda2, lambda1

  try:
    check_cubic_root_endo(G1, Fp, r, cofactor, int(lambda1), phi1)
  except:
    print('Failure with:')
    print('  𝜑 (mod p): 0x' + Integer(phi1).hex())
    print('  λᵩ (mod r): 0x' + Integer(lambda1).hex())
    phi1, phi2 = phi2, phi1
    check_cubic_root_endo(G1, Fp, r, cofactor, int(lambda1), phi1)
  finally:
    print('Success with:')
    print('  𝜑 (mod p):  0x' + Integer(phi1).hex())
    print('  λᵩ (mod r): 0x' + Integer(lambda1).hex())

  print('Deriving Lattice')
  lattice = derive_lattice(r, lambda1, 2)
  pretty_print_lattice(lattice)

  print('Deriving Babai basis')
  babai = derive_babai(r, lattice, 2)
  pretty_print_babai(babai)

  return phi1, lattice, babai

# 𝔾₂ Endomorphism
# ---------------------------------------------------------

def genPsiEndo(curve_name, curve_config):
  t = curve_config[curve_name]['field']['trace']
  r = curve_config[curve_name]['field']['order']
  k = curve_config[curve_name]['tower']['embedding_degree']

  # Decomposition factor depends on the embedding degree
  m = CyclotomicField(k).degree()
  # λψ is the trace of Frobenius - 1
  lambda_psi = t - 1

  print('Deriving Lattice')
  lattice = derive_lattice(r, lambda_psi, m)
  pretty_print_lattice(lattice)

  print('Deriving Babai basis')
  babai = derive_babai(r, lattice, m)
  pretty_print_babai(babai)

  return lattice, babai

# Dump
# ---------------------------------------------------------

def dumpLattice(lattice):
  result = '  # (BigInt, isNeg)\n'
  lastRow = lattice.nrows() - 1
  lastCol = lattice.ncols() - 1

  for rowID, row in enumerate(lattice):
    for colID, val in enumerate(row):
      result += '  '
      result += '(' if colID == 0 else ' '
      result += f'(BigInt[{max(1, int(abs(val)).bit_length())}].fromHex"0x{Integer(int(abs(val))).hex()}", '
      result += ('false' if val >= 0 else 'true') + ')'
      result += ')' if colID == lastCol else ''
      result += ',\n' if (rowID != lastRow or colID != lastCol) else '\n'

  return result

def dumpBabai(vec):
  result = '  # (BigInt, isNeg)\n'
  lastRow = len(vec) - 1

  for rowID, val in enumerate(vec):
    result += '  '
    result += f'(BigInt[{max(1, int(abs(val)).bit_length())}].fromHex"0x{Integer(int(abs(val))).hex()}", '
    result += ('false' if val >= 0 else 'true') + ')'
    result += ',\n' if rowID != lastRow else '\n'

  return result

def dumpConst(name, inner):
  result = f'const {name}* = (\n'
  result += inner
  result += ')\n'

  return result

# CLI
# ---------------------------------------------------------

if __name__ == "__main__":
  # Usage
  # BLS12-381
  # sage sage/derive_endomorphisms.sage BLS12_381

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
    print('\nPrecomputing G1 - 𝜑 (phi) cubic root endomorphism')
    print('----------------------------------------------------\n')
    cubeRootModP, g1lat, g1babai = genCubicRootEndo(curve, Curves)

    hasG2 = 'tower' in Curves[curve]

    if hasG2:
        print('\n\nPrecomputing 𝔾₂ - ψ (Psi) - untwist-Frobenius-twist endomorphism')
        print('----------------------------------------------------\n')
        g2lat, g2babai = genPsiEndo(curve, Curves)

    with open(f'{curve.lower()}_endomorphisms.nim', 'w') as f:
      f.write(copyright())
      f.write('\n\n')
      f.write(inspect.cleandoc(f"""
        import
          constantine/named/algebras,
          constantine/math/io/[io_bigints, io_fields]

        # {curve} G1
        # ------------------------------------------------------------
      """))
      f.write('\n\n')
      f.write(inspect.cleandoc(f"""
        const {curve}_cubicRootOfUnity_mod_p* =
          Fp[{curve}].fromHex"0x{Integer(cubeRootModP).hex()}"
      """))
      f.write('\n\n')
      f.write(dumpConst(
        f'{curve}_Lattice_G1',
        dumpLattice(g1lat)
      ))
      f.write('\n')
      f.write(dumpConst(
        f'{curve}_Babai_G1',
        dumpBabai(g1babai)
      ))
      f.write('\n')
      if hasG2:
        f.write('\n')
        f.write(inspect.cleandoc(f"""
            # {curve} 𝔾₂
            # ------------------------------------------------------------
        """))
        f.write('\n\n')
        f.write(dumpConst(
            f'{curve}_Lattice_G2',
            dumpLattice(g2lat)
        ))
        f.write('\n')
        f.write(dumpConst(
            f'{curve}_Babai_G2',
            dumpBabai(g2babai)
        ))
        f.write('\n')
