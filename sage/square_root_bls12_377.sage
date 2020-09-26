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

for a in range(2, 30):
    if kronecker(a, p) != 1:
        continue
    # print(f'{a}^(p-1)/2 = ' + str(GF(p)(a)^((p-1)/2)))
    print(f'{a} is a quadratic residue mod p')
    b = sqrt_tonelli_shanks(a, p)
    # print(f'{b}² = {a} mod p')
    # print('b*b = ' + str(b*b))
    assert b*b == a
