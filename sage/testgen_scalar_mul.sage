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
#            Scalar multiplication test generator
#
# ############################################################

# Imports
# ---------------------------------------------------------

import os, json
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

def progressbar(it, prefix="", size=60, file=sys.stdout):
  count = len(it)
  def show(j):
    x = int(size*j/count)
    file.write("%s[%s%s] %i/%i\r" % (prefix, "#"*x, "."*(size-x), j, count))
    file.flush()
  show(0)
  for i, item in enumerate(it):
    yield item
    show(i+1)
  file.write("\n")
  file.flush()

def serialize_bigint(x):
  return '0x' + Integer(x).hex()

def serialize_EC_Fp(P):
  (Px, Py, Pz) = P
  coords = {
    'x': serialize_bigint(Px),
    'y': serialize_bigint(Py)
  }
  return coords

def serialize_EC_Fp2(P):
  (Px, Py, Pz) = P
  Px = vector(Px)
  Py = vector(Py)
  coords = {
    'x': {
      'c0': serialize_bigint(Px[0]),
      'c1': serialize_bigint(Px[1])
    },
    'y': {
      'c0': serialize_bigint(Py[0]),
      'c1': serialize_bigint(Py[1])
    }
  }
  return coords

# Generator
# ---------------------------------------------------------

def genScalarMulG1(curve_name, curve_config, count, seed, scalarBits = None):
  p = curve_config[curve_name]['field']['modulus']
  r = curve_config[curve_name]['field']['order']
  form = curve_config[curve_name]['curve']['form']
  a = curve_config[curve_name]['curve']['a']
  b = curve_config[curve_name]['curve']['b']

  Fp = GF(p)
  G1 = EllipticCurve(Fp, [0, b])
  cofactor = G1.order() // r

  out = {
    'curve': curve_name,
    'group': 'G1',
    'modulus': serialize_bigint(p),
    'order': serialize_bigint(r),
    'cofactor': serialize_bigint(cofactor),
    'form': form
  }
  if form == 'short_weierstrass':
    out['a'] = serialize_bigint(a)
    out['b'] = serialize_bigint(b)

  vectors = []
  set_random_seed(seed)
  for i in progressbar(range(count)):
    v = {}
    P = G1.random_point()
    scalar = randrange(1 << scalarBits) if scalarBits else randrange(r)

    P *= cofactor # clear cofactor
    Q = scalar * P

    v['id'] = i
    v['P'] = serialize_EC_Fp(P)
    v['scalarBits'] = scalarBits if scalarBits else r.bit_length()
    v['scalar'] = serialize_bigint(scalar)
    v['Q'] = serialize_EC_Fp(Q)
    vectors.append(v)

  out['vectors'] = vectors
  return out

def genScalarMulG2(curve_name, curve_config, count, seed, scalarBits = None):
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
    G2 = EllipticCurve(G2F, [0, b/G2F(non_residue_twist)])
  elif twist == 'M_Twist':
    G2 = EllipticCurve(G2F, [0, b*G2F(non_residue_twist)])
  else:
    raise ValueError('G2 must be a D_Twist or M_Twist but found ' + twist)

  cofactor = G2.order() // r

  out = {
    'curve': curve_name,
    'group': 'G2',
    'modulus': serialize_bigint(p),
    'order': serialize_bigint(r),
    'cofactor': serialize_bigint(cofactor),
    'form': form,
    'twist_degree': int(twist_degree),
    'twist': twist,
    'non_residue_fp': int(non_residue_fp),
    'G2_field': G2_field,
    'non_residue_twist': [int(coord) for coord in non_residue_twist] if isinstance(non_residue_twist, list) else int(non_residue_twist)
  }
  if form == 'short_weierstrass':
    out['a'] = serialize_bigint(a)
    out['b'] = serialize_bigint(b)

  vectors = []
  set_random_seed(seed)
  for i in progressbar(range(count)):
      v = {}
      P = G2.random_point()
      scalar = randrange(1 << scalarBits) if scalarBits else randrange(r)

      P *= cofactor # clear cofactor
      Q = scalar * P

      v['id'] = i
      if G2_field == 'Fp2':
        v['P'] = serialize_EC_Fp2(P)
        v['scalarBits'] = scalarBits if scalarBits else r.bit_length()
        v['scalar'] = serialize_bigint(scalar)
        v['Q'] = serialize_EC_Fp2(Q)
      elif G2_field == 'Fp':
        v['P'] = serialize_EC_Fp(P)
        v['scalarBits'] = scalarBits if scalarBits else r.bit_length()
        v['scalar'] = serialize_bigint(scalar)
        v['Q'] = serialize_EC_Fp(Q)
      vectors.append(v)

  out['vectors'] = vectors
  return out

# CLI
# ---------------------------------------------------------

if __name__ == "__main__":
  # Usage
  # BLS12-381
  # sage sage/testgen_scalar_mul.sage BLS12_381 G1 {scalarBits: optional int}

  from argparse import ArgumentParser

  parser = ArgumentParser()
  parser.add_argument("curve",nargs="+")
  args = parser.parse_args()

  curve = args.curve[0]
  group = args.curve[1]
  scalarBits = None
  if len(args.curve) > 2:
    scalarBits = int(args.curve[2])

  if curve not in Curves:
    raise ValueError(
      curve +
      ' is not one of the available curves: ' +
      str(Curves.keys())
    )
  elif group not in ['G1', 'G2']:
    raise ValueError(
      group +
      ' is not a valid group, expected G1 or G2 instead'
    )
  else:
    bits = scalarBits if scalarBits else Curves[curve]['field']['order'].bit_length()
    print(f'\nGenerating test vectors tv_{curve}_scalar_mul_{group}_{bits}bit.json')
    print('----------------------------------------------------\n')

    count = 40
    seed = 1337

    if group == 'G1':
      out = genScalarMulG1(curve, Curves, count, seed, scalarBits)
    elif group == 'G2':
      out = genScalarMulG2(curve, Curves, count, seed, scalarBits)

    with open(f'tv_{curve}_scalar_mul_{group}_{bits}bit.json', 'w') as f:
      json.dump(out, f, indent=2)
