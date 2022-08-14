# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/macros,
  ../../platforms/primitives,
  ../arithmetic,
  ../extension_fields,
  ../constants/zoo_frobenius

# Frobenius Map
# ------------------------------------------------------------
#
# https://en.wikipedia.org/wiki/Frobenius_endomorphism
# For p prime
#
#   a^p (mod p) ≡ a (mod p)
#
# Also
#
#   (a + b)^p (mod p) ≡ a^p + b^p (mod p)
#                     ≡ a   + b   (mod p)
#
# Because p is prime and all expanded terms (from binomial expansion)
# besides a^p and b^p are divisible by p

# For 𝔽p2, with `u` the quadratic non-residue (usually the complex 𝑖)
# (a + u b)^p² (mod p²) ≡ a + u^p² b (mod p²)
#
# For 𝔽p2, frobenius acts like the conjugate
# whether u = √-1 = i
# or          √-2 or √-5

func frobenius_map*(r: var Fp, a: Fp, k: static int = 1) {.inline.} =
  ## Computes a^(pᵏ)
  ## The p-power frobenius automorphism on 𝔽p
  ## This is identity per Fermat's little theorem
  r = a

func frobenius_map*(r: var Fp2, a: Fp2, k: static int = 1) {.inline.} =
  ## Computes a^(pᵏ)
  ## The p-power frobenius automorphism on 𝔽p2
  when (k and 1) == 1:
    r.conj(a)
  else:
    r = a

# Frobenius map - on extension fields
# -----------------------------------------------------------------

func frobenius_map*[C](r: var Fp4[C], a: Fp4[C], k: static int = 1) {.inline.} =
  ## Computes a^(pᵏ)
  ## The p-power frobenius automorphism on 𝔽p4
  r.c0.frobenius_map(a.c0, k)
  r.c1.frobenius_map(a.c1, k)
  r.c1.mulCheckSparse frobMapConst(C, 3, k)

func frobenius_map*[C](r: var Fp6[C], a: Fp6[C], k: static int = 1) {.inline.} =
  ## Computes a^(pᵏ)
  ## The p-power frobenius automorphism on 𝔽p6
  r.c0.frobenius_map(a.c0, k)
  r.c1.frobenius_map(a.c1, k)
  r.c2.frobenius_map(a.c2, k)

  when C.getEmbeddingDegree == 12:
    r.c1.mulCheckSparse frobMapConst(C, 2, k)
    r.c2.mulCheckSparse frobMapConst(C, 4, k)
  elif C.getEmbeddingDegree == 6:
    r.c1.mulCheckSparse frobMapConst(C, 1, k)
    r.c2.mulCheckSparse frobMapConst(C, 2, k)
  else:
    {.error: "Not Implemented".}

func frobenius_map*[C](r: var Fp12[C], a: Fp12[C], k: static int = 1) {.inline.} =
  ## Computes a^(pᵏ)
  ## The p-power frobenius automorphism on 𝔽p12
  staticFor i, 0, r.coords.len:
    staticFor j, 0, r.coords[0].coords.len:
      r.coords[i].coords[j].frobenius_map(a.coords[i].coords[j], k)

  when r.c0 is Fp4:
    r.c0.c0.mulCheckSparse frobMapConst(C, 0, k)
    r.c0.c1.mulCheckSparse frobMapConst(C, 3, k)
    r.c1.c0.mulCheckSparse frobMapConst(C, 1, k)
    r.c1.c1.mulCheckSparse frobMapConst(C, 4, k)
    r.c2.c0.mulCheckSparse frobMapConst(C, 2, k)
    r.c2.c1.mulCheckSparse frobMapConst(C, 5, k)
  else:
    r.c0.c0.mulCheckSparse frobMapConst(C, 0, k)
    r.c0.c1.mulCheckSparse frobMapConst(C, 2, k)
    r.c0.c2.mulCheckSparse frobMapConst(C, 4, k)
    r.c1.c0.mulCheckSparse frobMapConst(C, 1, k)
    r.c1.c1.mulCheckSparse frobMapConst(C, 3, k)
    r.c1.c2.mulCheckSparse frobMapConst(C, 5, k)

# ψ (Psi) - Untwist-Frobenius-Twist Endomorphisms on twisted curves
# -----------------------------------------------------------------

# Constants:
#   Assuming embedding degree of 12 and a sextic twist
#   with SNR the sextic non-residue
#

func frobenius_psi*[PointG2](r: var PointG2, P: PointG2, k: static int = 1) =
  ## "Untwist-Frobenius-Twist" endomorphism applied k times
  ## r = ψ(P)
  for coordR, coordP in fields(r, P):
    coordR.frobenius_map(coordP, k)

  r.x.mulCheckSparse frobPsiConst(PointG2.F.C, psipow=k, coefpow=2)
  r.y.mulCheckSparse frobPsiConst(PointG2.F.C, psipow=k, coefpow=3)
