# Elliptic Curves

This folder will hold the implementation of elliptic curves arithmetic

## Terminology

### Coordinates system

The point P of the curve `y² = x³ + ax + b)` have the following coordinate:

- `(x, y)` in the affine coordinate system
- `(X, Y, Z)` with `X = xZ` and `Y = yZ` in the homogeneous projective coordinate system.
  The homogeneous projective coordinates will be called projective coordinates from now on.
- `(X, Y, Z)` with `X = xZ²` and `Y = yZ³` in the jacobian projective coordinate system.
  The jacobian projective coordinates will be called jacobian coordinates from now on.

## Operations on a Twist

Pairings require operation on a twisted curve. Formulas are available
in Costello2009 and Ionica2017 including an overview of which coordinate system (affine, homogeneous projective or jacobian) is the most efficient for the Miller loop.

In particular for sextic twist (applicable to BN and BLS12 families), the projective coordinates are more efficient while for quadratic and quartic twists, jacobian coordinates ar emore efficient.

When the addition law requires the `a` or `b` parameter from the curve Scott2009 and Nogami2010 give the parameter relevant to the twisted curve for the M-Twist (multiplication by non-residue) or D-Twist (Division by non-residue) cases.

## Side-Channel resistance

### Scalar multiplication

Scalar multiplication of a point `P` by a scalar `k` and denoted `R = [k]P` (or `R = kP`)
is a critical operation to make side-channel resistant.

Elliptic Curve-based signature scheme indeed rely on the fact that computing the inverse of elliptic scalar multiplication is intractable to produce a public key `[k]P` from
the secret (integer) key `k`. The problem is called ECDLP, Elliptic Curve Discrete Logarithm Problem in the litterature.

Scalar multiplication for elliptic curve presents the same constant-time challenge as square-and-multiply, a naive implementation will leak every bit of the secret key:
```
  N ← P
  R ← 0
  for i from 0 to log2(k) do
     if k.bit(i) == 1 then
         Q ← point_add(Q, N)
     N ← point_double(N)
  return Q
```

### Point Addition and Doubling

#### Exceptions in elliptic curve group laws.

For an elliptic curve in short Weierstrass form: `y² = x³ + ax + b`

The equation for elliptic curve addition is in affine (x, y) coordinates:

```
P + Q = R
(Px, Py) + (Qx, Qy) = (Rx, Ry)

with
Rx = λ² - Px - Qx
Ry = λ(Px - Rx) - Py
```
but in the case of addition
```
λ = (Qy - Py) / (Qx - Px)
```
which is undefined for P == Q or P == -Q (as `-(x, y) = (x, -y)`)

the doubling formula uses the slope of the tangent at the limit

```
λ = (3 Px² + a) / (2 Px)
```

So we have to take into account 2 special-cases.

Furthermore when using (homogeneous) projective or jacobian coordinates, most formulæ
needs to special-case the point at infinity.

#### Dealing with exceptions

An addition formula that works for both addition and doubling (adding the same point) is called **unified**.
An addition formula that works for all inputs including adding infinity point or the same point is called **complete** or **exception-free**.

Abarúa2019 highlight several attacks, their defenses, counterattacks and counterdefenses
on elliptic curve implementations.

We use the complete addition law from Renes2015 for projective coordinates, note that the prime order requirement can be relaxed to odd order according to the author.

We use the complete addition law from Bos2014 for Jacobian coordinates, note that there is a prime order requirement.

## References

- Pairing-Friendly Curves\
  (Draft, expires May 4, 2020)\
  https://tools.ietf.org/html/draft-irtf-cfrg-pairing-friendly-curves-00#section-2.1

- Survey for Performance & Security Problems of Passive Side-channel Attacks     Countermeasures in ECC\
  Rodrigo Abarúa, Claudio Valencia, and Julio López, 2019\
  https://eprint.iacr.org/2019/010

- Completing the Complete ECC Formulae with Countermeasures
  Łukasz Chmielewski, Pedro Maat Costa Massolino, Jo Vliegen, Lejla Batina and Nele Mentens, 2017\
  https://www.mdpi.com/2079-9268/7/1/3/pdf

- Pairings\
  Chapter 3 of Guide to Pairing-Based Cryptography\
  Sorina Ionica, Damien Robert, 2017\
  https://www.math.u-bordeaux.fr/~damienrobert/csi2018/pairings.pdf

- Complete addition formulas for prime order elliptic curves\
  Joost Renes and Craig Costello and Lejla Batina, 2015\
  https://eprint.iacr.org/2015/1060

- Selecting Elliptic Curves for Cryptography: An Efficiency and Security Analysis\
  Joppe W. Bos and Craig Costello and Patrick Longa and Michael Naehrig, 2014\
  https://eprint.iacr.org/2014/130
  https://www.imsc.res.in/~ecc14/slides/costello.pdf

- Efficient and Secure Algorithms for GLV-Based Scalar\
  Multiplication and their Implementation\
  on GLV-GLSCurves (Extended Version)\
  Armando Faz-Hernández, Patrick Longa, Ana H. Sánchez, 2013\
  https://eprint.iacr.org/2013/158.pdf

- Remote Timing Attacks are Still Practical\
  Billy Bob Brumley and Nicola Tuveri\
  https://eprint.iacr.org/2011/232

- State-of-the-art of secure ECC implementations:a survey on known side-channel attacks and countermeasures\
  Junfeng Fan,XuGuo, Elke De Mulder, Patrick Schaumont, Bart Preneel and Ingrid Verbauwhede, 2010
  https://www.esat.kuleuven.be/cosic/publications/article-1461.pdf

- Efficient Pairings on Twisted Elliptic Curve\
  Yasuyuki Nogami, Masataka Akane, Yumi Sakemi and Yoshitaka Morikawa, 2010\
  https://www.researchgate.net/publication/221908359_Efficient_Pairings_on_Twisted_Elliptic_Curve

- A note on twists for pairing friendly curves\
  Michael Scott, 2009\
  http://indigo.ie/~mscott/twists.pdf

- Faster Pairing Computations on Curves withHigh-Degree Twists\
  Craig Costello and Tanja Lange and Michael Naehrig, 2009
  https://eprint.iacr.org/2009/615

- Weierstraß Elliptic Curves and Side-Channel Attacks\
  Éric Brier and Marc Joye, 2002\
  http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.2.273&rep=rep1&type=pdf

- Efficient Elliptic Curve Exponentiation Using Mixed Coordinates\
  Henri Cohen, Atsuko Miyaji, Takatoshi Ono, 1998\
  https://link.springer.com/content/pdf/10.1007%2F3-540-49649-1_6.pdf

- Complete systems of Two Addition Laws for Elliptic Curve\
  Bosma and Lenstra, 1995\
  http://www.mat.uniroma3.it/users/pappa/CORSI/CR510_13_14/BosmaLenstra.pdf
