# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../primitives,
  ../config/[common, curves],
  ../arithmetic,
  ../towers,
  ../isogeny/frobenius

# No exceptions allowed
{.push raises: [].}

# ############################################################
#
#                Gϕₙ, Cyclotomic subgroup of Fpⁿ
#         with Gϕₙ(p) = {α ∈ Fpⁿ : α^Φₙ(p) ≡ 1 (mod pⁿ)}
#
# ############################################################

# - Faster Squaring in the Cyclotomic Subgroup of Sixth Degree Extensions
#   Granger, Scott, 2009
#   https://eprint.iacr.org/2009/565.pdf
#
# - On the final exponentiation for calculating
#   pairings on ordinary elliptic curves
#   Scott, Benger, Charlemagne, Perez, Kachisa, 2008
#   https://eprint.iacr.org/2008/490.pdf

# 𝔽pⁿ -> Gϕₙ - Mapping to Cyclotomic group
# ----------------------------------------------------------------

func finalExpEasy*[C: static Curve](f: var Fp6[C]) {.meter.} =
  ## Easy part of the final exponentiation
  ##
  ## This maps the result of the Miller loop into the cyclotomic subgroup Gϕ₆
  ##
  ## We need to clear the Gₜ cofactor to obtain
  ## an unique Gₜ representation
  ## (reminder, Gₜ is a multiplicative group hence we exponentiate by the cofactor)
  ##
  ## i.e. Fp⁶ --> (fexp easy) --> Gϕ₆ --> (fexp hard) --> Gₜ
  ##
  ## The final exponentiation is fexp = f^((p⁶ - 1) / r)
  ## It is separated into:
  ## f^((p⁶ - 1) / r) = (p⁶ - 1) / ϕ₆(p)  * ϕ₆(p) / r
  ##
  ## with the cyclotomic polynomial ϕ₆(p) = (p²-p+1)
  ##
  ## With an embedding degree of 6, the easy part of final exponentiation is
  ##
  ##  f^(p³−1)(p+1)
  ##
  ## And properties are
  ## 0. f^(p³) ≡ conj(f) (mod p⁶) for all f in Fp6
  ##
  ## After g = f^(p³−1) the result g is on the cyclotomic subgroup
  ## 1. g^(-1) ≡ g^(p³) (mod p⁶)
  ## 2. Inversion can be done with conjugate
  ## 3. g is unitary, its norm |g| (the product of conjugates) is 1
  ## 4. Squaring has a fast compressed variant.
  #
  # Proofs:
  #
  # Fp6 can be defined as a quadratic extension over Fp³
  # with g = g₀ + x g₁ with x a quadratic non-residue
  #
  # with q = p³, q² = p⁶
  # The frobenius map f^q ≡ (f₀ + x f₁)^q (mod q²)
  #                       ≡ f₀^q + x^q f₁^q (mod q²)
  #                       ≡ f₀ + x^q f₁ (mod q²)
  #                       ≡ f₀ - x f₁ (mod q²)
  # hence
  # f^p³ ≡ conj(f) (mod p⁶)
  # Q.E.D. of (0)
  #
  # ----------------
  #
  # p⁶ - 1 = (p³−1)(p³+1) = (p³−1)(p+1)(p²-p+1)
  # by Fermat's little theorem we have
  # f^(p⁶ - 1) ≡ 1 (mod p⁶)
  #
  # Hence f^(p³−1)(p³+1) ≡ 1 (mod p⁶)
  #
  # We call g = f^(p³−1) we have
  # g^(p³+1) ≡ 1 (mod p⁶) <=> g^(p³) * g ≡ 1 (mod p⁶)
  # hence g^(-1) ≡ g^(p³) (mod p⁶)
  # Q.E.D. of (1)
  #
  # --
  #
  # From (1) g^(-1) ≡ g^(p³) (mod p⁶) for g = f^(p³−1)
  # and  (0) f^p³ ≡ conj(f) (mod p⁶)  for all f in fp12
  #
  # so g^(-1) ≡ conj(g) (mod p⁶) for g = f^(p³−1)
  # Q.E.D. of (2)
  #
  # --
  #
  # f^(p⁶ - 1) ≡ 1 (mod p⁶) by Fermat's Little Theorem
  # f^(p³−1)(p³+1) ≡ 1 (mod p⁶)
  # g^(p³+1) ≡ 1 (mod p⁶)
  # g * g^p³ ≡ 1 (mod p⁶)
  # g * conj(g) ≡ 1 (mod p⁶)
  # Q.E.D. of (3)
  var g {.noinit.}: typeof(f)
  g.inv(f)              # g = f^-1
  conj(f)               # f = f^p³
  g *= f                # g = f^(p³-1)
  f.frobenius_map(g)    # f = f^((p³-1) p)
  f *= g                # f = f^((p³-1) (p+1))

