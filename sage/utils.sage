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
#                  Utilities
#
# ############################################################

import inspect

# Accelerate arithmetic by accepting probabilistic proofs
from sage.structure.proof.all import arithmetic
arithmetic(False)

# Display Utilities
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

# Conversion Utilities
# ---------------------------------------------------------

def serialize_bigint(x):
  return '0x' + Integer(x).hex()

# Curve Utilities
# ---------------------------------------------------------

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


