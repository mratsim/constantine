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
#                  Curves configuration
#
# ############################################################

import inspect

# Accelerate arithmetic by accepting probabilistic proofs
from sage.structure.proof.all import arithmetic
arithmetic(False)

def derive_BN_field(x):
  params = {
    'param': x,
    'modulus': 36*x^4 + 36*x^3 + 24*x^2 + 6*x + 1,
    'order': 36*x^4 + 36*x^3 + 18*x^2 + 6*x + 1,
    'trace': 6*x^2 + 1,
    'family': 'BN'
  }
  return params

def derive_BLS12_field(x):
  params = {
    'param': x,
    'modulus': (x - 1)^2 * (x^4 - x^2 + 1)//3 + x,
    'order': x^4 - x^2 + 1,
    'trace': x + 1,
    'family': 'BLS12'
  }
  return params

def derive_BW6_compose_BLS12_field(x, cofactor_trace, cofactor_y):
  # Brezing-Weng input
  r = (x^6 - 2*x^5 + 2*x^3 + x + 1) // 3 # BLS12 modulus

  # 6-th root of unity output + cofactors
  t = x^5 - 3*x^4 + 3*x^3 - x + 3 + cofactor_trace*r
  y = (x^5 - 3*x^4 + 3*x^3 - x + 3)//3 + cofactor_y*r

  # Curve parameters
  p = (t^2 + 3*y^2)/4
  trace = p+1-r # (3*y+t)/2

  params = {
    'param': x,
    'modulus': p,
    'order': r,
    'trace': trace,
    'family': 'BW6'
  }
  return params

def copyright():
  return inspect.cleandoc("""
    # Constantine
    # Copyright (c) 2018-2019    Status Research & Development GmbH
    # Copyright (c) 2020-Present Mamy André-Ratsimbazafy
    # Licensed and distributed under either of
    #   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
    #   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
    # at your option. This file may not be copied, modified, or distributed except according to those terms.
  """)

Curves = {
  'BN254_Nogami': {
    'field': derive_BN_field(-(2^62 + 2^55 + 1)),
    'curve': {
      'form': 'short_weierstrass',
      'a': 0,
      'b': 2
    },
    'tower': {
      'embedding_degree': 12,
      'twist_degree': 6,
      'QNR_Fp': -1,
      'SNR_Fp2': [1, 1],
      'twist': 'D_Twist'
    }
  },
  'BN254_Snarks': {
    'field': derive_BN_field(Integer('0x44e992b44a6909f1')),
    'curve': {
      'form': 'short_weierstrass',
      'a': 0,
      'b': 3
    },
    'tower': {
      'embedding_degree': 12,
      'twist_degree': 6,
      'QNR_Fp': -1,
      'SNR_Fp2': [9, 1],
      'twist': 'D_Twist'
    }
  },
  'BLS12_377': {
    'field': derive_BLS12_field(3 * 2^46 * (7 * 13 * 499) + 1),
    'curve': {
      'form': 'short_weierstrass',
      'a': 0,
      'b': 1
    },
    'tower': {
      'embedding_degree': 12,
      'twist_degree': 6,
      'QNR_Fp': -5,
      'SNR_Fp2': [0, 1],
      'twist': 'D_Twist'
    }
  },
  'BLS12_381': {
    'field': derive_BLS12_field(-(2^63 + 2^62 + 2^60 + 2^57 + 2^48 + 2^16)),
    'curve': {
      'form': 'short_weierstrass',
      'a': 0,
      'b': 4
    },
    'tower': {
      'embedding_degree': 12,
      'twist_degree': 6,
      'QNR_Fp': -1,
      'SNR_Fp2': [1, 1],
      'twist': 'M_Twist'
    }
  },
  'BW6_761': {
    'field': derive_BW6_compose_BLS12_field(
        3 * 2^46 * (7 * 13 * 499) + 1,
        cofactor_trace = 13,
        cofactor_y = 9
    ),
    'curve': {
      'form': 'short_weierstrass',
      'a': 0,
      'b': -1
    },
    'tower': {
      'embedding_degree': 6,
      'twist_degree': 6,
      'SNR_Fp': -4,
      'twist': 'M_Twist'
    }
  },
  'Pallas': {
    'field': {
      'modulus': Integer('0x40000000000000000000000000000000224698fc094cf91b992d30ed00000001'),
      'order': Integer('0x40000000000000000000000000000000224698fc0994a8dd8c46eb2100000001')
    },
    'curve': {
      'form': 'short_weierstrass',
      'a': 0,
      'b': 5
    }
  },
  'Vesta': {
    'field': {
      'modulus':  Integer('0x40000000000000000000000000000000224698fc0994a8dd8c46eb2100000001'),
      'order': Integer('0x40000000000000000000000000000000224698fc094cf91b992d30ed00000001'),
    },
    'curve': {
      'form': 'short_weierstrass',
      'a': 0,
      'b': 5
    }
  },
  'Secp256k1': {
    'field': {
      'modulus':  Integer('0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f'),
      'order': Integer('0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141'),
    },
    'curve': {
      'form': 'short_weierstrass',
      'a': 0,
      'b': 7
    }
  },
}