func finalExpEasy*[C: static Curve](f: var Fp12[C]) {.meter.} =
  ## Easy part of the final exponentiation
  ##
  ## This maps the result of the Miller loop into the cyclotomic subgroup Gϕ₁₂
  ##
  ## We need to clear the Gₜ cofactor to obtain
  ## an unique Gₜ representation
  ## (reminder, Gₜ is a multiplicative group hence we exponentiate by the cofactor)
  ##
  ## i.e. Fp¹² --> (fexp easy) --> Gϕ₁₂ --> (fexp hard) --> Gₜ
  ##
  ## The final exponentiation is fexp = f^((p¹² - 1) / r)
  ## It is separated into:
  ## f^((p¹² - 1) / r) = (p¹² - 1) / ϕ₁₂(p)  * ϕ₁₂(p) / r
  ##
  ## with the cyclotomic polynomial ϕ₁₂(p) = (p⁴-p²+1)
  ##
  ## With an embedding degree of 12, the easy part of final exponentiation is
  ##
  ##  f^(p⁶−1)(p²+1)
  ##
  ## And properties are
  ## 0. f^(p⁶) ≡ conj(f) (mod p¹²) for all f in Fp12
  ##
  ## After g = f^(p⁶−1) the result g is on the cyclotomic subgroup
  ## 1. g^(-1) ≡ g^(p⁶) (mod p¹²)
  ## 2. Inversion can be done with conjugate
  ## 3. g is unitary, its norm |g| (the product of conjugates) is 1
  ## 4. Squaring has a fast compressed variant.
  #
  # Proofs:
  #
  # Fp12 can be defined as a quadratic extension over Fp⁶
  # with g = g₀ + x g₁ with x a quadratic non-residue
  #
  # with q = p⁶, q² = p¹²
  # The frobenius map f^q ≡ (f₀ + x f₁)^q (mod q²)
  #                       ≡ f₀^q + x^q f₁^q (mod q²)
  #                       ≡ f₀ + x^q f₁ (mod q²)
  #                       ≡ f₀ - x f₁ (mod q²)
  # hence
  # f^p⁶ ≡ conj(f) (mod p¹²)
  # Q.E.D. of (0)
  #
  # ----------------
  #
  # p¹² - 1 = (p⁶−1)(p⁶+1) = (p⁶−1)(p²+1)(p⁴-p²+1)
  # by Fermat's little theorem we have
  # f^(p¹² - 1) ≡ 1 (mod p¹²)
  #
  # Hence f^(p⁶−1)(p⁶+1) ≡ 1 (mod p¹²)
  #
  # We call g = f^(p⁶−1) we have
  # g^(p⁶+1) ≡ 1 (mod p¹²) <=> g^(p⁶) * g ≡ 1 (mod p¹²)
  # hence g^(-1) ≡ g^(p⁶) (mod p¹²)
  # Q.E.D. of (1)
  #
  # --
  #
  # From (1) g^(-1) ≡ g^(p⁶) (mod p¹²) for g = f^(p⁶−1)
  # and  (0) f^p⁶ ≡ conj(f) (mod p¹²)  for all f in fp12
  #
  # so g^(-1) ≡ conj(g) (mod p¹²) for g = f^(p⁶−1)
  # Q.E.D. of (2)
  #
  # --
  #
  # f^(p¹² - 1) ≡ 1 (mod p¹²) by Fermat's Little Theorem
  # f^(p⁶−1)(p⁶+1) ≡ 1 (mod p¹²)
  # g^(p⁶+1) ≡ 1 (mod p¹²)
  # g * g^p⁶ ≡ 1 (mod p¹²)
  # g * conj(g) ≡ 1 (mod p¹²)
  # Q.E.D. of (3)
  var g {.noinit.}: typeof(f)
  g.inv(f)              # g = f^-1
  conj(f)               # f = f^p⁶
  g *= f                # g = f^(p⁶-1)
  f.frobenius_map(g, 2) # f = f^((p⁶-1) p²)
  f *= g                # f = f^((p⁶-1) (p²+1))

