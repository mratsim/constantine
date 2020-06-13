# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                    BN254 GLV Endomorphism
#                     Lattice Decomposition
#
# ############################################################

# Parameters
u = Integer('0x44E992B44A6909F1')
p = 36*u^4 + 36*u^3 + 24*u^2 + 6*u + 1
r = 36*u^4 + 36*u^3 + 18*u^2 + 6*u + 1
cofactor = 1

# Cube root of unity (mod r) formula for any BN curves
lambda1_r = (-(36*u^3+18*u^2+6*u+2))
assert lambda1_r^3 % r == 1
print('λᵩ1  : ' + lambda1_r.hex())
print('λᵩ1+r: ' + (lambda1_r+r).hex())
print('λᵩ1+r: ' + (lambda1_r+r).hex())

lambda2_r = (36*u^4-1)
assert lambda2_r^3 % r == 1
print('λᵩ2  : ' + lambda2_r.hex())

# Finite fields
F       = GF(p)
# K2.<u>  = PolynomialRing(F)
# F2.<beta>  = F.extension(u^2+9)
# K6.<v>  = PolynomialRing(F2)
# F6.<eta>  = F2.extension(v^3-beta)
# K12.<w> = PolynomialRing(F6)
# K12.<gamma> = F6.extension(w^2-eta)

# Curves
b = 3
G1 = EllipticCurve(F, [0, b])
# G2 = EllipticCurve(F2, [0, b/beta])

(phi1, phi2) = (root for root in GF(p)(1).nth_root(3, all=True) if root != 1)
print('𝜑1  :' + Integer(phi1).hex())
print('𝜑2  :' + Integer(phi2).hex())

# Check
def checkEndo():
    P = G1.random_point()
    (Px, Py, Pz) = P
    Qendo1 = G1([Px*phi1 % p, Py, Pz])
    Qendo2 = G1([Px*phi2 % p, Py, Pz])

    Q1 = lambda1_r * P
    Q2 = lambda2_r * P

    assert P != Q1
    assert P != Q2

    assert Q1 == Qendo1
    assert Q2 == Qendo1

    print('Endomorphism OK with 𝜑1')

checkEndo()

# Lattice
b = [
  [2*u+1, 6*u^2+4*u+1],
  [6*u^2+2*u,  -2*u-1]
]
# Babai rounding
ahat = [2*u+1, 6*u^2+4*u+1]
v = int(r).bit_length()
v = int(((v + 64 - 1) // 64) * 64) # round to next multiple of 64

l = [Integer(a << v) // r for a in ahat]

def getGLV2_decomp(scalar):

    a0 = (l[0] * scalar) >> v
    a1 = (l[1] * scalar) >> v

    k0 = scalar - a0 * b[0][0] - a1 * b[1][0]
    k1 = 0      - a0 * b[0][1] - a1 * b[1][1]

    assert int(k0).bit_length() <= (int(r).bit_length() + 1) // 2
    assert int(k1).bit_length() <= (int(r).bit_length() + 1) // 2

    assert scalar == (k0 + k1 * (lambda1_r % r)) % r
    assert scalar == (k0 + k1 * (lambda2_r % r)) % r

    return k0, k1

def scalarMulGLV():
    scalar = randrange(r) # Pick an integer below curve order
    print('scalar: ' + Integer(scalar).hex())

    k0, k1 = getGLV2_decomp(scalar)
    print('k0: ' + k0.hex())
    print('k1: ' + k1.hex())

    P0 = G1.random_point()
    P1 = (lambda1_r % r) * P0
    (Px, Py, Pz) = P0
    P1_endo = G1([Px*phi1 % p, Py, Pz])

    expected = scalar * P0
    decomp = k0*P0 + k1*P1
    assert expected == decomp

# Test generator
set_random_seed(1337)

for i in range(1):
    print('---------------------------------------')
    scalarMulGLV()
