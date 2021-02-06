# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# Instantiate the actual tower extensions
# that were described in a "conceptualized" way
# ----------------------------------------------------------------

import
  ../arithmetic,
  ../config/[common, curves],
  ../io/io_fields,
  ./tower_common,
  ./quadratic_extensions,
  ./cubic_extensions,
  ./exponentiations

export tower_common, quadratic_extensions, cubic_extensions, exponentiations

# We assume that the sextic non-residues used to construct
# the elliptic curve twists
# match with the quadratic and cubic non-residues
# chosen to construct the tower of extension fields.

# 𝔽p
# ----------------------------------------------------------------

func `*=`*(a: var Fp, _: type NonResidue) {.inline.} =
  ## Multiply an element of 𝔽p by the quadratic non-residue
  ## chosen to construct 𝔽p2
  static: doAssert Fp.C.getNonResidueFp() != -1, "𝔽p2 should be specialized for complex extension"
  a *= Fp.C.getNonResidueFp()

func prod*(r: var Fp, a: Fp, _: type NonResidue){.inline.} =
  ## Multiply an element of 𝔽p by the quadratic non-residue
  ## chosen to construct 𝔽p2
  static: doAssert Fp.C.getNonResidueFp() != -1, "𝔽p2 should be specialized for complex extension"
  r.prod(a, Fp.C.getNonResidueFp())

# 𝔽p2
# ----------------------------------------------------------------

type
  Fp2*[C: static Curve] = object
    c0*, c1*: Fp[C]

template fromComplexExtension*[F](elem: F): static bool =
  ## Returns true if the input is a complex extension
  ## i.e. the irreducible polynomial chosen is
  ##   x² - µ with µ = -1
  ## and so 𝔽p2 = 𝔽p[x] / x² - µ = 𝔽p[𝑖]
  when F is Fp2 and F.C.getNonResidueFp() == -1:
    true
  else:
    false

template mulCheckSparse*(a: var Fp2, b: Fp2) =
  when b.isOne().bool:
    discard
  elif b.isMinusOne().bool:
    a.neg()
  elif b.c0.isZero().bool and b.c1.isOne().bool:
    var t {.noInit.}: type(a.c0)
    when fromComplexExtension(b):
      t.neg(a.c1)
      a.c1 = a.c0
      a.c0 = t
    else:
      t.prod(a.c1, NonResidue)
      a.c1 = a.c0
      a.c0 = t
  elif b.c0.isZero().bool and b.c1.isMinusOne().bool:
    var t {.noInit.}: type(a.c0)
    when fromComplexExtension(b):
      t = a.c1
      a.c1.neg(a.c0)
      a.c0 = t
    else:
      t.prod(a.c1, NonResidue)
      a.c1.neg(a.c0)
      a.c0.neg(t)
  elif b.c0.isZero().bool:
    a.mul_sparse_by_0y(b)
  elif b.c1.isZero().bool:
    a.mul_sparse_by_x0(b)
  else:
    a *= b

func prod*(r: var Fp2, a: Fp2, _: type NonResidue) {.inline.} =
  ## Multiply an element of 𝔽p2 by the non-residue
  ## chosen to construct the next extension or the twist:
  ## - if quadratic non-residue: 𝔽p4
  ## - if cubic non-residue: 𝔽p6
  ## - if sextic non-residue: 𝔽p4, 𝔽p6 or 𝔽p12
  # Yet another const tuple unpacking bug
  const u = Fp2.C.getNonResidueFp2()[0]
  const v = Fp2.C.getNonResidueFp2()[1]
  const Beta {.used.} = Fp2.C.getNonResidueFp()
  # ξ = u + v x
  # and x² = β
  #
  # (c0 + c1 x) (u + v x) => u c0 + (u c0 + u c1)x + v c1 x²
  #                       => u c0 + β v c1 + (v c0 + u c1) x
  when a.fromComplexExtension() and u == 1 and v == 1:
    let t = a.c0
    r.c0.diff(t, a.c1)
    r.c1.sum(t, a.c1)
  else:
    # Case:
    # - BN254_Snarks, QNR_Fp: -1, SNR_Fp2: 9+1𝑖  (𝑖 = √-1)
    # - BLS12_377, QNR_Fp: -5, SNR_Fp2: 0+1j    (j = √-5)
    # - BW6_761, SNR_Fp: -4, CNR_Fp2: 0+1j      (j = √-4)
    when u == 0:
      # BLS12_377 and BW6_761, use small addition chain
      r.mul_sparse_by_0y(a, v)
    else:
      # BN254_Snarks, u = 9
      # Full 𝔽p2 multiplication is cheaper than addition chains
      # for u*c0 and u*c1
      static:
        doAssert u >= 0 and uint64(u) <= uint64(high(BaseType))
        doAssert v >= 0 and uint64(v) <= uint64(high(BaseType))
      # TODO: compile-time
      var NR {.noInit.}: Fp2
      NR.c0.fromUint(uint u)
      NR.c1.fromUint(uint v)
      r.prod(a, NR)