# Gϕₙ - Cyclotomic functions
# ----------------------------------------------------------------
# A cyclotomic group is a subgroup of Fpⁿ defined by
#
# Gϕₙ(p) = {α ∈ Fpⁿ : α^Φₙ(p) = 1}
#
# The result of any pairing is in a cyclotomic subgroup

func cyclotomic_inv*[FT](a: var FT) {.meter.} =
  ## Fast inverse for a
  ## `a` MUST be in the cyclotomic subgroup
  ## consequently `a` MUST be unitary
  a.conj()

func cyclotomic_inv*[FT](r: var FT, a: FT) {.meter.} =
  ## Fast inverse for a
  ## `a` MUST be in the cyclotomic subgroup
  ## consequently `a` MUST be unitary
  r.conj(a)

func cyclotomic_square*[FT](r: var FT, a: FT) {.meter.} =
  ## Square `a` into `r`
  ## `a` MUST be in the cyclotomic subgroup
  ## consequently `a` MUST be unitary
  #
  # Faster Squaring in the Cyclotomic Subgroup of Sixth Degree Extensions
  # Granger, Scott, 2009
  # https://eprint.iacr.org/2009/565.pdf

  when a is CubicExt:
    # Cubic extension field
    # A = 3a² − 2 ̄a
    # B = 3 √i c² + 2 ̄b
    # C = 3b² − 2 ̄c
    var t0{.noinit.}, t1{.noinit.}: typeof(a.c0)

    t0.square(a.c0)     # t0 = a²
    t1.double(t0)       # t1 = 2a²
    t1 += t0            # t1 = 3a²

    t0.conj(a.c0)       # t0 =  ̄a
    t0.double()         # t0 =  2 ̄a
    r.c0.diff(t1, t0)   # r0 = 3a² − 2 ̄a

    # Aliasing: a.c0 unused

    t0.square(a.c2)     # t0 = c²
    t0 *= NonResidue    # t0 = √i c²
    t1.double(t0)       # t1 = 2 √i c²
    t0 += t1            # t0 = 3 √i c²

    t1.square(a.c1)     # t1 = b²

    r.c1.conj(a.c1)     # r1 = ̄b
    r.c1.double()       # r1 = 2 ̄b
    r.c1 += t0          # r1 = 3 √i c² + 2 ̄b

    # Aliasing: a.c1 unused

    t0.double(t1)       # t0 = 2b²
    t0 += t1            # t0 = 3b²

    t1.conj(a.c2)       # r2 =  ̄c
    t1.double()         # r2 =  2 ̄c
    r.c2.diff(t0, t1)   # r2 = 3b² - 2 ̄c

  else:
    {.error: "Not implemented".}

func cyclotomic_square*[FT](a: var FT) {.meter.} =
  ## Square `a` into `r`
  ## `a` MUST be in the cyclotomic subgroup
  ## consequently `a` MUST be unitary
  #
  # Faster Squaring in the Cyclotomic Subgroup of Sixth Degree Extensions
  # Granger, Scott, 2009
  # https://eprint.iacr.org/2009/565.pdf
  a.cyclotomic_square(a)

func cycl_sqr_repeated*[FT](f: var FT, num: int) {.inline, meter.} =
  ## Repeated cyclotomic squarings
  for _ in 0 ..< num:
    f.cyclotomic_square()

func cycl_sqr_repeated*[FT](r: var FT, a: FT, num: int) {.inline, meter.} =
  ## Repeated cyclotomic squarings
  r.cyclotomic_square(a)
  for _ in 1 ..< num:
    r.cyclotomic_square()

iterator unpack(scalarByte: byte): bool =
  yield bool((scalarByte and 0b10000000) shr 7)
  yield bool((scalarByte and 0b01000000) shr 6)
  yield bool((scalarByte and 0b00100000) shr 5)
  yield bool((scalarByte and 0b00010000) shr 4)
  yield bool((scalarByte and 0b00001000) shr 3)
  yield bool((scalarByte and 0b00000100) shr 2)
  yield bool((scalarByte and 0b00000010) shr 1)
  yield bool( scalarByte and 0b00000001)

