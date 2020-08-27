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
cofactor = Integer('0x396c8c005555e1568c00aaab0000aaab')
print('p  : ' + p.hex())
print('r  : ' + r.hex())

# Finite fields
Fp       = GF(p)
K2.<u>  = PolynomialRing(Fp)
Fp2.<beta>  = Fp.extension(u^2+1)
# K6.<v>  = PolynomialRing(F2)
# Fp6.<eta>  = Fp2.extension(v^3-beta)
# K12.<w> = PolynomialRing(Fp6)
# Fp12.<gamma> = Fp6.extension(w^2-eta)

# Curves
b = 4
SNR = Fp2([1, 1])
G1 = EllipticCurve(Fp, [0, b])
G2 = EllipticCurve(Fp2, [0, b*SNR])

# Utilities
def fp2_to_hex(a):
    v = vector(a)
    return Integer(v[0]).hex() + ' + β * ' + Integer(v[1]).hex()

# Frobenius constants (D type: use SNR, M type use 1/SNR)
print('1/sextic_non_residue: ' + fp2_to_hex(1/SNR))
FrobConst = (1/SNR)**((p-1)/6)
print('FrobConst   : ' + fp2_to_hex(FrobConst))
FrobConst2 = FrobConst * FrobConst
print('FrobConst2  : ' + fp2_to_hex(FrobConst2))
FrobConst3 = FrobConst2 * FrobConst
print('FrobConst3  : ' + fp2_to_hex(FrobConst3))
