Deriving efficient and complete Jacobian formulae
=================================================

We are looking for a complete addition formula,
that minimize overhead over classic addition formulae
from the litterature
and can handle all inputs.

We recall the basic affine addition and doubling formulae

```
P + Q = R
(Px, Py) + (Qx, Qy) = (Rx, Ry)

with
  Rx = λ² - Px - Qx
  Ry = λ(Px - Rx) - Py
and
  λadd = (Qy - Py) / (Px - Qx)
  λdbl = (3 Px² + a) / (2 Px)
```

Which is also called the "chord-and-tangent" group law.
Notice that if Px == Qx, addition is undefined, this can happen in 2 cases
- P == Q, in that case we need to double
- P == -Q, since -(x,y) = (x,-y) for elliptic curves. In that case we need infinity.

Concretely, that means that it is non-trivial to make the code constant-time
whichever case we are.
Furthermore, Renes et al 2015 which introduced complete addition formulae for projective coordinates
demonstrated that such a law cannot be as efficient for the Jacobian coordinates we are interested in.

Since we can't rely on math, we will need to rely on implementation "details" to achieve our goals.
First we look back in history at Brier and Joye 2002 unified formulae which uses the same code for addition and doubling:

```
λ = ((x₁+x₂)² - x₁x₂ + a)/(y₁+y₂)
x₃ = λ² - (x₁+x₂)
2y₃= λ(x₁+x₂-2x₃) - (y₁+y₂)
```

Alas we traded exceptions depending on the same coordinate x
for exceptions on negated coordinate y.
This can still happen for P=-Q but also for "unrelated" numbers.
> We recall that curves with equation `y² = x³ + b` are chosen so that there exist a cubic root of unity modulo r the curve order.
> Hence x³ ≡ 1 (mod r), we call that root ω
> And so we have y² = (ωx)³ + b describing a valid point with coordinate (ωx, y)
> Hence the unified formula cannot handle (x, y) + (ωx, -y)
> All pairings curves and secp256k1 have that equation form.

Now, all hope is not lost, we recall that unlike in math,
in actual implementation we havean excellent tool called conditional copy
so that we can ninja-swap our terms
provided addition and doubling are resembling each other.

So let's look at the current state of the art formulae.
I have added the spots where we can detect special conditions like infinity points, doubling and negation,
and reorganized doubling operations so that they match multiplication/squarings in the addition law

Let's look first at Cohen et al, 1998 formulae

```
|    Addition - Cohen et al    |         Doubling any a - Cohen et al         |  Doubling = -3  | Doubling a = 0 |
| 12M + 4S + 6add + 1*2        | 3M + 6S + 1*a + 4add + 2*2 + 1*3 + 1*4 + 1*8 |                 |                |
|------------------------------|----------------------------------------------|-----------------|----------------|
| Z₁Z₁ = Z₁²                   | Z₁Z₁ = Z₁²                                   |                 |                |
| Z₂Z₂ = Z₂²                   |                                              |                 |                |
|                              |                                              |                 |                |
| U₁ = X₁*Z₂Z₂                 |                                              |                 |                |
| U₂ = X₂*Z₁Z₁                 |                                              |                 |                |
| S₁ = Y₁*Z₂*Z₂Z₂              |                                              |                 |                |
| S₂ = Y₂*Z₁*Z₁Z₁              |                                              |                 |                |
| H = U₂-U₁ # P=-Q, P=Inf, P=Q |                                              |                 |                |
| R = S₂-S₁ # Q=Inf            |                                              |                 |                |
|                              |                                              |                 |                |
| HH = H²                      | YY = Y₁²                                     |                 |                |
| HHH = H*HH                   | M = 3*X₁²+a*ZZ²                              | 3(X₁-Z₁)(X₁+Z₁) | 3*X₁²          |
| V = U₁*HH                    | S = 4*X₁*YY                                  |                 |                |
|                              |                                              |                 |                |
| X₃ = R²-HHH-2*V              | X₃ = M²-2*S                                  |                 |                |
| Y₃ = R*(V-X₃)-S₁*HHH         | Y₃ = M*(S-X₃)-8*YY²                          |                 |                |
| Z₃ = Z₁*Z₂*H                 | Z₃ = 2*Y₁*Z₁                                 |                 |                |
```

This is very promising, as the expensive multiplies and squares n doubling all have a corresponding sister operation.
Now for Bernstein et al 2007 formulae.