func cyclotomic_exp*[FT](r: var FT, a: FT, exponent: BigInt, invert: bool) {.meter.} =
    var eBytes: array[(exponent.bits+7) div 8, byte]
    eBytes.exportRawUint(exponent, bigEndian)

    r.setOne()
    for b in eBytes:
      for bit in unpack(b):
        r.cyclotomic_square()
        if bit:
          r *= a
    if invert:
      r.cyclotomic_inv()

func isInCyclotomicSubgroup*[C](a: Fp6[C]): SecretBool =
  ## Check if a ∈ Fpⁿ: a^Φₙ(p) = 1
  ## Φ₆(p) = p⁴-p²+1
  var t{.noInit.}, p{.noInit.}: Fp6[C]

  t.frobenius_map(a, 2)  # a^(p²)
  t *= a                 # a^(p²+1)
  p.frobenius_map(a)     # a^(p)

  return t == p

func isInCyclotomicSubgroup*[C](a: Fp12[C]): SecretBool =
  ## Check if a ∈ Fpⁿ: a^Φₙ(p) = 1
  ## Φ₁₂(p) = p⁴-p²+1
  var t{.noInit.}, p2{.noInit.}: Fp12[C]

  p2.frobenius_map(a, 2) # a^(p²)
  t.frobenius_map(p2, 2) # a^(p⁴)
  t *= a                 # a^(p⁴+1)

  return t == p2

# ############################################################
#
#                Compressed representations
#
# ############################################################
#
# The special structure of cyclotomic subgroup allows compression that
# can lead to faster exponentiation:
#
# - Compression in Finite Fields and Torus-Based Cryptography
#   Rubin and Silverberg, 2003
#   https://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.90.8087&rep=rep1&type=pdf
#
# - Squaring in Cyclotomic Subgroup
#   Karabina, 2012
#   https://www.ams.org/journals/mcom/2013-82-281/S0025-5718-2012-02625-1/S0025-5718-2012-02625-1.pdf
#
# Karabina's formula G₂₃₄₅ has the best squaring/decompression cost ratio.
# From a sextic tower Fpᵏᐟ⁶ -> Fpᵏᐟ³ -> Fpᵏ with quadratic-non-residue u and cubic non-residue v
# α = (a₀+a₁u) + (b₀+b₁u)v + (c₀+c₁u)v²
# Compressed α: C(α) = (b₀+b₁u)v + (c₀+c₁u)v² = (g₂+g₃u)v + (g₄+g₅u)v²
# C(α)² = (h₂+h₃u)v + (h₄+h₅u)v²
#  with h₂ = 2(g₂ + 3ξg₄g₅)
#       h₃ = 3((g₄+g₅)(g₄+ξg₅) - (ξ+1)g₄g₅) - 2g₃
#       h₄ = 3((g₂+g₃)(g₂+ξg₃) - (ξ+1)g₂g₃) - 2g₄
#       h₅ = 2(g₅ + 3(g₂+g₃)(g₂+ξg₃))
#
# For decompression we can recompute the missing coefficients
# if g₂ != 0
#       g₁ = (g₅²ξ + 3g₄² - 2g₃)/4g₂       g₀ = (2g₁² + g₂g₅ - 3g₃g₄)ξ + 1
# if g₂ == 0
#       g₁ = 2g₄g₅/g₃                      g₀ = (2g₁²        - 3g₃g₄)ξ + 1

type G2345*[F] = object
  ## Compressed representation of cyclotomic subgroup element of a sextic extension
  ## (0 + 0u) + (g₂+g₃u)v + (g₄+g₅u)v²
  g2, g3, g4, g5: F

