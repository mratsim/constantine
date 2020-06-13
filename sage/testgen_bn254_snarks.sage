# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                    BN254 test generator
#
# ############################################################

# Parameters
u = Integer('0x44E992B44A6909F1')
p = 36*u^4 + 36*u^3 + 24*u^2 + 6*u + 1
r = 36*u^4 + 36*u^3 + 18*u^2 + 6*u + 1
cofactor = 1

# Finite fields
F       = GF(p)
K2.<u>  = PolynomialRing(F)
# F2.<beta>  = F.extension(u^2+9)
# K6.<v>  = PolynomialRing(F2)
# F6.<eta>  = F2.extension(v^3-beta)
# K12.<w> = PolynomialRing(F6)
# K12.<gamma> = F6.extension(w^2-eta)

# Curves
b = 3
G1 = EllipticCurve(F, [0, b])
# G2 = EllipticCurve(F2, [0, b/beta])

# Test generator
set_random_seed(1337)

for i in range(10):
    print('---------------------------------------')
    P = G1.random_point()
    (Px, Py, Pz) = P
    print('Px: ' + Integer(Px).hex())
    print('Py: ' + Integer(Py).hex())
    print('Pz: ' + Integer(Pz).hex())
    exponent = randrange(r) # Pick an integer below curve order
    print('scalar: ' + Integer(exponent).hex())

    Q = exponent * P
    (Qx, Qy, Qz) = Q
    print('Qx: ' + Integer(Qx).hex())
    print('Qy: ' + Integer(Qy).hex())
    print('Qz: ' + Integer(Qz).hex())
print('=========================================')

# CurveOrder sanity check
#
# P = G1.random_point()
# (Px, Py, Pz) = P
# print('Px: ' + Integer(Px).hex())
# print('Py: ' + Integer(Py).hex())
# print('Pz: ' + Integer(Pz).hex())
#
# print('order: ' + Integer(r).hex())
#
# Q = (r * cofactor) * P
# (Qx, Qy, Qz) = Q
# print('Qx: ' + Integer(Qx).hex())
# print('Qy: ' + Integer(Qy).hex())
# print('Qz: ' + Integer(Qz).hex())
