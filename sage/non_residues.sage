# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# This script checks polynomial irreducibility
#
# Constructing Tower Extensions for the implementation of Pairing-Based Cryptography
# Naomi Benger and Michael Scott, 2009
# https://eprint.iacr.org/2009/556


















# ############################################################
#
#    Failed experiments of actually instantiating
#          the tower of extension fields
#
# ############################################################

# ############################################################
# 1st try

# # Create the field of x ∈ [0, p-1]
# K.<p> = NumberField(x - 1)
#
# # Tower Fp² with Fp[u] / (u² + 1) <=> u = 𝑖
# L.<im> = K.extension(x^2 + 1)
#
# TODO how to make the following work?
# # Tower Fp^6 with Fp²[v] / (v³ - (u + 1))
# M.<xi> = L.extension(x^3 - (im + 1))

# ############################################################
# 2nd try

# # Create the field of u ∈ [0, p-1]
# p = Integer('0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47')
# Fp = GF(p)
# Elem.<u> = Fp[]
# print("p mod 4 = ", p % 4)
#
# # Tower Fp² with Fp[u] / (u² + 1) <=> u = 𝑖
# Fp2.<im> = Fp.extension(u^2 + 1)
# Elem2.<v> = Fp2[]
#
# # Tower Fp^6 with Fp²[v] / (v³ - (u + 1))
# Fp6.<xi> = Fp.extension(v^3 - (im + 1))
# Elem6.<w> = Fp6[]

# ############################################################
# 3rd try
# K.<xi, im, p> = NumberField([x^3 - I - 1, x^2 + 1, x - 1])

# ############################################################
# 4th try, just trying to verify Fp6
# print('Verifying non-residues')

# modulus = Integer('0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47')

# Fp.<p> = NumberField(x - 1)
# r1 = Fp(-1).residue_symbol(Fp.ideal(modulus),2)
# print('Fp² = Fp[sqrt(-1)]: ' + str(r1))

# Fp2.<im> = Fp.extension(x^2 + 1)

# xi = Fp2(1+im)
# r2 = xi.residue_symbol(Fp2.ideal(modulus),3)
# # ValueError: The residue symbol to that power is not defined for the number field
# # ^ AFAIK that means that Fp2 doesn't contain the 3rd root of unity
# #   so we are clear
# print('Fp6 = Fp²[cubicRoot(1+I)]: ' + str(r2))