func cyclotomic_square_compressed*[F](g: var G2345[F]) =
  ## Karabina's compressed squaring
  ## for sextic extension fields
  # C(α)² = (h₂+h₃u)v + (h₄+h₅u)v²
  # with
  #       h₂ = 2(g₂ + 3ξg₄g₅)
  #       h₃ = 3((g₄+g₅)(g₄+ξg₅) - (ξ+1)g₄g₅) - 2g₃
  #       h₄ = 3((g₂+g₃)(g₂+ξg₃) - (ξ+1)g₂g₃) - 2g₄
  #       h₅ = 2(g₅ + 3(g₂+g₃)(g₂+ξg₃))
  # (4 mul, theorem 3.2 p561)
  #
  # or
  #       h₂ = 2g₂ + 6ξg₄g₅
  #       h₃ = 3g₄² + 3g₅²ξ - 2g₃
  #       h₄ = 3g₂² + 3g₃²ξ - 2g₄
  #       h₅ = 2g₅ + 6g₂g₃
  # (2 mul, 4 sqr, section 5.3 p567)
  #
  # or
  #       h₂ = 2g₂ + 3ξ((g₄+g₅)²-g₄²-g₅²)
  #       h₃ = 3(g₄² + g₅²ξ) - 2g₃
  #       h₄ = 3(g₂² + g₃²ξ) - 2g₄
  #       h₅ = 2g₅ + 3 ((g₂+g₃)²-g₂²-g₃²)
  # (6 sqr)    
  #
  # or with quadratic arithmetic
  #   (h₂+h₃u) = 3u(g₄+g₅u)² + 2(g₂-g₃u)
  #   (h₄+h₅u) = 3 (g₂+g₃u)² - 2(g₄-g₅u)
  # (2x2mul or 2x3sqr, section 5.3 p567)
  var g2g3 {.noInit.} = QuadraticExt[F](coords:[g.g2, g.g3])
  var g4g5 {.noInit.} = QuadraticExt[F](coords:[g.g4, g.g5])
  var h2h3 {.noInit.}, h4h5 {.noInit.}: QuadraticExt[F]

  h2h3.square(g4g5)
  h2h3 *= NonResidue
  h2h3 *= 3

  h4h5.square(g2g3)
  h4h5 *= 3

  g2g3.double()
  g4g5.double()

  g.g2.sum(h2h3.c0, g2g3.c0)
  g.g3.diff(h2h3.c1, g2g3.c1)
  g.g4.diff(h4h5.c0, g4g5.c0)
  g.g5.sum(h4h5.c1, g4g5.c1)

func recover_g1*[F](g1_num, g1_den: var F, g: G2345[F]) =
  ## Compute g₁ from coordinates g₂g₃g₄g₅
  ## of a cyclotomic subgroup element of a sextic extension field
  # if g₂ != 0
  #   g₁ = (g₅²ξ + 3g₄² - 2g₃)/4g₂
  # if g₂ == 0
  #   g₁ = 2g₄g₅/g₃
  # 
  # Theorem 3.1, this is well-defined for all
  # g in Gϕₙ \ {1}
  # if g₂=g₃=0 then g₄=g₅=0 as well
  # and g₀ = 1
  let g2NonZero = not g.g2.isZero()
  var t{.noInit.}: F
  
  g1_num = g.g4
  t = g.g5
  t.ccopy(g.g4, g2NonZero)
  t *= g1_num                     #  g₄²              or  g₄g₅
  g1_num = t
  g1_num.csub(g.g3, g2NonZero)    #  g₄²- g₃
  g1_num.double()                 # 2g₄²-2g₃          or 2g₄g₅
  g1_num.cadd(t, g2NonZero)       # 3g₄²-2g₃          or 2g₄g₅

  t.square(g.g5)
  t *= NonResidue
  g1_num.cadd(t, g2NonZero)       # g₅²ξ + 3g₄² - 2g₃ or 2g₄g₅
  
  t.prod(g.g2, 4)
  g1_den = g.g3
  g1_den.ccopy(t, g2NonZero)      # 4g₂ or g₃

func batch_ratio_g1s*[N: static int, F](
       dst: var array[N, F],
       src: array[N, tuple[g1_num, g1_den: F]]) =
  ## Batch inversion of g₁
  ## returns g1_numᵢ/g1_denᵢ
  ## This requires that all g1_den != 0 or all g1_den == 0
  ## which is the case if this is used to implement
  ## exponentiation in cyclotomic subgroup.
  
  # Algorithm: Montgomery's batch inversion
  # - Speeding the Pollard and Elliptic Curve Methods of Factorization
  #   Section 10.3.1
  #   Peter L. Montgomery
  #   https://www.ams.org/journals/mcom/1987-48-177/S0025-5718-1987-0866113-7/S0025-5718-1987-0866113-7.pdf
  # - Modern Computer Arithmetic
  #   Section 2.5.1 Several inversions at once
  #   Richard P. Brent and Paul Zimmermann
  #   https://members.loria.fr/PZimmermann/mca/mca-cup-0.5.9.pdf

  dst[0] = src[0].g1_den
  for i in 1 ..< N:
    dst[i].prod(dst[i-1], src[i].g1_den)

  var accInv{.noInit.}: F
  accInv.inv(dst[N-1])

  for i in countdown(N-1, 1):
    # Compute inverse
    dst[i].prod(accInv, dst[i-1])
    # Apply it
    dst[i] *= src[i].g1_num
    # Next iteration
    accInv *= src[i].g1_den
  
  dst[0].prod(accInv, src[0].g1_num)

