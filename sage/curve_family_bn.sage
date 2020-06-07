# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                    BN Curves parameters
#                  (Barreto-Naehrig curves)
#
# ############################################################
#
# This module derives a BN curve parameters from
# its base parameter u

def compute_curve_characteristic(u_str):
  u = sage_eval(u_str)
  p = 36*u^4 + 36*u^3 + 24*u^2 + 6*u + 1
  r = 36*u^4 + 36*u^3 + 18*u^2 + 6*u + 1

  print(f'BN family - {p.nbits()} bits')
  print('  Prime modulus:     0x' + p.hex())
  print('  Curve order:       0x' + r.hex())
  print('  Parameter u:       ' + u_str)
  if u < 0:
      print('  Parameter u (hex): -0x' + (-u).hex())
  else:
      print('  Parameter u (hex):  0x' + u.hex())

  print(f'  p mod 3:           ' + str(p % 3))
  print(f'  p mod 4:           ' + str(p % 4))
  print(f'  p mod 8:           ' + str(p % 8))
  print(f'  p mod 12:          ' + str(p % 12))
  print(f'  p mod 16:          ' + str(p % 16))

  print(f'  cube roots of unity: ' + str(['0x' + Integer(root).hex() for root in GF(p)(1).nth_root(3, all=True)]))

if __name__ == "__main__":
  # Usage
  # sage sage/curve_family_bn.sage '-(2^62 + 2^55 + 1)'
  # sage sage/curve_family_bn.sage 4965661367192848881

  from argparse import ArgumentParser

  parser = ArgumentParser()
  parser.add_argument("curve_param",nargs="+")
  args = parser.parse_args()

  compute_curve_characteristic(args.curve_param[0])
