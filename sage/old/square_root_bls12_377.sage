# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                         BLS12-377
#                 Constant-time Square Root
#
# ############################################################

# Parameters
x = 3 * 2^46 * (7 * 13 * 499) + 1
p = (x - 1)^2 * (x^4 - x^2 + 1)//3 + x
r = x^4 - x^2 + 1
t = x + 1
print('x  : ' + x.hex())
print('p  : ' + p.hex())
print('r  : ' + r.hex())
print('t  : ' + t.hex())

def modCheck(p, pow):
    ## Find q mod 2^s != 1
    q = p^pow
    s = 4
    while q % s == 1:
        s *= 2
        if s > q:
            raise ValueError('Uh Oh')
    if pow == 1:
      print(f'Found: p mod {s} = {q % s}')
    else:
      print(f'Found: p^{pow} mod {s} = {q % s}')

modCheck(p, 1) # Found: p mod 140737488355328 = 70368744177665
modCheck(p, 2) # Found: p^2 mod 281474976710656 = 140737488355329

# On Fp
# a^((p-70368744177665+140737488355328)/140737488355328)
# would lead to a square root but there would be
# log2(140737488355328)-1 candidates
# which must be checked constant time

def precomp_tonelli_shanks(p):
    ## Precompute constants for
    ## constant-time Tonelli Shanks algorithm
    ## with q = p^pow returns:
    ## 1. c1, the largest integer such that 2^c1 divides q - 1.
    ## 2. c2 = (q - 1) / (2^c1) in ℕ
    ## 3. c3 = (c2 - 1) / 2 in ℕ
    ## 4. c4, a non-square value in Fq
    ## 5. c5 = c4^c2 in Fq
    q = p
    c1 = 0
    c2 = q-1
    while c2 & 1 == 0:
        c2 >>= 1
        c1 += 1
    c3 = (c2 - 1) // 2
    c4 = 1
    while kronecker(c4, q) == 1:
        c4 += 1
    c5 = GF(p)(c4)^c2
    return (c1,c2,c3,c4,c5)

def ccopy(a, b, ctl):
    ## `b` if `ctl` is true, `a` if false
    return int(not(bool(ctl)))*a + int(bool(ctl))*b

def sqrt_tonelli_shanks(x, p):
    ## Returns z = x² (p^pow)
    (c1, c2, c3, c4, c5) = precomp_tonelli_shanks(p)

    x = GF(p)(x)

    z = x^c3
    t = z*z*x
    z *= x
    b = t
    c = c5
    for i in range(c1, 1, -1): # c1 ... 2
        for j in range(1, i-1): # 1 ... i-2
            b *= b
        z = ccopy(z, z*c, b != 1)
        c *= c
        t = ccopy(t, t*c, b != 1)
        b = t
    return z

# for a in range(2, 30):
#     if kronecker(a, p) != 1:
#         continue
#     # print(f'{a}^(p-1)/2 = ' + str(GF(p)(a)^((p-1)/2)))
#     print(f'{a} is a quadratic residue mod p')
#     b = sqrt_tonelli_shanks(a, p)
#     # print(f'{b}² = {a} mod p')
#     # print('b*b = ' + str(b*b))
#     assert b*b == a

# Optimized Tonelli Shanks
# --------------------------------------------------------

# Finite fields
Fp       = GF(p)
K2.<u>  = PolynomialRing(Fp)
Fp2.<beta>  = Fp.extension(u^2+5)

def precomp_ts(Fq):
    ## From q = p^m with p the prime characteristic of the field Fp^m
    ##
    ## Returns (s, e) such as
    ## q == s * 2^e + 1
    s = Fq.order() - 1
    e = 0
    while s & 1 == 0:
        s >>= 1
        e += 1
    return s, e

def find_any_qnr(Fq):
    ## Find a quadratic Non-Residue
    ## in GF(p^m)
    qnr = Fq(Fq.gen())
    r = Fq.order()
    while qnr.is_square():
        qnr += 1
    return qnr

def sqrt_exponent_precomp(Fq, e):
    ## Returns precomputation a^((q-1-2^e)/(2*2^e))
    ##
    ## With 2^e the largest power of 2 that divides q-1
    ##
    ## For all sqrt related functions
    ## - legendre symbol
    ## - SQRT
    ## - inverse SQRT
    r = Fq.order()
    precomp = (r - 1) >> e       # (q-1) / 2^e
    precomp = (precomp - 1) >> 1 # ((q-1) / 2^e) - 1) / 2 = (q-1-2^e)/2^e / 2
    return precomp