func recover_g0*[F](
       g0: var F, g1: F,
       g: G2345[F]) =
  ## Compute g₀ from coordinates g₁g₂g₃g₄g₅
  ## of a cyclotomic subgroup element of a sextic extension field
  var t{.noInit.}: F

  t.square(g1)
  g0.prod(g.g3, g.g4)
  t -= g0
  t.double()
  t -= g0
  g0.prod(g.g2, g.g5)
  t += g0
  g0.prod(t, NonResidue)
  t.setOne()
  g0 += t

func fromFpk*[Fpkdiv6, Fpk](
       g: var G2345[Fpkdiv6],
       a: Fpk) =
  ## Convert from a sextic extension to the Karabina g₂₃₄₅
  ## representation.
  
  # GT representations isomorphisms
  # ===============================
  #
  # Given a sextic twist, we can express all elements in terms of z = SNR¹ᐟ⁶
  # 
  # The canonical direct sextic representation uses coefficients
  #
  #    c₀ + c₁ z + c₂ z² + c₃ z³ + c₄ z⁴ + c₅ z⁵
  #
  # with z = SNR¹ᐟ⁶
  #
  # The cubic over quadatric towering
  # ---------------------------------
  #
  #   (a₀ + a₁ u) + (a₂ + a₃u) v + (a₄ + a₅u) v²
  #
  # with u = (SNR)¹ᐟ² and v = z = u¹ᐟ³ = (SNR)¹ᐟ⁶
  #
  # The quadratic over cubic towering
  # ---------------------------------
  #
  #   (b₀ + b₁x + b₂x²) + (b₃ + b₄x + b₅x²)y
  #
  # with x = (SNR)¹ᐟ³ and y = z = x¹ᐟ² = (SNR)¹ᐟ⁶
  #
  # Mapping between towering schemes
  # --------------------------------
  #
  # g₂₃₄₅ uses the cubic over quadratic representation hence:
  #
  #   c₀ <=> a₀ <=> b₀ <=> g₀
  #   c₁ <=> a₂ <=> b₃ <=> g₂
  #   c₂ <=> a₄ <=> b₁ <=> g₄
  #   c₃ <=> a₁ <=> b₄ <=> g₁
  #   c₄ <=> a₃ <=> b₂ <=> g₃
  #   c₅ <=> a₅ <=> b₅ <=> g₅
  #
  # See also chapter 6.4
  # - Multiplication and Squaring on Pairing-Friendly Fields
  #   Augusto Jun Devegili and Colm Ó hÉigeartaigh and Michael Scott and Ricardo Dahab, 2006
  #   https://eprint.iacr.org/2006/471

  when a is CubicExt:
    when a.c0 is QuadraticExt:
      g.g2 = a.c1.c0
      g.g3 = a.c1.c1
      g.g4 = a.c2.c0
      g.g5 = a.c2.c1
    else:
      {.error: "a must be a sextic extension field".}
  elif a is QuadraticExt:
    when a.c0 is CubicExt:
      {.error: "𝔽pᵏᐟ⁶ -> 𝔽pᵏᐟ³ -> 𝔽pᵏ towering (quadratic over cubic) is not implemented.".}
    else:
      {.error: "a must be a sextic extension field".}
  else:
    {.error: "𝔽pᵏᐟ⁶ -> 𝔽pᵏ towering (direct sextic) is not implemented.".}

