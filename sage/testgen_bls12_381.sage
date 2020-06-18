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
x = -(2^63 + 2^62 + 2^60 + 2^57 + 2^48 + 2^16)
p = (x - 1)^2 * (x^4 - x^2 + 1)//3 + x
r = x^4 - x^2 + 1
cofactor = Integer('0x396c8c005555e1568c00aaab0000aaab')

# Effective cofactor for the G2 curve (that leads to equivalent hashToG2 when using endomorphisms)
g2_h_eff = Integer('0xbc69f08f2ee75b3584c6a0ea91b352888e2a8e9145ad7689986ff031508ffe1329c2f178731db956d82bf015d1212b02ec0ec69d7477c1ae954cbc06689f6a359894c0adebbf6b4e8020005aaa95551')

# Finite fields
Fp       = GF(p)
K2.<u>  = PolynomialRing(Fp)
Fp2.<beta>  = Fp.extension(u^2+1)
# K6.<v>  = PolynomialRing(Fp2)
# Fp6.<eta>  = Fp2.extension(v^3-Fp2([1, 1])
# K12.<w> = PolynomialRing(Fp6)
# K12.<gamma> = F6.extension(w^2-eta)

# Curves
b = 4
SNR = Fp2([1, 1])
G1 = EllipticCurve(Fp, [0, b])
G2 = EllipticCurve(Fp2, [0, b*SNR])

# Test generator
set_random_seed(1337)

print('=========================================')
print('G1 vectors: ')
for i in range(10):
    Prand = G1.random_point()

    # Clear cofactor
    P = Prand * cofactor

    (Px, Py, Pz) = P
    print('Px: ' + Integer(Px).hex())
    print('Py: ' + Integer(Py).hex())
    # print('Pz: ' + Integer(Pz).hex())
    exponent = randrange(r) # Pick an integer below curve order
    print('scalar: ' + Integer(exponent).hex())

    Q = exponent * P
    (Qx, Qy, Qz) = Q
    print('Qx: ' + Integer(Qx).hex())
    print('Qy: ' + Integer(Qy).hex())
    # print('Qz: ' + Integer(Qz).hex())
    print('---------------------------------------')
print('=========================================')
print('G2 vectors: ')

for i in range(10):
    Prand = G2.random_point()

    # Clear cofactor
    P = Prand * g2_h_eff

    (Px, Py, Pz) = P
    vPx = vector(Px)
    vPy = vector(Py)
    # Pz = vector(Pz)
    print('Px: ' + Integer(vPx[0]).hex() + ' + β * ' + Integer(vPx[1]).hex())
    print('Py: ' + Integer(vPy[0]).hex() + ' + β * ' + Integer(vPy[1]).hex())

    exponent = randrange(r) # Pick an integer below curve order
    print('scalar: ' + Integer(exponent).hex())

    Q = exponent * P
    (Qx, Qy, Qz) = Q
    Qx = vector(Qx)
    Qy = vector(Qy)
    print('Qx: ' + Integer(Qx[0]).hex() + ' + β * ' + Integer(Qx[1]).hex())
    print('Qy: ' + Integer(Qy[0]).hex() + ' + β * ' + Integer(Qy[1]).hex())
    print('---------------------------------------')
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
