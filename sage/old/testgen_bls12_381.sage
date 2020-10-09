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

# https://crypto.stackexchange.com/questions/64064/order-of-twisted-curve-in-pairings
# https://math.stackexchange.com/questions/144194/how-to-find-the-order-of-elliptic-curve-over-finite-field-extension
cofactorG1 = G1.order() // r
cofactorG2 = G2.order() // r

print('')
print('cofactor G1: ' + cofactorG1.hex())
print('cofactor G2: ' + cofactorG2.hex())
print('')

def clearCofactorG1(P):
    return cofactorG1 * P

def clearCofactorG2(P):
    return cofactorG2 * P

# Test generator
set_random_seed(1337)

print('=========================================')
print('G1 vectors: ')
for i in range(10):
    print(f'--- test {i} ------------------------------')
    Prand = G1.random_point()
    P = clearCofactorG1(Prand)

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
print('=========================================')
print('G2 vectors: ')

for i in range(10):
    print(f'--- test {i} ------------------------------')
    Prand = G2.random_point()
    P = clearCofactorG2(Prand)

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