func asFpk*[Fpkdiv6, Fpk](
       a: var Fpk,
       g0, g1: Fpkdiv6,
       g: G2345[Fpkdiv6]) =
  ## Convert from a sextic extension to the Karabina g₂₃₄₅
  ## representation.
  when a is CubicExt:
    when a.c0 is QuadraticExt:
      a.c0.c0 = g0
      a.c0.c1 = g1
      a.c1.c0 = g.g2
      a.c1.c1 = g.g3
      a.c2.c0 = g.g4
      a.c2.c1 = g.g5
    else:
      {.error: "a must be a sextic extension field".}
  elif a is QuadraticExt:
    when a.c0 is CubicExt:
      {.error: "𝔽pᵏᐟ⁶ -> 𝔽pᵏᐟ³ -> 𝔽pᵏ towering (quadratic over cubic) is not implemented.".}
    else:
      {.error: "a must be a sextic extension field".}
  else:
    {.error: "𝔽pᵏᐟ⁶ -> 𝔽pᵏ towering (direct sextic) is not implemented.".}

func cyclotomic_exp_compressed*[N: static int, Fpk](
       r: var Fpk, a: Fpk, 
       squarings: static array[N, int]) =
  ## Exponentiation on the cyclotomic subgroup
  ## via compressed repeated squarings
  ## Exponentiation is done least-signigicant bits first
  ## `squarings` represents the number of squarings
  ## to do before the next multiplication.
  ## 
  ## `accumSquarings` stores the accumulated squarings so far
  ## iff N != 1
  
  type Fpkdiv6 = typeof(a.c0.c0)

  var gs {.noInit.}: array[N, G2345[Fpkdiv6]]

  var g {.noInit.}: G2345[Fpkdiv6]
  g.fromFpk(a)

  # Compressed squarings
  for i in 0 ..< N:
    for j in 0 ..< squarings[i]:
      g.cyclotomic_square_compressed()
    gs[i] = g

  # Batch decompress
  var g1s_ratio {.noInit.}: array[N, tuple[g1_num, g1_den: Fpkdiv6]]
  for i in 0 ..< N:
    recover_g1(g1s_ratio[i].g1_num, g1s_ratio[i].g1_den, gs[i])
  
  var g1s {.noInit.}: array[N, Fpkdiv6]
  g1s.batch_ratio_g1s(g1s_ratio)

  var g0s {.noInit.}: array[N, Fpkdiv6]
  for i in 0 ..< N:
    g0s[i].recover_g0(g1s[i], gs[i])

  r.asFpk(g0s[0], g1s[0], gs[0])
  for i in 1 ..< N:
    var t {.noInit.}: Fpk
    t.asFpk(g0s[i], g1s[i], gs[i])
    r *= t

func cyclotomic_exp_compressed*[N: static int, Fpk](
       r, accumSquarings: var Fpk, a: Fpk,
       squarings: static array[N, int]) =
  ## Exponentiation on the cyclotomic subgroup
  ## via compressed repeated squarings
  ## Exponentiation is done least-signigicant bits first
  ## `squarings` represents the number of squarings
  ## to do before the next multiplication.
  ## 
  ## `accumSquarings` stores the accumulated squarings so far
  ## iff N != 1
  
  type Fpkdiv6 = typeof(a.c0.c0)

  var gs {.noInit.}: array[N, G2345[Fpkdiv6]]

  var g {.noInit.}: G2345[Fpkdiv6]
  g.fromFpk(a)

  # Compressed squarings
  for i in 0 ..< N:
    for j in 0 ..< squarings[i]:
      g.cyclotomic_square_compressed()
    gs[i] = g

  # Batch decompress
  var g1s_ratio {.noInit.}: array[N, tuple[g1_num, g1_den: Fpkdiv6]]
  for i in 0 ..< N:
    recover_g1(g1s_ratio[i].g1_num, g1s_ratio[i].g1_den, gs[i])
  
  var g1s {.noInit.}: array[N, Fpkdiv6]
  g1s.batch_ratio_g1s(g1s_ratio)

  var g0s {.noInit.}: array[N, Fpkdiv6]
  for i in 0 ..< N:
    g0s[i].recover_g0(g1s[i], gs[i])

  r.asFpk(g0s[0], g1s[0], gs[0])
  for i in 1 ..< N:
    var t {.noInit.}: Fpk
    t.asFpk(g0s[i], g1s[i], gs[i])
    r *= t

    if i+1 == N:
      accumSquarings = t