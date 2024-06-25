# Common configuration

- Low-level logical and physical word definitions
- Elliptic curve declarations
- Cipher suites

## Algorithms


### Modular inverses mod 2ⁿ

We use "Dumas iterations" to precompute Montgomery magic number `-1/n[0] (mod 2^Wordbitwidth)`

Explanation p11 "Dumas iterations" based on Newton-Raphson:
- Cetin Kaya Koc (2017), https://eprint.iacr.org/2017/411
- Jean-Guillaume Dumas (2012), https://arxiv.org/pdf/1209.6626v2.pdf
- Colin Plumb (1994), http://groups.google.com/groups?selm=1994Apr6.093116.27805%40mnemosyne.cs.du.edu
Other sources:
- https://crypto.stackexchange.com/questions/47493/how-to-determine-the-multiplicative-inverse-modulo-64-or-other-power-of-two
- https://mumble.net/~campbell/2015/01/21/inverse-mod-power-of-two
- http://marc-b-reynolds.github.io/math/2017/09/18/ModInverse.html
