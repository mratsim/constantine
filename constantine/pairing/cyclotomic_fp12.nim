# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../primitives,
  ../config/curves,
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
func finalExpEasy*[C: static Curve](f: var Fp12[C]) =
  ## Easy part of the final exponentiation
  ##
  ## This maps the result of the Miller loop into the cyclotomic subgroup Gϕ₁₂
  ##
  ## We need to clear the Gₜ cofactor to obtain
  ## an unique Gₜ representation
  ## (reminder, Gₜ is a multiplicative group hence we exponentiate by the cofactor)
  ##
  ## i.e. Fp^12 --> (fexp easy) --> Gϕ₁₂ --> (fexp hard) --> Gₜ
  ##
  ## The final exponentiation is fexp = f^((p^12 - 1) / r)
  ## It is separated into:
  ## f^((p^12 - 1) / r) = (p^12 - 1) / ϕ₁₂(p)  * ϕ₁₂(p) / r
  ##
  ## with the cyclotomic polynomial ϕ₁₂(p) = (p⁴-p²+1)
  ##
  ## With an embedding degree of 12, the easy part of final exponentiation is
  ##
  ##  f^(p⁶−1)(p²+1)
  ##
  ## And properties are
  ## 0. f^(p⁶) ≡ conj(f) (mod p^12) for all f in Fp12
  ##
  ## After g = f^(p⁶−1) the result g is on the cyclotomic subgroup
  ## 1. g^(-1) ≡ g^(p⁶) (mod p^12)
  ## 2. Inversion can be done with conjugate
  ## 3. g is unitary, its norm |g| (the product of conjugates) is 1
  ## 4. Squaring has a fast compressed variant.
  #
  # Proofs:
  #
  # Fp12 can be defined as a quadratic extension over Fp⁶
  # with g = g₀ + x g₁ with x a quadratic non-residue
  #
  # with q = p⁶
  # The frobenius map f^q ≡ (f₀ + x f₁)^q (mod q²)
  #                       ≡ f₀^q + x^q f₁^q (mod q²)
  #                       ≡ f₀ + x^q f₁ (mod q²)
  #                       ≡ f₀ - x f₁ (mod q²)
  # hence
  # f^p⁶ ≡ conj(f) (mod p^12)
  # Q.E.D. of (0)
  #
  # ----------------
  #
  # p^12 - 1 = (p⁶−1)(p⁶+1) = (p⁶−1)(p²+1)(p⁴-p²+1)
  # by Fermat's little theorem we have
  # f^(p^12 - 1) ≡ 1 (mod p^12)
  #
  # Hence f^(p⁶−1)(p⁶+1) ≡ 1 (mod p^12)
  #
  # We call g = f^(p⁶−1) we have
  # g^(p⁶+1) ≡ 1 (mod p^12) <=> g^(p⁶) * g ≡ 1 (mod p^12)
  # hence g^(-1) ≡ g^(p⁶) (mod p^12)
  # Q.E.D. of (1)
  #
  # --
  #
  # From (1) g^(-1) ≡ g^(p⁶) (mod p^12) for g = f^(p⁶−1)
  # and  (0) f^p⁶ ≡ conj(f) (mod p^12)  for all f in fp12
  #
  # so g^(-1) ≡ conj(g) (mod p^12) for g = f^(p⁶−1)
  # Q.E.D. of (2)
  #
  # --
  #
  # f^(p^12 - 1) ≡ 1 (mod p^12) by Fermat's Little Theorem
  # f^(p⁶−1)(p⁶+1) ≡ 1 (mod p^12)
  # g^(p⁶+1) ≡ 1 (mod p^12)
  # g * g^p⁶ ≡ 1 (mod p^12)
  # g * conj(g) ≡ 1 (mod p^12)
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

func cyclotomic_inv*(a: var Fp12) =
  ## Fast inverse for a
  ## `a` MUST be in the cyclotomic subgroup
  ## consequently `a` MUST be unitary
  a.conj()

func cyclotomic_inv*(r: var Fp12, a: Fp12) =
  ## Fast inverse for a
  ## `a` MUST be in the cyclotomic subgroup
  ## consequently `a` MUST be unitary
  r.conj(a)

func cyclotomic_square*[C](r: var Fp12[C], a: Fp12[C]) =
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
    var A{.noinit.}, B{.noinit.}, C{.noinit.}, D{.noinit.}: Fp4[C]

    A = a.c0

    r.c0.square(a.c0)  # r0 = a²
    D.double(r.c0)     # D  = 2a²
    r.c0 += D          # r0 = 3a²

    A.conjneg()        # A = − ̄a
    A.double()         # A = − 2 ̄a
    r.c0 += A          # r0 = 3a² − 2 ̄a

    B.square(a.c2)     # B = c²
    B *= NonResidue    # B = √i c²
    D.double(B)        # B = 2 √i c²
    B += D             # B = 3 √i c²

    r.c1.conj(a.c1)    # r1 = ̄b
    r.c1.double()      # r1 = 2 ̄b
    r.c1 += B          # r1 = 3 √i c² + 2 ̄b

    C.square(a.c1)     # C = b²
    D.double(C)        # D = 2b²
    C += D             # C = 3b²

    r.c2.conjneg(a.c2) # r2 = - ̄c
    r.c2.double()      # r2 = - 2 ̄c
    r.c2 += C          # r2 = 3b² - 2 ̄c

  else:
    {.error: "Not implemented".}

func cyclotomic_square*[C](a: var Fp12[C]) =
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
    var A{.noinit.}, B{.noinit.}, C{.noinit.}, D{.noinit.}: Fp4[C]

    A = a.c0

    a.c0.square()      # r0 = a²
    D.double(a.c0)     # D  = 2a²
    a.c0 += D          # r0 = 3a²

    A.conjneg()        # A = − ̄a
    A.double()         # A = − 2 ̄a
    a.c0 += A          # r0 = 3a² − 2 ̄a

    B.square(a.c2)     # B = c²
    B *= NonResidue    # B = √i c²
    D.double(B)        # B = 2 √i c²
    B += D             # B = 3 √i c²

    A = a.c1

    a.c1.conj()        # r1 = ̄b
    a.c1.double()      # r1 = 2 ̄b
    a.c1 += B          # r1 = 3 √i c² + 2 ̄b

    C.square(A)        # C = b²
    D.double(C)        # D = 2b²
    C += D             # C = 3b²

    a.c2.conjneg()     # r2 = - ̄c
    a.c2.double()      # r2 = - 2 ̄c
    a.c2 += C          # r2 = 3b² - 2 ̄c

  else:
    {.error: "Not implemented".}

func cycl_sqr_repeated*(f: var Fp12, num: int) {.inline.} =
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

func cyclotomic_exp*[C](r: var Fp12[C], a: Fp12[C], exponent: BigInt, invert: bool) =
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
