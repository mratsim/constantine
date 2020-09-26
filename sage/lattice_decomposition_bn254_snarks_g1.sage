# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                  BN254-Snarks GLV Endomorphism
#                     Lattice Decomposition
#
# ############################################################

# Parameters
x = Integer('0x44E992B44A6909F1')
p = 36*x^4 + 36*x^3 + 24*x^2 + 6*x + 1
r = 36*x^4 + 36*x^3 + 18*x^2 + 6*x + 1

# Cube root of unity (mod r) formula for any BN curves
lambda1_r = (-(36*x^3+18*x^2+6*x+2))
assert lambda1_r^3 % r == 1
print('λᵩ1  : ' + lambda1_r.hex())
print('λᵩ1+r: ' + (lambda1_r+r).hex())

lambda2_r = (36*x^4-1)
assert lambda2_r^3 % r == 1
print('λᵩ2  : ' + lambda2_r.hex())

# Finite fields
F       = GF(p)

# Curves
b = 3
G1 = EllipticCurve(F, [0, b])

cofactorG1 = G1.order() // r
assert cofactorG1 == 1, "BN curve have a prime order"

print('')
print('cofactor G1: ' + cofactorG1.hex())
print('')

(phi1, phi2) = (root for root in GF(p)(1).nth_root(3, all=True) if root != 1)
print('𝜑1  :' + Integer(phi1).hex())
print('𝜑2  :' + Integer(phi2).hex())

# Test generator
set_random_seed(1337)

# Check
def checkEndo():
    P = G1.random_point()
    assert P != G1([0, 1, 0]) # Infinity

    (Px, Py, Pz) = P
    Qendo1 = G1([Px*phi1 % p, Py, Pz])
    Qendo2 = G1([Px*phi2 % p, Py, Pz])

    Q1 = lambda1_r * P
    Q2 = lambda2_r * P

    assert P != Q1
    assert P != Q2

    assert (F(Px)*F(phi1))^3 == F(Px)^3
    assert (F(Px)*F(phi2))^3 == F(Px)^3

    assert Q1 == Qendo1
    assert Q2 == Qendo1

    print('Endomorphism OK with 𝜑1')

checkEndo()

# Decomposition generated by LLL-algorithm and Babai rounding
# to solve the Shortest (Basis) Vector Problem
# Lattice from Guide to Pairing-Based Cryptography
Lat = [
  [2*x+1, 6*x^2+4*x+1],
  [6*x^2+2*x,  -2*x-1]
]
ahat = [2*x+1, 6*x^2+4*x+1]
n = int(r).bit_length()
n = int(((n + 64 - 1) // 64) * 64) # round to next multiple of 64
v = [Integer(a << n) // r for a in ahat]

def pretty_print_lattice(Lat):
    latHex = [['0x' + x.hex() if x >= 0 else '-0x' + (-x).hex() for x in vec] for vec in Lat]
    maxlen = max([len(cell) for row in latHex for cell in row])
    for row in latHex:
        row = ' '.join(cell.rjust(maxlen + 2) for cell in row)
        print(row)

print('\nLattice')
pretty_print_lattice(Lat)

print('\nbasis:')
print('  𝛼\u03050: 0x' + v[0].hex())
print('  𝛼\u03051: 0x' + v[1].hex())
print('')

maxInfNorm = abs(6*x^2+6*x+2)
print('\nmax infinity norm:')
print('  ||(a0, a1)||∞ ≤ 0x' + str(maxInfNorm.hex()))
print('  infinity norm bitlength: ' + str(int(maxInfNorm).bit_length()))

# Contrary to Faz2013 paper, we use the max infinity norm
# to properly dimension our recoding instead of ⌈log2 r/m⌉ + 1
# which fails for some inputs
# +1 for signed column
# Optional +1 for handling negative miniscalars
L = int(maxInfNorm).bit_length() + 1
L += 1

def getGLV2_decomp(scalar):

    maxLen = (int(r).bit_length() + 1) // 2 + 1

    a0 = (v[0] * scalar) >> n
    a1 = (v[1] * scalar) >> n

    k0 = scalar - a0 * Lat[0][0] - a1 * Lat[1][0]
    k1 = 0      - a0 * Lat[0][1] - a1 * Lat[1][1]

    assert int(k0).bit_length() <= maxLen
    assert int(k1).bit_length() <= maxLen

    assert scalar == (k0 + k1 * (lambda1_r % r)) % r
    assert scalar == (k0 + k1 * (lambda2_r % r)) % r

    return k0, k1

def recodeScalars(k):
    m = 2

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

def scalarMulEndo(scalar, P0):
    m = 2
    print('L: ' + str(L))

    print('scalar: ' + Integer(scalar).hex())

    k0, k1 = getGLV2_decomp(scalar)
    print('k0: ' + k0.hex())
    print('k1: ' + k1.hex())

    P1 = (lambda1_r % r) * P0
    (Px, Py, Pz) = P0
    P1_endo = G1([Px*phi1 % p, Py, Pz])
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
    scalar = Integer('0x0e08a292f940cfb361cc82bc24ca564f51453708c9745a9cf8707b11c84bc448')
    P = G1([
        Integer('0x22d3af0f3ee310df7fc1a2a204369ac13eb4a48d969a27fcd2861506b2dc0cd7'),
        Integer('0x1c994169687886ccd28dd587c29c307fb3cab55d796d73a5be0bbf9aab69912e'),
        Integer(1)
    ])
    scalarMulEndo(scalar, P)