func `*=`*(a: var Fp2, _: type NonResidue) {.inline.} =
  ## Multiply an element of 𝔽p2 by the non-residue
  ## chosen to construct the next extension or the twist:
  ## - if quadratic non-residue: 𝔽p4
  ## - if cubic non-residue: 𝔽p6
  ## - if sextic non-residue: 𝔽p4, 𝔽p6 or 𝔽p12
  # Yet another const tuple unpacking bug
  a.prod(a, NonResidue)

func `/=`*(a: var Fp2, _: type NonResidue) {.inline.} =
  ## Divide an element of 𝔽p by the non-residue
  ## chosen to construct the next extension or the twist:
  ## - if quadratic non-residue: 𝔽p4
  ## - if cubic non-residue: 𝔽p6
  ## - if sextic non-residue: 𝔽p4, 𝔽p6 or 𝔽p12
  # Yet another const tuple unpacking bug
  # Yet another const tuple unpacking bug
  const u = Fp2.C.getNonresidueFp2()[0] # Sextic non-residue to construct 𝔽p12
  const v = Fp2.C.getNonresidueFp2()[1]
  const Beta = Fp2.C.getNonResidueFp()  # Quadratic non-residue to construct 𝔽p2
  # ξ = u + v x
  # and x² = β
  #
  # (c0 + c1 x) / (u + v x) => (c0 + c1 x)(u - v x) / ((u + vx)(u-vx))
  #                         => u c0 - v c1 x² + (u c1 - v c0) x / (u² - x²v²)
  #                         => 1/(u² - βv²) * (uc0 - β v c1, u c1 - v c0)
  # With β = 𝑖 = √-1
  #   1/(u² + v²) * (u c0 + v c1, u c1 - v c0)
  #
  # With β = 𝑖 = √-1 and ξ = 1 + 𝑖
  #   1/2 * (c0 + c1, c1 - c0)

  when a.fromComplexExtension() and u == 1 and v == 1:
    let t = a.c0
    a.c0 += a.c1
    a.c1 -= t
    a.div2()
  else:
    var a0 = a.c0
    let a1 = a.c1
    const u2v2 = u*u - Beta*v*v # (u² - βv²)
    # TODO can be precomputed (or precompute b/µ the twist coefficient)
    #      and use faster non-constant-time inversion in the VM
    var u2v2inv {.noInit.}: a.c0.typeof
    u2v2inv.fromUint(u2v2)
    u2v2inv.inv()

    a.c0 *= u
    a.c1 *= Beta * v
    a.c0 -= a.c1

    a.c1 = a1
    a.c1 *= u
    a0 *= v
    a.c1 -= a0
    a.c0 *= u2v2inv
    a.c1 *= u2v2inv

# 𝔽p4 & 𝔽p6
# ----------------------------------------------------------------

type
  Fp4*[C: static Curve] = object
    c0*, c1*: Fp2[C]

  Fp6*[C: static Curve] = object
    c0*, c1*, c2*: Fp2[C]

func prod*(r: var Fp4, a: Fp4, _: type NonResidue) =
  ## Multiply an element of 𝔽p4 by the non-residue
  ## chosen to construct the next extension or the twist:
  ## - if quadratic non-residue: 𝔽p8
  ## - if cubic non-residue: 𝔽p12
  ## - if sextic non-residue: 𝔽p8, 𝔽p12 or 𝔽p24
  ##
  ## Assumes that it is sqrt(NonResidue_Fp2)
  let t = a.c0
  r.c0.prod(a.c1, NonResidue)
  r.c1 = t

