# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                         BLS12-381
#                   Frobenius Endomorphism
#              Untwist-Frobenius-Twist isogeny
#
# ############################################################

# Parameters
x = -(2^63 + 2^62 + 2^60 + 2^57 + 2^48 + 2^16)
p = (x - 1)^2 * (x^4 - x^2 + 1)//3 + x
r = x^4 - x^2 + 1
t = x + 1
print('p  : ' + p.hex())
print('r  : ' + r.hex())
print('t  : ' + t.hex())
print('p (mod r) == t-1 (mod r) == 0x' + (p % r).hex())

# Finite fields
Fp       = GF(p)
K2.<u>  = PolynomialRing(Fp)
Fp2.<beta>  = Fp.extension(u^2+1)

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

# Utilities
def fp2_to_hex(a):
    v = vector(a)
    return '0x' + Integer(v[0]).hex() + ' + β * ' + '0x' + Integer(v[1]).hex()

# Frobenius map constants (D type: use SNR, M type use 1/SNR)
print('\nFrobenius extension field constants')
FrobConst_map = SNR^((p-1)/6)
FrobConst_map_list = []
cur = Fp2([1, 0])

for i in range(6):
    FrobConst_map_list.append(cur)
    print(f'FrobConst_map_{i}     : {fp2_to_hex(cur)}')
    cur *= FrobConst_map
print('')
for i in range(6):
    print(f'FrobConst_map_{i}_pow2     : {fp2_to_hex(FrobConst_map_list[i]*conjugate(FrobConst_map_list[i]))}')
print('')
for i in range(6):
    print(f'FrobConst_map_{i}_pow3     : {fp2_to_hex(FrobConst_map_list[i]**2 * conjugate(FrobConst_map_list[i]))}')

# Frobenius psi constants (D type: use SNR, M type use 1/SNR)
print('\nψ (Psi) - Untwist-Frobenius-Twist constants')
print('1/sextic_non_residue: ' + fp2_to_hex(1/SNR))
FrobConst_psi = (1/SNR)^((p-1)/6)
FrobConst_psi_2 = FrobConst_psi * FrobConst_psi
FrobConst_psi_3 = FrobConst_psi_2 * FrobConst_psi
print('FrobConst_psi   : ' + fp2_to_hex(FrobConst_psi))
print('FrobConst_psi_2  : ' + fp2_to_hex(FrobConst_psi_2))
print('FrobConst_psi_3  : ' + fp2_to_hex(FrobConst_psi_3))

print('')
FrobConst_psi2_2 = FrobConst_psi_2 * FrobConst_psi_2**p
FrobConst_psi2_3 = FrobConst_psi_3 * FrobConst_psi_3**p
print('FrobConst_psi2_2  : ' + fp2_to_hex(FrobConst_psi2_2))
print('FrobConst_psi2_3  : ' + fp2_to_hex(FrobConst_psi2_3))

print('')
FrobConst_psi3_2 = FrobConst_psi_2 * FrobConst_psi2_2**p
FrobConst_psi3_3 = FrobConst_psi_3 * FrobConst_psi2_3**p
print('FrobConst_psi3_2  : ' + fp2_to_hex(FrobConst_psi3_2))
print('FrobConst_psi3_3  : ' + fp2_to_hex(FrobConst_psi3_3))