```
|    Addition - Bernstein et al    |          Doubling any a - Bernstein et al           |  Doubling = -3  | Doubling a = 0 |
| 11M + 5S + 9add + 4*2            | 1M + 8S + 1*a + 10add + 2*2 + 1*3 + 1*8             |                 |                |
|----------------------------------|-----------------------------------------------------|-----------------|----------------|
| Z₁Z₁ = Z₁²                       | Z₁Z₁ = Z₁²                                          |                 |                |
| Z₂Z₂ = Z₂²                       |                                                     |                 |                |
|                                  |                                                     |                 |                |
| U₁ = X₁*Z₂Z₂                     |                                                     |                 |                |
| U₂ = X₂*Z₁Z₁                     |                                                     |                 |                |
| S₁ = Y₁*Z₂*Z₂Z₂                  |                                                     |                 |                |
| S₂ = Y₂*Z₁*Z₁Z₁                  |                                                     |                 |                |
| H = U₂-U₁     # P=-Q, P=Inf, P=Q |                                                     |                 |                |
| R = 2*(S₂-S₁) # Q=Inf            |                                                     |                 |                |
|                                  |                                                     |                 |                |
|                                  | XX = X₁² (no matching op in addition, extra square) |                 |                |
|                                  | YYYY (no matching op in addition, extra 2 squares)  |                 |                |
|                                  |                                                     |                 |                |
| I = (2*H)²                       | YY = Y₁²                                            |                 |                |
| J = H*I                          | M = 3*X₁²+a*ZZ²                                     | 3(X₁-Z₁)(X₁+Z₁) | 3*X₁²          |
| V = U₁*I                         | S = 2*((X₁+YY)²-XX-YYYY) = 4*X₁*YY                  |                 |                |
|                                  |                                                     |                 |                |
| X₃ = R²-J-2*V                    | X₃ = M²-2*S                                         |                 |                |
| Y₃ = R*(V-X₃)-2*S₁*J             | Y₃ = M*(S-X₃)-8*YYYY                                |                 |                |
| Z₃ = ((Z₁+Z₂)²-Z₁Z₁-Z₂Z₂)*H      | Z₃ = (Y₁+Z₁)² - YY - ZZ = 2*Y₁*Z₁                   |                 |                |
```

Bernstein et al rewrites multiplication into squaring and 2 substraction.

The first thing to note is that we can't use that trick to compute S in doubling
and keep doubling resembling addition as we have not computed XX or YYYY yet
and have no auspicious place to do so before.

The second thing to note is that in the addition, they had to scale Z₃ by 2
which scaled X₃ by 4 and Y₃ by 8, leading to the doubling in I, r coefficients

Ultimately, it saves 1 mul but it costs 1S 3A 3*2. Here are some benchmarks for reference

| Operation | Fp[BLS12_381] (cycles) | Fp2[BLS12_381] (cycles) | Fp4[BLS12_381] (cycles) |
|-----------|------------------------|-------------------------|-------------------------|
| Add       | 14                     | 24                      | 47                      |
| Sub       | 12                     | 24                      | 46                      |
| Ccopy     | 5                      | 10                      | 20                      |
| Div2      | 14                     | 23                      | 42                      |
| Mul       | 81                     | 337                     | 1229                    |
| Sqr       | 81                     | 231                     | 939                     |

On G1 this is not good enough
On G2 it is still not good enough
On G4 (BLS24) or G8 (BLS48) we can revisit the decision.

Let's focus back to Cohen formulae

```
|    Addition - Cohen et al    |         Doubling any a - Cohen et al         |  Doubling = -3  | Doubling a = 0 |
| 12M + 4S + 6add + 1*2        | 3M + 6S + 1*a + 4add + 2*2 + 1*3 + 1*4 + 1*8 |                 |                |
|------------------------------|----------------------------------------------|-----------------|----------------|
| Z₁Z₁ = Z₁²                   | Z₁Z₁ = Z₁²                                   |                 |                |
| Z₂Z₂ = Z₂²                   |                                              |                 |                |
|                              |                                              |                 |                |
| U₁ = X₁*Z₂Z₂                 |                                              |                 |                |
| U₂ = X₂*Z₁Z₁                 |                                              |                 |                |
| S₁ = Y₁*Z₂*Z₂Z₂              |                                              |                 |                |
| S₂ = Y₂*Z₁*Z₁Z₁              |                                              |                 |                |
| H = U₂-U₁ # P=-Q, P=Inf, P=Q |                                              |                 |                |
| R = S₂-S₁ # Q=Inf            |                                              |                 |                |
|                              |                                              |                 |                |
| HH = H²                      | YY = Y₁²                                     |                 |                |
| HHH = H*HH                   | M = 3*X₁²+a*ZZ²                              | 3(X₁-Z₁)(X₁+Z₁) | 3*X₁²          |
| V = U₁*HH                    | S = 4*X₁*YY                                  |                 |                |
|                              |                                              |                 |                |
| X₃ = R²-HHH-2*V              | X₃ = M²-2*S                                  |                 |                |
| Y₃ = R*(V-X₃)-S₁*HHH         | Y₃ = M*(S-X₃)-8*YY²                          |                 |                |
| Z₃ = Z₁*Z₂*H                 | Z₃ = 2*Y₁*Z₁                                 |                 |                |
```

