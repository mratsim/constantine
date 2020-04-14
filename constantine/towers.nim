# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./arithmetic,
  ./config/curves,
  ./tower_field_extensions/[
    tower_common,
    quadratic_extensions,
    cubic_extensions
  ]

export tower_common, quadratic_extensions, cubic_extensions

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
  when F is Fp2 and F.C.get_QNR_Fp() == -1:
    true
  else:
    false

func `*=`*(a: var Fp, _: typedesc[β]) {.inline.} =
  ## Multiply an element of 𝔽p by the quadratic non-residue
  ## chosen to construct 𝔽p2
  static: doAssert Fp.C.get_QNR_Fp() != -1, "𝔽p2 should be specialized for complex extension"
  a *= Fp.C.get_QNR_Fp()

func `*`*(_: typedesc[β], a: Fp): Fp {.inline, noInit.} =
  ## Multiply an element of 𝔽p by the quadratic non-residue
  ## chosen to construct 𝔽p2
  result = a
  result *= β

# 𝔽p6
# ----------------------------------------------------------------

type
  Fp6*[C: static Curve] = object
    c0*, c1*, c2*: Fp2[C]

  ξ = β
    # We call the non-residue ξ on 𝔽p6 to avoid confusion between non-residue
    # of different tower level

func `*`*(_: typedesc[β], a: Fp2): Fp2 {.inline, noInit.} =
  ## Multiply an element of 𝔽p2 by the cubic non-residue
  ## chosen to construct 𝔽p6
  # Yet another const tuple unpacking bug
  const u = Fp2.C.get_CNR_Fp2()[0] # Cubic non-residue to construct 𝔽p6
  const v = Fp2.C.get_CNR_Fp2()[1]
  const Beta = Fp2.C.get_QNR_Fp()  # Quadratic non-residue to construct 𝔽p2
  # ξ = u + v x
  # and x² = β
  #
  # (c0 + c1 x) (u + v x) => u c0 + (u c0 + u c1)x + v c1 x²
  #                       => u c0 + β v c1 + (v c0 + u c1) x

  # TODO: check code generated when ξ = 1 + 𝑖
  #       The mul by constant are inline but
  #       since we don't have __restrict tag
  #       and we use arrays (which decay into pointer)
  #       the compiler might not elide the temporary
  when a.fromComplexExtension():
    result.c0.diff(u * a.c0, v * a.c1)
  else:
    result.c0.sum(u * a.c0, (Beta * v) * a.c1)
  result.c1.sum(v * a.c0, u * a.c1 )

func `*=`*(a: var Fp2, _: typedesc[ξ]) {.inline.} =
  ## Multiply an element of 𝔽p by the quadratic non-residue
  ## chosen to construct 𝔽p2
  # Yet another const tuple unpacking bug
  const u = Fp2.C.get_CNR_Fp2()[0] # Cubic non-residue to construct 𝔽p6
  const v = Fp2.C.get_CNR_Fp2()[1]
  const Beta = Fp2.C.get_QNR_Fp()  # Quadratic non-residue to construct 𝔽p2
  # ξ = u + v x
  # and x² = β
  #
  # (c0 + c1 x) (u + v x) => u c0 + (u c0 + u c1)x + v c1 x²
  #                       => u c0 + β v c1 + (v c0 + u c1) x
  when a.fromComplexExtension() and u == 1 and v == 1:
    let t = a.c0
    a.c0 -= a.c1
    a.c1 += t
  else: # TODO: optim for inline
    a = ξ * a

# 𝔽p12
# ----------------------------------------------------------------

type
  Fp12*[C: static Curve] = object
    c0*, c1*: Fp6[C]

  γ = β
    # We call the non-residue γ (Gamma) on 𝔽p6 to avoid confusion between non-residue
    # of different tower level

func `*`*(_: typedesc[γ], a: Fp6): Fp6 {.noInit, inline.} =
  ## Multiply an element of 𝔽p6 by the cubic non-residue
  ## chosen to construct 𝔽p12
  ## For all curves γ = v with v the factor for 𝔽p6 coordinate
  ## and v³ = ξ
  ## (c0 + c1 v + c2 v²) v => ξ c2 + c0 v + c1 v²
  result.c0 = ξ * a.c2
  result.c1 = a.c0
  result.c2 = a.c1

func `*=`*(a: var Fp6, _: typedesc[γ]) {.inline.} =
  a = γ * a
