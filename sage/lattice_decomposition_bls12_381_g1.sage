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
u = -(2^63 + 2^62 + 2^60 + 2^57 + 2^48 + 2^16)
p = (u - 1)^2 * (u^4 - u^2 + 1)//3 + u
r = u^4 - u^2 + 1
cofactor = Integer('0x396c8c005555e1568c00aaab0000aaab')
print('p  : ' + p.hex())
print('r  : ' + r.hex())

# Cube root of unity (mod r) formula for any BLS12 curves
lambda1_r = u^2 - 1
assert lambda1_r^3 % r == 1
print('λᵩ1  : ' + lambda1_r.hex())
print('λᵩ1+r: ' + (lambda1_r+r).hex())

lambda2_r = u^4
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
b = 4
G1 = EllipticCurve(F, [0, b])
# G2 = EllipticCurve(F2, [0, b*beta])

(phi1, phi2) = (root for root in GF(p)(1).nth_root(3, all=True) if root != 1)
print('𝜑1  :' + Integer(phi1).hex())
print('𝜑2  :' + Integer(phi2).hex())
assert phi1^3 % p == 1
assert phi2^3 % p == 1

# Test generator
set_random_seed(1337)

# Check
def checkEndo():
    Prand = G1.random_point()
    assert Prand != G1([0, 1, 0]) # Infinity

    # Clear cofactor
    P = Prand * cofactor

    (Px, Py, Pz) = P
    Qendo1 = G1([Px*phi1 % p, Py, Pz])
    Qendo2 = G1([Px*phi2 % p, Py, Pz])

    Q1 = lambda1_r * P
    Q2 = lambda2_r * P

    assert P != Q1
    assert P != Q2

    assert (F(Px)*F(phi1))^3 == F(Px)^3
    assert (F(Px)*F(phi2))^3 == F(Px)^3

    assert Q1 == Qendo2
    assert Q2 == Qendo2

    print('Endomorphism OK with 𝜑2')

checkEndo()

# Lattice
b = [
  [u^2-1, -1],
  [1,  u^2]
]
# Babai rounding
ahat = [u^2, 1]
v = int(r).bit_length()
v = int(((v + 64 - 1) // 64) * 64) # round to next multiple of 64

l = [Integer(a << v) // r for a in ahat]
print('𝛼\u03051: ' + l[0].hex())
print('𝛼\u03052: ' + l[1].hex())

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

def recodeScalars(k):
    m = 2
    L = ((int(r).bit_length() + m-1) // m) + 1 # l = ⌈log2 r/m⌉ + 1

    b = [[0] * L, [0] * L]
    b[0][L-1] = 0
    for i in range(0, L-1): # l-2 inclusive
        b[0][i] = 1 - ((k[0] >> (i+1)) & 1)
    for j in range(1, m):
        for i in range(0, L):
            b[j][i] = k[j] & 1
            k[j] = k[j]//2 + (b[j][i] & b[0][i])

    return b

def buildLut(P0, P1):
    m = 2
    lut = [0] * (1 << (m-1))
    lut[0] = P0
    lut[1] = P0 + P1
    return lut

def pointToString(P):
    (Px, Py, Pz) = P
    return '(x: ' + Integer(Px).hex() + ', y: ' + Integer(Py).hex() + ', z: ' + Integer(Pz).hex() + ')'

def scalarMulGLV(scalar, P0):
    m = 2
    L = ((int(r).bit_length() + m-1) // m) + 1 # l = ⌈log2 r/m⌉ + 1

    print('L: ' + str(L))

    print('scalar: ' + Integer(scalar).hex())

    k0, k1 = getGLV2_decomp(scalar)
    print('k0: ' + k0.hex())
    print('k1: ' + k1.hex())

    P1 = (lambda1_r % r) * P0
    (Px, Py, Pz) = P0
    P1_endo = G1([Px*phi2 % p, Py, Pz])
    assert P1 == P1_endo

    expected = scalar * P0
    decomp = k0*P0 + k1*P1
    assert expected == decomp

    print('------ recode scalar -----------')
    even = k0 & 1 == 0
    if even:
        k0 += 1

    b = recodeScalars([k0, k1])
    print('b0: ' + str(list(reversed(b[0]))))
    print('b1: ' + str(list(reversed(b[1]))))

    print('------------ lut ---------------')

    lut = buildLut(P0, P1)

    print('------------ mul ---------------')
    # b[0][L-1] is always 0
    Q = lut[b[1][L-1]]
    for i in range(L-2, -1, -1):
        Q *= 2
        Q += (1 - 2 * b[0][i]) * lut[b[1][i]]

    if even:
        Q -= P0

    print('final Q: ' + pointToString(Q))
    print('expected: ' + pointToString(expected))
    assert Q == expected

# Test generator
set_random_seed(1337)

for i in range(1):
    print('---------------------------------------')
    # scalar = randrange(r) # Pick an integer below curve order
    # P = G1.random_point()
    scalar = Integer('0xf7e60a832eb77ac47374bc93251360d6c81c21add62767ff816caf11a20d8db')
    P = G1([
        Integer('0xf9679bb02ee7f352fff6a6467a5e563ec8dd38c86a48abd9e8f7f241f1cdd29d54bc3ddea3a33b62e0d7ce22f3d244a'),
        Integer('0x50189b992cf856846b30e52205ff9ef72dc081e9680726586231cbc29a81a162120082585f401e00382d5c86fb1083f'),
        Integer(1)
    ])
    scalarMulGLV(scalar, P)