func `*=`*(a: var Fp4, _: type NonResidue) {.inline.} =
  ## Multiply an element of 𝔽p4 by the non-residue
  ## chosen to construct the next extension or the twist:
  ## - if quadratic non-residue: 𝔽p8
  ## - if cubic non-residue: 𝔽p12
  ## - if sextic non-residue: 𝔽p8, 𝔽p12 or 𝔽p24
  ##
  ## Assumes that it is sqrt(NonResidue_Fp2)
  a.prod(a, NonResidue)

func prod*(r: var Fp6, a: Fp6, _: type NonResidue) {.inline.} =
  ## Multiply an element of 𝔽p4 by the non-residue
  ## chosen to construct the next extension or the twist:
  ## - if quadratic non-residue: 𝔽p12
  ## - if cubic non-residue: 𝔽p18
  ## - if sextic non-residue: 𝔽p12, 𝔽p18 or 𝔽p36
  ##
  ## Assumes that it is cube_root(NonResidue_Fp2)
  ##
  ## For all curves γ = v with v the factor for 𝔽p6 coordinate
  ## and v³ = ξ
  ## (c0 + c1 v + c2 v²) v => ξ c2 + c0 v + c1 v²
  let t = a.c2
  r.c1 = a.c0
  r.c2 = a.c1
  t.c0.prod(t, NonResidue)

func `*=`*(a: var Fp6, _: type NonResidue) {.inline.} =
  ## Multiply an element of 𝔽p4 by the non-residue
  ## chosen to construct the next extension or the twist:
  ## - if quadratic non-residue: 𝔽p12
  ## - if cubic non-residue: 𝔽p18
  ## - if sextic non-residue: 𝔽p12, 𝔽p18 or 𝔽p36
  ##
  ## Assumes that it is cube_root(NonResidue_Fp2)
  ##
  ## For all curves γ = v with v the factor for 𝔽p6 coordinate
  ## and v³ = ξ
  ## (c0 + c1 v + c2 v²) v => ξ c2 + c0 v + c1 v²
  a.prod(a, NonResidue)

# 𝔽p12
# ----------------------------------------------------------------

type
  Fp12*[C: static Curve] = object
    c0*, c1*, c2*: Fp4[C]
    # c0*, c1*: Fp6[C]

# Sparse functions
# ----------------------------------------------------------------

func `*=`*(a: var Fp2, b: Fp) =
  ## Multiply an element of Fp2 by an element of Fp
  a.c0 *= b
  a.c1 *= b

func mul_sparse_by_y0*[C: static Curve](r: var Fp4[C], a: Fp4[C], b: Fp2[C]) =
  ## Sparse multiplication of an Fp4 element
  ## with coordinates (a₀, a₁) by (b₀, 0)
  r.c0.prod(a.c0, b)
  r.c1.prod(a.c1, b)

func mul_sparse_by_0y0*[C: static Curve](r: var Fp6[C], a: Fp6[C], b: Fp2[C]) =
  ## Sparse multiplication of an Fp6 element
  ## with coordinates (a₀, a₁, a₂) by (0, b₁, 0)
  # TODO: make generic and move to tower_field_extensions

  # v0 = a0 b0 = 0
  # v1 = a1 b1
  # v2 = a2 b2 = 0
  #
  # r0 = ξ ((a1 + a2) * (b1 + b2) - v1 - v2) + v0
  #    = ξ (a1 b1 + a2 b1 - v1)
  #    = ξ a2 b1
  # r1 = (a0 + a1) * (b0 + b1) - v0 - v1 + ξ v2
  #    = a0 b1 + a1 b1 - v1
  #    = a0 b1
  # r2 = (a0 + a2) * (b0 + b2) - v0 - v2 + v1
  #    = v1
  #    = a1 b1

  r.c0.prod(a.c2, b)
  r.c0 *= NonResidue
  r.c1.prod(a.c0, b)
  r.c2.prod(a.c1, b)
