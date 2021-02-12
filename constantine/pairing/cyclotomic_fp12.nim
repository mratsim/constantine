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

# ############################################################
#
#               Gϕ₁₂, Cyclotomic subgroup of Fp12
#         with GΦₙ(p) = {α ∈ Fpⁿ : α^Φₙ(p) ≡ 1 (mod pⁿ)}
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

# 𝔽p12 -> Gϕ₁₂ - Mapping to Cyclotomic group
# ----------------------------------------------------------------
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

# Gϕ₁₂ - Cyclotomic functions
# ----------------------------------------------------------------
# A cyclotomic group is a subgroup of Fp^n defined by
#
# GΦₙ(p) = {α ∈ Fpⁿ : α^Φₙ(p) = 1}
#
# The result of any pairing is in a cyclotomic subgroup

func cyclotomic_inv*(a: var Fp12) {.meter.} =
  ## Fast inverse for a
  ## `a` MUST be in the cyclotomic subgroup
  ## consequently `a` MUST be unitary
  a.conj()

func cyclotomic_inv*(r: var Fp12, a: Fp12) {.meter.} =
  ## Fast inverse for a
  ## `a` MUST be in the cyclotomic subgroup
  ## consequently `a` MUST be unitary
  r.conj(a)

func cyclotomic_square*[C](r: var Fp12[C], a: Fp12[C]) {.meter.} =
  ## Square `a` into `r`
  ## `a` MUST be in the cyclotomic subgroup
  ## consequently `a` MUST be unitary
  #
  # Faster Squaring in the Cyclotomic Subgroup of Sixth Degree Extensions
  # Granger, Scott, 2009
  # https://eprint.iacr.org/2009/565.pdf

  when a.c0 is Fp4:
    # Cubic over quadratic
    # A = 3a² − 2 ̄a
    # B = 3 √i c² + 2 ̄b
    # C = 3b² − 2 ̄c
    var t0{.noinit.}, t1{.noinit.}: Fp4[C]

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

func cyclotomic_square*[C](a: var Fp12[C]) {.meter.} =
  ## Square `a` into `r`
  ## `a` MUST be in the cyclotomic subgroup
  ## consequently `a` MUST be unitary
  #
  # Faster Squaring in the Cyclotomic Subgroup of Sixth Degree Extensions
  # Granger, Scott, 2009
  # https://eprint.iacr.org/2009/565.pdf
  a.cyclotomic_square(a)

func cycl_sqr_repeated*(f: var Fp12, num: int) {.inline, meter.} =
  ## Repeated cyclotomic squarings
  for _ in 0 ..< num:
    f.cyclotomic_square()

iterator unpack(scalarByte: byte): bool =
  yield bool((scalarByte and 0b10000000) shr 7)
  yield bool((scalarByte and 0b01000000) shr 6)
  yield bool((scalarByte and 0b00100000) shr 5)
  yield bool((scalarByte and 0b00010000) shr 4)
  yield bool((scalarByte and 0b00001000) shr 3)
  yield bool((scalarByte and 0b00000100) shr 2)
  yield bool((scalarByte and 0b00000010) shr 1)
  yield bool( scalarByte and 0b00000001)

func cyclotomic_exp*[C](r: var Fp12[C], a: Fp12[C], exponent: BigInt, invert: bool) {.meter.} =
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
