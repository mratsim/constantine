# Tower Extensions of Finite Fields

## Overview

From Ben Edgington, https://hackmd.io/@benjaminion/bls12-381

> ### Field extensions
>
> Field extensions are fundamental to elliptic curve pairings. The "12" is BLS12-381 is not only the embedding degree, it is also (relatedly) the degree of field extension that we will need to use.
>
> The field $F_q$ can be thought of as just the integers modulo $q$: $0,1,...,q-1$. But what kind of beast is $F_{q^{12}}$, the twelfth extension of $F_q$?
>
> I totally failed to find any straightforward explainers of field extensions out there, so here's my attempt after wrestling with this for a while.
>
> Let's construct an $F_{q^2}$, the quadratic extension of $F_q$. In $F_{q^2}$ we will represent field elements as first-degree polynomials like $a_0 + a_1x$, which we can write more concisely as $(a_0, a_1)$ if we wish.
>
> Adding two elements is easy: $(a, b) + (c, d) =$$a + bx + c + dx =$$(a+c) + (b+d)x =$$(a+c, b+d)$. We just need to be sure to reduce $a+c$ and $b+d$ modulo $q$.
>
> What about multiplying? $(a, b) \times (c, d) =$$(a + bx)(c + dx) =$$ac + (ad+bc)x+ bdx^2 =$$???$. Oops - what are we supposed to do with that $x^2$ coefficient?
>
> We need a rule for reducing polynomials so that they have a degree less than two. In this example we're going to take $x^2 + 1 = 0$ as our rule, but we could make other choices. There are only two rules about our rule^[Our rule is "an extension field modular reduction" (terminology from [here](https://www.emsec.ruhr-uni-bochum.de/media/crypto/veroeffentlichungen/2015/03/26/crypto98rc9.pdf)).]:
>  1. it must be a degree $k$ polynomial, where $k$ is our extension degree, $2$ in this case; and
>  2. it must be [irreducible](https://en.wikipedia.org/wiki/Irreducible_polynomial) in the field we are extending. That means it must not be possible to factor it into two or more lower degree polynomials.
>
> Applying our rule, by substituting $x^2 = -1$, gives us the final result $(a, b) \times (c, d) =$$ac + (ad+bc)x + bdx^2 =$$(ac-bd) + (ad+bc)x =$$(ac-bd, ad+bc)$. This might look a little familiar from complex arithmetic: $(a+ib) \times (c+id) =$$(ac-bd) + (ad+bc)i$. This is not a coincidence! The complex numbers are a quadratic extension of the real numbers.
>
> Complex numbers can't be extended any further because there are [no irreducible polynomials over the complex numbers](https://en.wikipedia.org/wiki/Fundamental_theorem_of_algebra). But for finite fields, if we can find an irreducible $k$-degree polynomial in our field $F_q$, and we often can, then we are able to extend the field to $F_{qᵏ}$, and represent the elements of the extended field as degree $k-1$ polynomials, $a_0 + a_1x +$$...$$+ a_{k-1}x^{k-1}$. We can represent this compactly as $(a_0,...,a_{k-1})$, as long as we remember that there may be some very funky arithmetic going on.
>
> Also worth noting is that modular reductions like this (our reduction rule) can be chosen so that they play nicely with the twisting operation.
>
> In practice, large extension fields like $F_{q^{12}}$ are implemented as towers of smaller extensions. That's an implementation aspect, so I've put it in the more practical section [below](#Extension-towers).
>
> ### Extension towers
>
> Recall our discussion of [field extensions](#Field-extensions)? In practice, rather than implementing a massive 12th-degree extension directly, it is more efficient to build it up from smaller extensions: [a tower of extensions](https://eprint.iacr.org/2009/556.pdf).
>
> For BLS12-381, the $F_{q^{12}}$ field is implemented as a quadratic (degree two) extension, on top of a cubic (degree three) extension, on top of a quadratic extension of $F_q$.
>
> As long as the modular reduction polynomial (our reduction rule) is irreducible (can't be factored) in the field being extended at each stage, then this all works out fine.
>
> [Specifically](https://github.com/zkcrypto/pairing/tree/master/src/bls12_381):
>
>   1. $F_{q^2}$ is constructed as $F_q(u) / (u^2 - \beta)$ where $\beta = -1$.
>   2. $F_{q^6}$ is constructed as $F_{q^2}(v) / (v^3 - \xi)$ where $\xi = u + 1$.
>   3. $F_{q^{12}}$ is constructed as $F_{q^6}(w) / (w^2 - \gamma)$ where $\gamma = v$
>
> Interpreting these in terms of our previous explantation:
>   1. We write elements of the $F_{q^2}$ field as first degree polynomials in $u$, with coefficients from $F_q$, and apply the reduction rule $u^2 + 1 = 0$, which is irreducible in $F_q$.
>       - an element of $F_{q^2}$ looks like $a_0 + a_1u$ where $a_j \in F_q$.
>   3. We write elements of the $F_{q^6}$ field as second degree polynomials in $v$, with coefficients from the $F_{q^2}$ field we just constructed, and apply the reduction rule $v^3 - (u + 1) = 0$, which is irreducible in $F_{q^2}$.
>       - an element of $F_{q^6}$ looks like $b_0 + b_1v + b_2v^2$ where $b_j \in F_{q^2}$.
>   4. We write elements of the $F_{q^{12}}$ field as first degree polynomials in $w$, with coefficients from the $F_{q^6}$ field we just constructed, and apply the reduction rule $w^2 - v = 0$, which is irreducible in $F_{q^6}$.
>       - an element of $F_{q^{12}}$ looks like $c_0 + c_1w$ where $c_j \in F_{q^6}$.
>
> This towered extension can replace the direct extension as a basis for pairings, and when well-implemented can save a huge amount of arithmetic when multiplying $F_{q^{12}}$ points. See [Pairings for Beginners](http://www.craigcostello.com.au/pairings/PairingsForBeginners.pdf) section 7.3 for a full discussion of the advantages.


## References

### Research

- Optimal Extension Fields for Fast Arithmetic in Public-Key Algorithms\
  Daniel V. Bailey and Christof Paar, 1998\
  https://www.emsec.ruhr-uni-bochum.de/media/crypto/veroeffentlichungen/2015/03/26/crypto98rc9.pdf

- Asymmetric Squaring Formulae\
  Jaewook Chung and M. Anwar Hasan\
  http://cacr.uwaterloo.ca/techreports/2006/cacr2006-24.pdf

- Multiplication and Squaring on Pairing-Friendly Fields\
  Augusto Jun Devegili and Colm Ó hÉigeartaigh and Michael Scott and Ricardo Dahab, 2006\
  https://eprint.iacr.org/2006/471

- Software Implementation of Pairings\
  D. Hankerson, A. Menezes, and M. Scott, 2009\
  http://cacr.uwaterloo.ca/~ajmeneze/publications/pairings_software.pdf

- Constructing Tower Extensions for the implementation of Pairing-Based Cryptography\
  Naomi Benger and Michael Scott, 2009\
  https://eprint.iacr.org/2009/556

- Faster Squaring in the Cyclotomic Subgroup of Sixth Degree Extensions\
  Robert Granger and Michael Scott, 2009\
  https://eprint.iacr.org/2009/565.pdf

- High-Speed Software Implementation of the Optimal Ate Pairing over Barreto-Naehrig Curves\
  Jean-Luc Beuchat and Jorge Enrique González Díaz and Shigeo Mitsunari and Eiji Okamoto and Francisco Rodríguez-Henríquez and Tadanori Teruya, 2010\
  https://eprint.iacr.org/2010/354

- Faster Explicit Formulas for Computing Pairings over Ordinary Curves\
  Diego F. Aranha and Koray Karabina and Patrick Longa and Catherine H. Gebotys and Julio López, 2010\
  https://eprint.iacr.org/2010/526.pdf\
  https://www.iacr.org/archive/eurocrypt2011/66320047/66320047.pdf

- Efficient Implementation of Bilinear Pairings on ARM Processors
  Gurleen Grewal, Reza Azarderakhsh,
  Patrick Longa, Shi Hu, and David Jao, 2012
  https://eprint.iacr.org/2012/408.pdf

- Choosing and generating parameters for low level pairing implementation on BN curves\
  Sylvain Duquesne and Nadia El Mrabet and Safia Haloui and Franck Rondepierre, 2015\
  https://eprint.iacr.org/2015/1212

- Arithmetic of Finite Fields\
  Chapter 5 of Guide to Pairing-Based Cryptography\
  Jean Luc Beuchat, Luis J. Dominguez Perez, Sylvain Duquesne, Nadia El Mrabet, Laura Fuentes-Castañeda, Francisco Rodríguez-Henríquez, 2017\
  https://www.researchgate.net/publication/319538235_Arithmetic_of_Finite_Fields

### Presentations

- BLS12-381 For The Rest Of Us\
  Ben Edgington, 2019\
  https://hackmd.io/@benjaminion/bls12-381
