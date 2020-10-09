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

# Note: Some of the curves here are not pairing friendly and never used in an extension field.
#       We still check them to potentially add them as additional test vectors in
#       𝔽p2, 𝔽p6, 𝔽p12, ... since as they are most 0xFF bytes they
#       trigger "carry" code-paths that are not triggered by pairing-friendly moduli.
Curves = {
    'P224': Integer('0xffffffffffffffffffffffffffffffff000000000000000000000001'),
    'BN254_Nogami': Integer('0x2523648240000001ba344d80000000086121000000000013a700000000000013'),
    'BN254_Snarks': Integer('0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47'),
    'Curve25519': Integer('0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffed'),
    'P256': Integer('0xffffffff00000001000000000000000000000000ffffffffffffffffffffffff'),
    'Secp256k1': Integer('0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F'),
    'BLS12_377': Integer('0x01ae3a4617c510eac63b05c06ca1493b1a22d9f300f5138f1ef3622fba094800170b5d44300000008508c00000000001'),
    'BLS12_381': Integer('0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab'),
    'BN446': Integer('0x2400000000000000002400000002d00000000d800000021c0000001800000000870000000b0400000057c00000015c000000132000000067'),
    'FKM12_447': Integer('0x4ce300001338c00001c08180000f20cfffffe5a8bffffd08a000000f228000007e8ffffffaddfffffffdc00000009efffffffca000000007'),
    'BLS12_461': Integer('0x15555545554d5a555a55d69414935fbd6f1e32d8bacca47b14848b42a8dffa5c1cc00f26aa91557f00400020000555554aaaaaac0000aaaaaaab'),
    'BN462': Integer('0x240480360120023ffffffffff6ff0cf6b7d9bfca0000000000d812908f41c8020ffffffffff6ff66fc6ff687f640000000002401b00840138013')
}

def find_quadratic_non_residues(A, B, Field, modulus):
    result = false
    for a in A:
        for b in B:
              residue = Fp(a^2 + b^2).residue_symbol(Fp.ideal(modulus),2)
              if residue < 0:
                print(f'        𝔽p4 = 𝔽p2[v] / v² - ({a} ± {b}𝑖) is an irreducible polynomial')
                result = true
    return result

def find_cubic_non_residues_pmod3eq1(A, B, modulus):
    assert modulus % 3 == 1
    result = false
    for a in A:
        for b in B:
            #   The following `residue_symbol` is not satisfactory for cubic root
            #   It just returns exceptions for all values
            #
            #
            #   residue = Fp(a^2 + b^2).residue_symbol(Fp.ideal(modulus),3)
            #   if residue < 0:
            #       print(f'        𝔽p2[v] / v³ - ({a} ± {b}𝑖) is an irreducible polynomial')

            # for p ≡ 1 (mod 3)
            # we have ``a`` a cubic residue iff a^((p-1)/3) ≡ 1 (mod p)
            residue = pow(a^2 + b^2, (modulus-1)//3, modulus)
            if residue != 1:
                print(f'        𝔽p6 = 𝔽p2[v] / v³ - ({a} ± {b}𝑖) is a possible extension')
                result = true
    return result

for curve, modulus in Curves.items():
    print(f'Curve {curve}:')
    print(f'  Modulus 0x{modulus.hex()}:')
    pMod4 = modulus % 4
    print(f'    p mod  4: {pMod4}')
    if pMod4 == 3:
        # This is actually the hard case, but given that most pairing friendly curves somehow end up in that case
        # this is the one we will focus on.
        print(f'           ^ suggested irreducible polynomial for 𝔽p2: u² + 1 (𝔽p2 complex)')
    else:
        print(f'           ⚠️  p mod 4 != 3: to be reviewed manually. See Theorem 1 of Scott 2009 Constructing Tower Extensions for the implementation of Pairing-Based Cryptography')
    print(f'    p mod  8: {modulus % 8}')
    print(f'    p mod 12: {modulus % 12}')
    if pMod4 != 3:
        print(f'    p mod 4 != 3 => find a square/cubic root and then successively adjoin roots of the roots to build the tower.')
        print(f'    Skipping to next curve.')
        continue


    Fp.<p> = NumberField(x - 1)
    print('')
    print('    Searching for valid irreducible polynomials ...')

    # Constructing 𝔽p4
    print('      𝔽p4 = 𝔽p2[v] / v² - (a ± 𝑖 b))')
    found = find_quadratic_non_residues([0, 1, 2], [1, 2], Fp, modulus)
    if not found:
        found = find_quadratic_non_residues(range(5), range(1, 5), Fp, modulus)
    assert found
    found = false

    # Constructing 𝔽p6
    print('      𝔽p6 = 𝔽p2[v] / v³ - (a ± 𝑖 b))')
    pMod3 = modulus % 3
    print(f'        p mod  3: {pMod3}')
    if pMod3 != 1:
      # A remark on the computation of cube roots in finite fields
      # https://eprint.iacr.org/2009/457.pdf
      print(f'        p mod 3 != 1 => to be reviewed manually')
      print(f'        Skipping to next curve.')
      continue

    if not found:
        found = find_cubic_non_residues_pmod3eq1([0, 1, 2], [1, 2], modulus)
    if not found:
        found = find_cubic_non_residues_pmod3eq1(range(5), range(1, 5), modulus)
    if not found:
        found = find_cubic_non_residues_pmod3eq1(range(17), range(1, 17), modulus)
    assert found

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
