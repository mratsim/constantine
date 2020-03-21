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

if __name__ == "__main__":
  # Usage
  # sage '-(2^63 + 2^62 + 2^60 + 2^57 + 2^48 + 2^16)'

  from argparse import ArgumentParser

  parser = ArgumentParser()
  parser.add_argument("curve_param",nargs="+")
  args = parser.parse_args()

  compute_curve_characteristic(args.curve_param[0])
