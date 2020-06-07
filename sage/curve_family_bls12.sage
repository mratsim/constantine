# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                    BLS12 Curves parameters
#       (Barreto-Lynn-Scott with embedding degree of 12)
#
# ############################################################
#
# This module derives a BLS12 curve parameters from
# its base parameter u

def compute_curve_characteristic(u_str):
  u = sage_eval(u_str)
  p = (u - 1)^2 * (u^4 - u^2 + 1)//3 + u
  r = u^4 - u^2 + 1

  print(f'BLS12 family - {p.nbits()} bits')
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

  print()

  print(f'  Endomorphism-based acceleration when p mod 3 == 1')
  print(f'    Endomorphism can be field multiplication by one of the non-trivial cube root of unity 𝜑')
  print(f'      Rationale:')
  print(f'        curve equation is y² = x³ + b, and y² = (x𝜑)³ + b <=> y² = x³ + b (with 𝜑³ == 1) so we are still on the curve')
  print(f'        this means that multiplying by 𝜑 the x-coordinate is equivalent to a scalar multiplication by some λᵩ')
  print(f'        with λᵩ² + λᵩ + 1 ≡ 0 (mod CurveOrder), see below. Hence we have a 2 dimensional decomposition of the scalar multiplication')
  print(f'        i.e. For any [s]P, we can find a corresponding [k1]P + [k2][λᵩ]P with [λᵩ]P being a simple field multiplication by 𝜑')
  print(f'      Finding cube roots:')
  print(f'         x³−1=0 <=> (x−1)(x²+x+1) = 0, if x != 1, x solves (x²+x+1) = 0 <=> x = (-1±√3)/2')
  print(f'         cube roots of unity: ' + str(['0x' + Integer(root).hex() for root in GF(p)(1).nth_root(3, all=True)]))
  print(f'    GLV-2 decomposition of s into (k1, k2) on G1')
  print(f'      (k1, k2) = (s, 0) - 𝛼1 b1 - 𝛼2 b2')
  print(f'      𝛼i = 𝛼\u0302i * s / r')
  print(f'        Lattice b1: ' + str(['0x' + b.hex() for b in [u^2-1, -1]]))
  print(f'        Lattice b2: ' + str(['0x' + b.hex() for b in [1, u^2]]))

  # Babai rounding
  ahat1 = 2*u+1
  ahat2 = 6*u^2+4*u+1
  # We want a1 = ahat1 * s/r with m = 2 (for a 2-dim decomposition) and r the curve order
  # To handle rounding errors we instead multiply by
  # 𝜈 = (2^WordBitWidth)^w (i.e. the same as the R magic constant for Montgomery arithmetic)
  # with 𝜈 > r and w minimal so that 𝜈 > r
  # a1 = ahat1*𝜈/r * s/𝜈
  v = int(r).bit_length()
  print(f'      r.bit_length(): {v}')
  v = int(((v + 64 - 1) // 64) * 64) # round to next multiple of 64
  print(f'      𝜈 > r, 𝜈: 2^{v}')
  print(f'      Babai roundings')
  print(f'        𝛼\u03021: ' + '0x' + ahat1.hex())
  print(f'        𝛼\u03022: ' + '0x' + ahat2.hex())
  print(f'      Handle rounding errors')
  print(f'        𝛼1 = 𝛼\u03021 * s / r with 𝛼1 = (𝛼\u03021 * 𝜈/r) * s/𝜈')
  print(f'        𝛼2 = 𝛼\u03022 * s / r with 𝛼2 = (𝛼\u03022 * 𝜈/r) * s/𝜈')
  print(f'        -----------------------------------------------------')
  l1 = Integer(ahat1 << v) // r
  l2 = Integer(ahat2 << v) // r
  print(f'        𝛼1 = (0x{l1.hex()} * s) >> {v}')
  print(f'        𝛼2 = (0x{l2.hex()} * s) >> {v}')

if __name__ == "__main__":
  # Usage
  # sage sage/curve_family_bls12.sage '-(2^63 + 2^62 + 2^60 + 2^57 + 2^48 + 2^16)'

  from argparse import ArgumentParser

  parser = ArgumentParser()
  parser.add_argument("curve_param",nargs="+")
  args = parser.parse_args()

  compute_curve_characteristic(args.curve_param[0])
