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

# Utilities - Reinventing the wheel
# ---------------------------------------------------------
# Trying to import derive_endomorphisms lead to exception because the sage "load('foo.sage')"
# does not respect __name__ == __main__ check.
#
# So we redo the utilities


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

# Bandersnatch / Banderwagon
# ---------------------------------------------------------

r = Integer('0x1cfb69d4ca675f520cce760202687600ff8f87007419047174fd06b52876e7e1')
Fr = GF(r)

sol = [Integer(root) for root in Fr(-2).nth_root(2, all=True) if root != 1]

# Paper: https://eprint.iacr.org/2021/1152.pdf
#  - https://ethresear.ch/t/introducing-bandersnatch-a-fast-elliptic-curve-built-over-the-bls12-381-scalar-field/9957
#  - https://github.com/asanso/Bandersnatch/
L = Integer('0x13b4f3dc4a39a493edf849562b38c72bcfc49db970a5056ed13d21408783df05')
assert L in sol

print('Deriving Lattice')
lattice = derive_lattice(r, L, 2)
pretty_print_lattice(lattice)

print('Deriving Babai basis')
babai = derive_babai(r, L, 2)
pretty_print_babai(babai)


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

# Output
# ---------------------------------------------------------
#
print("""
Note the endomorphism must also be implemented
and is with Twisted Edwards cordinates:
ψ(x, y, z) = (f(y)g(y), g(y)xy, h(y)xy)
with f(y) = c(z² - y²)
     g(y) = b(y² + bz²)
     h(y) = y² - bz²

  b = 0x52c9f28b828426a561f00d3a63511a882ea712770d9af4d6ee0f014d172510b4
  c = 0x6cc624cf865457c3a97c6efd6c17d1078456abcfff36f4e9515c806cdf650b3d
""")
with open(f'bandersnatch_endomorphisms.nim', 'w') as f:
    f.write(copyright())
    f.write('\n\n')
    f.write(inspect.cleandoc(f"""
    import
        ../config/curves,
        ../io/[io_bigints, io_fields]

    # Bandersnatch
    # ------------------------------------------------------------
    """))

    f.write('\n\n')
    f.write(dumpConst(
    f'Bandersnatch_Lattice_G1',
    dumpLattice(lattice)
    ))
    f.write('\n')
    f.write(dumpConst(
    f'Bandersnatch_Babai_G1',
    dumpBabai(babai)
    ))
