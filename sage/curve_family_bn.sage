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

if __name__ == "__main__":
  # Usage
  # sage sage/curve_family_bn.sage '-(2^62 + 2^55 + 1)'

  from argparse import ArgumentParser

  parser = ArgumentParser()
  parser.add_argument("curve_param",nargs="+")
  args = parser.parse_args()

  compute_curve_characteristic(args.curve_param[0])