s, e = precomp_ts(Fp)
qnr = find_any_qnr(Fp)
root_unity = qnr^s
exponent = sqrt_exponent_precomp(Fp, e)

# print('tonelli        s: 0x' + Integer(s).hex())
print('tonelli e (2-adicity): ' + str(e))
print('tonelli          root: 0x' + Integer(root_unity).hex())
print('tonelli      exponent: 0x' + Integer(exponent).hex())

def legendre_symbol_impl(a, e, a_pre_exp):
    ## Legendre symbol χ(a) = a^(q-1)/2
    ## -1 if a is non-square
    ## 0 if a is 0
    ## 1 if a is square
    ##
    ## a_pre_exp = a^((q-1-2^e)/(2*2^e))
    ## with
    ##  s and e, precomputed values
    ##  such as q == s * 2^e + 1
    ##
    ## a_pre_exp is used in square root
    ## and or inverse square root computation
    ##
    ## for fused operations
    r = a_pre_exp * a_pre_exp # a^((q-1-2^e)/2^e) = a^((q-1)/2^e - 1)
    r *= a                    # a^((q-1)/2^e)
    for i in range(0, e-1):
        r *= r                # a^((q-1)/2)

    return r

def legendre_symbol(a):
    a_pre_exp = a^exponent
    return legendre_symbol_impl(a, e, a_pre_exp)

for a in range(20):
    assert kronecker(a, p) == legendre_symbol(GF(p)(a))

def sqrt_tonelli_shanks_impl(a, a_pre_exp, s, e, root_of_unity):
    ## Square root for any `a` in a field of prime characteristic p
    ##
    ## a_pre_exp = a^((q-1-2^e)/(2*2^e))
    ## with
    ##  s and e, precomputed values
    ##  such as q == s * 2^e + 1
    z = a_pre_exp
    t = z*z*a
    r = z * a
    b = t
    root = root_of_unity
    for i in range(e, 1, -1):   # e .. 2
        for j in range(1, i-1): # 1 .. i-2
            b *= b
        doCopy = b != 1
        r = ccopy(r, r * root, doCopy)
        root *= root
        t = ccopy(t, t * root, doCopy)
        b = t
    return r

def sqrt_tonelli_shanks_opt(a):
    a_pre_exp = a^exponent
    return sqrt_tonelli_shanks_impl(a, a_pre_exp, s, e, root_unity)

# for a in range(2, 30):
#     if kronecker(a, p) != 1:
#         continue
#     # print(f'{a}^(p-1)/2 = ' + str(GF(p)(a)^((p-1)/2)))
#     print(f'{a} is a quadratic residue mod p')
#     b = sqrt_tonelli_shanks_opt(GF(p)(a))
#     # print(f'{b}² = {a} mod p')
#     # print('b*b = ' + str(b*b))
#     assert b*b == a

def sqrt_inv_sqrt_tonelli_shanks_impl(a, a_pre_exp, s, e, root_of_unity):
    ## Square root and inverse square root for any `a` in a field of prime characteristic p
    ##
    ## a_pre_exp = a^((q-1-2^e)/(2*2^e))
    ## with
    ##  s and e, precomputed values
    ##  such as q == s * 2^e + 1

    # Implementation
    # 1/√a * a = √a
    # Notice that in Tonelli Shanks, the result `r` is bootstrapped by "z*a"
    # We bootstrap it instead by just z to get invsqrt for free

    z = a_pre_exp
    t = z*z*a
    r = z
    b = t
    root = root_of_unity
    for i in range(e, 1, -1):   # e .. 2
        for j in range(1, i-1): # 1 .. i-2
            b *= b
        doCopy = b != 1
        r = ccopy(r, r * root, doCopy)
        root *= root
        t = ccopy(t, t * root, doCopy)
        b = t
    return r*a, r

def sqrt_invsqrt_tonelli_shanks_opt(a):
    a_pre_exp = a^exponent
    return sqrt_inv_sqrt_tonelli_shanks_impl(a, a_pre_exp, s, e, root_unity)

for a in range(2, 30):
    if kronecker(a, p) != 1:
        continue
    # print(f'{a}^(p-1)/2 = ' + str(GF(p)(a)^((p-1)/2)))
    print(f'{a} is a quadratic residue mod p')
    b, invb = sqrt_invsqrt_tonelli_shanks_opt(GF(p)(a))
    # print(f'{b}² = {a} mod p')
    # print('b*b = ' + str(b*b))
    assert b*b == a
    assert invb*a == b
