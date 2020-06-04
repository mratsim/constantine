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
u = -(2^63 + 2^62 + 2^60 + 2^57 + 2^48 + 2^16)
p = (u - 1)^2 * (u^4 - u^2 + 1)//3 + u
r = u^4 - u^2 + 1
cofactor = Integer('0x396c8c005555e1568c00aaab0000aaab')

# Finite fields
F       = GF(p)
K2.<u>  = PolynomialRing(F)
# F2.<beta>  = F.extension(u^2+1)
# K6.<v>  = PolynomialRing(F2)
# F6.<eta>  = F2.extension(v^3-beta)
# K12.<w> = PolynomialRing(F6)
# K12.<gamma> = F6.extension(w^2-eta)

# Curves
b = 4
G1 = EllipticCurve(F, [0, b])
# G2 = EllipticCurve(F2, [0, b*beta])

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
