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

# Roots of unity
# ---------------------------------------------------------

def gen_pow2_roots_of_unity(field, num_powers):
  """
  Generate the 2^i'th roots of unity
  with i in [0, num_powers)
  """

  # Find a primitive root of the finite field of modulus q
  # i.e. root^k != 1 for all k < q-1 so powers of root generate the field.
  # https://crypto.stanford.edu/pbc/notes/numbertheory/gen.html
  #
  # Usage, see ω usagefor polynomials in evaluation form:
  # https://dankradfeist.de/ethereum/2021/06/18/pcs-multiproofs.html
  primitive_root = field.multiplicative_generator()

  assert primitive_root == 7, (
    'The ref implementation c-kzg-4844 uses 7.'
    + ' Any primitive root is correct but the order of coefficients '
    + ' won\'t be the same which makes debugging harder.'
  )

  return [primitive_root^((field.characteristic()-1)//(1 << i)) for i in range(num_powers)]

# Dump
# ---------------------------------------------------------

def dumpConst(name, inner):
  result = f'const {name}* = (\n'
  result += inner
  result += ')\n'

  return result

def dumpRoots(vec):
  result = f'  # primitive_root⁽ᵐᵒᵈᵘˡᵘˢ⁻¹⁾/⁽²^ⁱ⁾ for i in [0, {len(vec)})\n'
  lastRow = len(vec) - 1

  for rowID, val in enumerate(vec):
    result += '  '
    result += f'BigInt[{max(1, int(val).bit_length())}].fromHex"0x{Integer(int(val)).hex()}"'
    result += ',\n' if rowID != lastRow else '\n'

  return result

# CLI
# ---------------------------------------------------------

if __name__ == "__main__":

  with open(f'ethereum_kzg_constants.nim', 'w') as f:

    f.write(copyright())
    f.write('\n\n')
    f.write(inspect.cleandoc(f"""
      import
        constantine/named/algebra,
        constantine/math/io/io_bigints

      # Roots of unity
      # ------------------------------------------------------------
    """))
    f.write('\n\n')

    r = Curves['BLS12_381']['field']['order']
    Fr = GF(r)
    f.write(dumpConst(
      'ctt_eth_kzg_bls12_381_fr_pow2_roots_of_unity',
      dumpRoots(gen_pow2_roots_of_unity(Fr, 32))
    ))
    f.write('\n\n')