# Recap, with ξ (xi) the sextic non-residue
# psi_2 = ((1/ξ)^((p-1)/6))^2 = (1/ξ)^((p-1)/3)
# psi_3 = psi_2 * (1/ξ)^((p-1)/6) = (1/ξ)^((p-1)/3) * (1/ξ)^((p-1)/6) = (1/ξ)^((p-1)/2)
#
# Reminder, in 𝔽p2, frobenius(a) = a^p = conj(a)
# psi2_2 = psi_2 * psi_2^p = (1/ξ)^((p-1)/3) * (1/ξ)^((p-1)/3)^p = (1/ξ)^((p-1)/3) * frobenius((1/ξ))^((p-1)/3)
#        = norm(1/ξ)^((p-1)/3)
# psi2_3 = psi_3 * psi_3^p = (1/ξ)^((p-1)/2) * (1/ξ)^((p-1)/2)^p = (1/ξ)^((p-1)/2) * frobenius((1/ξ))^((p-1)/2)
#        = norm(1/ξ)^((p-1)/2)
#
# In Fp²:
# - quadratic non-residues respect the equation a^((p²-1)/2) ≡ -1 (mod p²) by the Legendre symbol
# - sextic non-residues are also quadratic non-residues so ξ^((p²-1)/2) ≡ -1 (mod p²)
# - QRT(1/a) = QRT(a) with QRT the quadratic residuosity test
#
# We have norm(ξ)^((p-1)/2) = (ξ*frobenius(ξ))^((p-1)/2) = (ξ*(ξ^p))^((p-1)/2) = ξ^(p+1)^(p-1)/2
#                           = ξ^((p²-1)/2)
# And ξ^((p²-1)/2) ≡ -1 (mod p²)
# So psi2_3 ≡ -1 (mod p²)
#
# TODO: explain why psi3_2 = [0, -1]

# Frobenius Fp2
A = Fp2([5, 7])
Aconj = Fp2([5, -7])
AF = A.frobenius(1) # or pth_power(1)
AF2 = A.frobenius(2)
AF3 = A.frobenius(3)
print('')
print('A          : ' + fp2_to_hex(A))
print('A conjugate: ' + fp2_to_hex(Aconj))
print('')
print('AF1        : ' + fp2_to_hex(AF))
print('AF2        : ' + fp2_to_hex(AF2))
print('AF3        : ' + fp2_to_hex(AF3))

def psi(P):
    (Px, Py, Pz) = P
    return G2([
        FrobConst_psi_2 * Px.frobenius(),
        FrobConst_psi_3 * Py.frobenius()
        # Pz.frobenius() - Always 1 after extract
    ])

def psi2(P):
    (Px, Py, Pz) = P
    return G2([
        FrobConst_psi2_2 * Px.frobenius(2),
        FrobConst_psi2_3 * Py.frobenius(2)
        # Pz - Always 1 after extract
    ])

def clearCofactorG2(P):
    return cofactorG2 * P

# Test generator
set_random_seed(1337)

# Vectors
print('\nTest vectors:')
for i in range(4):
    P = G2.random_point()
    P = clearCofactorG2(P)

    (Px, Py, Pz) = P
    vPx = vector(Px)
    vPy = vector(Py)
    # Pz = vector(Pz)
    print(f'\nTest {i}')
    print('  Px: ' + Integer(vPx[0]).hex() + ' + β * ' + Integer(vPx[1]).hex())
    print('  Py: ' + Integer(vPy[0]).hex() + ' + β * ' + Integer(vPy[1]).hex())

    # Galbraith-Lin-Scott, 2008, Theorem 1
    # Fuentes-Castaneda et al, 2011, Equation (2)
    assert psi(psi(P)) - t*psi(P) + p*P == G2([0, 1, 0]), "Always true"

    # Galbraith-Scott, 2008, Lemma 1
    # k-th cyclotomic polynomial with k = 12
    assert psi2(psi2(P)) - psi2(P) + P == G2([0, 1, 0]), "Always true"

    assert psi(psi(P)) == psi2(P), "Always true"

    (Qx, Qy, Qz) = psi(P)
    vQx = vector(Qx)
    vQy = vector(Qy)
    print('  Qx: ' + Integer(vQx[0]).hex() + ' + β * ' + Integer(vQx[1]).hex())
    print('  Qy: ' + Integer(vQy[0]).hex() + ' + β * ' + Integer(vQy[1]).hex())

    assert psi(P) == (p % r) * P, "Can be false if the cofactor was not cleared"
