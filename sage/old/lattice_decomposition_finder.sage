# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                  Lattice decomposition finder
#
# ############################################################

# Example of BLS12-381 with the ψ (Psi) - Untwist-Frobenius-Twist endomorphism
x = -(2^63 + 2^62 + 2^60 + 2^57 + 2^48 + 2^16)
p = (x - 1)^2 * (x^4 - x^2 + 1)//3 + x
r = x^4 - x^2 + 1
t = x + 1 # Trace of Frobenius

lambda_psi = t - 1

Lpsi = Matrix([
    [          r,   0, 0, 0],
    [-lambda_psi,   1, 0, 0],
    [-lambda_psi^2, 0, 1, 0],
    [-lambda_psi^3, 0, 0, 1],
])

Lpsi = Lpsi.LLL()
print(Lpsi)

ahat = vector([r, 0, 0, 0]) * Lpsi.inverse()
print('ahat: ' + str(ahat))

v = int(r).bit_length()
v = int(((v + 64 - 1) // 64) * 64)
print([(a << v) // r for a in ahat])
