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
  }
}