> Reminder: Jacobian coordinates are related to affine coordinate
>           the following way (X, Y) <-> (X Z², Y Z³, Z)

The 2, 4, 8 coefficients in respectively `Z₃=2Y₁Z₁`, `S=4X₁YY` and `Y₃=M(S-X₃)-8YY²`
are not in line with the addition.
2 solutions:
- either we scale the addition Z₃ by 2, which will scale X₃ by 4 and Y₃ by 8 just like Bernstein et al.
- or we scale the doubling Z₃ by ½, which will scale X₃ by ¼ and Y₃ by ⅛. This is what Bos et al 2014 does for a=-3 curves.

We generalize their approach to all curves and obtain

```
|    Addition (Cohen et al)     | Doubling any a (adapted Bos et al, Cohen et al) |   Doubling = -3   | Doubling a = 0 |
|     12M + 4S + 6add + 1*2     |    3M + 6S + 1*a + 4add + 1*2 + 1*3 + 1half     |                   |                |
| ----------------------------- | ----------------------------------------------- | ----------------- | -------------- |
| Z₁Z₁ = Z₁²                    | Z₁Z₁ = Z₁²                                      |                   |                |
| Z₂Z₂ = Z₂²                    |                                                 |                   |                |
|                               |                                                 |                   |                |
| U₁ = X₁*Z₂Z₂                  |                                                 |                   |                |
| U₂ = X₂*Z₁Z₁                  |                                                 |                   |                |
| S₁ = Y₁*Z₂*Z₂Z₂               |                                                 |                   |                |
| S₂ = Y₂*Z₁*Z₁Z₁               |                                                 |                   |                |
| H  = U₂-U₁ # P=-Q, P=Inf, P=Q |                                                 |                   |                |
| R  = S₂-S₁ # Q=Inf            |                                                 |                   |                |
|                               |                                                 |                   |                |
| HH  = H²                      | YY = Y₁²                                        |                   |                |
| HHH = H*HH                    | M  = (3*X₁²+a*ZZ²)/2                            | 3(X₁-Z₁)(X₁+Z₁)/2 | 3X₁²/2         |
| V   = U₁*HH                   | S  = X₁*YY                                      |                   |                |
|                               |                                                 |                   |                |
| X₃ = R²-HHH-2*V               | X₃ = M²-2*S                                     |                   |                |
| Y₃ = R*(V-X₃)-S₁*HHH          | Y₃ = M*(S-X₃)-YY²                               |                   |                |
| Z₃ = Z₁*Z₂*H                  | Z₃ = Y₁*Z₁                                      |                   |                |
```

So we actually replaced 1 doubling, 1 quadrupling, 1 octupling by 1 halving, which has the same cost as doubling/addition.
We could use that for elliptic curve over Fp and Fp2.
For elliptic curve over Fp4 and Fp8 (BLS24 and BLS48) the gap between multiplication and square is large enough
that replacing a multiplication by squaring + 2 substractions and extra bookkeeping is worth it,
we could use this formula instead:

```
| Addition (adapted Bernstein et al) |     Doubling any a (adapted Bernstein)   |  Doubling = -3  | Doubling a = 0 |
|       11M + 5S + 9add + 4*2        | 2M + 7S + 1*a + 7add + 2*2+1*3+1*4+1*8   |                 |                |
| ---------------------------------- | ---------------------------------------- | --------------- | -------------- |
| Z₁Z₁ = Z₁²                         | Z₁Z₁ = Z₁²                               |                 |                |
| Z₂Z₂ = Z₂²                         |                                          |                 |                |
|                                    |                                          |                 |                |
| U₁ = X₁*Z₂Z₂                       |                                          |                 |                |
| U₂ = X₂*Z₁Z₁                       |                                          |                 |                |
| S₁ = Y₁*Z₂*Z₂Z₂                    |                                          |                 |                |
| S₂ = Y₂*Z₁*Z₁Z₁                    |                                          |                 |                |
| H = U₂-U₁     # P=-Q, P=Inf, P=Q   |                                          |                 |                |
| R = 2*(S₂-S₁) # Q=Inf              |                                          |                 |                |
|                                    |                                          |                 |                |
| I = (2*H)²                         | YY = Y₁²                                 |                 |                |
| J = H*I                            | M  = 3*X₁²+a*ZZ²                         | 3(X₁-Z₁)(X₁+Z₁) | 3*X₁²          |
| V = U₁*I                           | S  = 4*X₁*YY                             |                 |                |
|                                    |                                          |                 |                |
| X₃ = R²-J-2*V                      | X₃ = M²-2*S                              |                 |                |
| Y₃ = R*(V-X₃)-2*S₁*J               | Y₃ = M*(S-X₃)-8*YY²                      |                 |                |
| Z₃ = ((Z₁+Z₂)²-Z₁Z₁-Z₂Z₂)*H        | Z₃ = (Y₁+Z₁)² - YY - ZZ                  |                 |                |
```
