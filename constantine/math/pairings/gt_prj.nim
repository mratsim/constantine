# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/abstractions,
  constantine/named/algebras,
  constantine/math/arithmetic,
  constantine/math/extension_fields/towers

# debug
import constantine/math/io/io_extfields

# ############################################################
#                                                            #
#             Projective 𝔾ₜ & Extension Fields               #
#                                                            #
# ############################################################


# Projective extension fields
# ===========================
#
# This implements a new coordinate system for extension fields
# to accelerate Miller Loops, Final Exponentiation
# and computation on 𝔾ₜ.
#
# This uses Toom-Cook which requires dividing by an extra factor k
# after computation.
#
# We delay this, similar to how projective coordinates are used
# for elliptic curves.

type Fp6prj*[Name: static Algebra] {.borrow: `.`.} = distinct Fp6[Name]
  ## An implementation of 𝔽p6 over 𝔽p2 with
  ## special Toom-Cook multiplication/squaring
  ##
  ## Results are off by a factor 4.

template c0*(a: Fp6prj): auto =
  a.coords[0]
template c1*(a: Fp6prj): auto =
  a.coords[1]
template c2*(a: Fp6prj): auto =
  a.coords[2]

template `c0=`*(a: var Fp6prj, v: auto) =
  a.coords[0] = v
template `c1=`*(a: var Fp6prj, v: auto) =
  a.coords[1] = v
template `c2=`*(a: var Fp6prj, v: auto) =
  a.coords[2] = v

# Reimplementation of addition/substraction
# -----------------------------------------
# We cannot borrow here due to https://github.com/nim-lang/Nim/issues/23971

func `+=`*(a: var Fp6prj, b: Fp6prj) =
  staticFor i, 0, a.coords.len:
    a.coords[i] += b.coords[i]

func `-=`*(a: var Fp6prj, b: Fp6prj) =
  # We cannot borrow here due to https://github.com/nim-lang/Nim/issues/23971
  staticFor i, 0, a.coords.len:
    a.coords[i] -= b.coords[i]

func double*(r: var Fp6prj, a: Fp6prj) =
  ## Field out-of-place doubling
  staticFor i, 0, a.coords.len:
    r.coords[i].double(a.coords[i])

func double*(a: var Fp6prj) =
  ## Field in-place doubling
  staticFor i, 0, a.coords.len:
    a.coords[i].double()

func div2*(a: var Fp6prj) =
  ## Field in-place division by 2
  staticFor i, 0, a.coords.len:
    a.coords[i].div2()

func sum*(r: var Fp6prj, a, b: Fp6prj) =
  ## Sum ``a`` and ``b`` into ``r``
  staticFor i, 0, a.coords.len:
    r.coords[i].sum(a.coords[i], b.coords[i])

func diff*(r: var Fp6prj, a, b: Fp6prj) =
  ## Diff ``a`` and ``b`` into ``r``
  staticFor i, 0, a.coords.len:
    r.coords[i].diff(a.coords[i], b.coords[i])

# Projective multiplication & squaring
# -----------------------------------------

func mul_by_i(r{.noalias.}: var Fp2, a{.noalias.}: Fp2) =
  # (u + vi)i = -v + aui
  r.c0.neg(a.c1)
  r.c1 = a.c0

func mul_by_i(a: var Fp2) =
  # (u + vi)i = -v + aui
  var t {.noInit.}: typeof(a.c0)
  t.neg(a.c1)
  a.c1 = a.c0
  a.c0 = t

func prod_prj*[Name: static Algebra](
      r: var Fp6prj[Name], a, b: Fp6[Name]) =
  ## Multiply a and b returning scaled 4ab
  #
  # This uses a 4-point DFT
  # within a 5-point Toom-Cook
  #
  # In summary, we move from coefficient form to evaluation (Lagrange) form
  # multiply the evaluations and then interpolate the result
  static: doAssert Name.getNonResidueFp() == -1

  var u {.noInit.}: array[2, Fp2[Name]] # FFT Butterfly
  var t {.noInit.}: Fp2[Name]

  # Eval of a at 1,-𝑖,-1,𝑖,infinity. (if 𝑖 non-residue)
  t.mul_by_i(a.c1)       # 1i
  u[0].sum(a.c0, a.c2)
  u[1].diff(a.c0, a.c2)  # 2A+1i

  var aa {.noInit.}: array[4, Fp2[Name]]
  aa[0].sum(u[0], a.c1)
  aa[1].diff(u[1], t)
  aa[2].diff(u[0], a.c1)
  aa[3].sum(u[1], t)     # 6A+1i
  # aa[4] = a[4]

  # Eval of b at 1,-𝑖,-1,𝑖,infinity. (if 𝑖 non-residue)
  t.mul_by_i(b.c1)
  u[0].sum(b.c0, b.c2)
  u[1].diff(b.c0, b.c2)  # 8A+2i

  var bb {.noInit.}: array[4, Fp2[Name]]
  bb[0].sum(u[0], b.c1)
  bb[1].diff(u[1], t)
  bb[2].diff(u[0], b.c1)
  bb[3].sum(u[1], t)     # 12A+2i
  # bb[4] = b[4]

  # Hadamard product
  var rr {.noInit.}: array[5, Fp2[Name]]
  for i in 0 ..< 4:
    rr[i].prod(aa[i], bb[i])
  rr[4].prod(a.c2, b.c2) # 5M+12A+2i

  # Inverse DFT
  var v {.noInit.}: array[2, Fp2[Name]]
  u[0].sum(rr[0], rr[2])
  u[1].diff(rr[0], rr[2])
  v[0].sum(rr[1], rr[3])
  v[1].diff(rr[1], rr[3])

  v[1].mul_by_i()        # 5M+16A+3i

  # Interpolation
  rr[0].sum(u[0], v[0])
  rr[1].sum(u[1], v[1])
  rr[2].diff(u[0], v[0])
  rr[3].diff(u[1], v[1])
  rr[4] *= 4             # 5M+20A+2D+3i

  # Recomposition
  r.c0.prod(rr[3], NonResidue)
  r.c0 += rr[0]
  r.c0 -= rr[4]          # 5M+22A+2D+1m+3i

  r.c1.prod(rr[4], NonResidue)
  r.c1 += rr[1]

  r.c2 = rr[2]           # 5M+23A+2D+2m+3i

func square_prj*[Name: static Algebra](
      r: var Fp6prj[Name], a: Fp6[Name]) =
  ## Square a returning scaled 4a²
  #
  # This uses a 4-point DFT
  # within a 5-point Toom-Cook
  #
  # In summary, we move from coefficient form to evaluation (Lagrange) form
  # multiply the evaluations and then interpolate the result
  static: doAssert Name.getNonResidueFp() == -1

  var u {.noInit.}: array[2, Fp2[Name]] # FFT Butterfly
  var t {.noInit.}: Fp2[Name]

  # Eval of a at 1,-𝑖,-1,𝑖,infinity. (if 𝑖 non-residue)
  t.mul_by_i(a.c1)       # 1i
  u[0].sum(a.c0, a.c2)
  u[1].diff(a.c0, a.c2)  # 2A+1i

  var aa {.noInit.}: array[4, Fp2[Name]]
  aa[0].sum(u[0], a.c1)
  aa[1].diff(u[1], t)
  aa[2].diff(u[0], a.c1)
  aa[3].sum(u[1], t)     # 6A+1i
  # aa[4] = a[4]

  # Hadamard product
  var rr {.noInit.}: array[5, Fp2[Name]]
  for i in 0 ..< 4:
    rr[i].square(aa[i])
  rr[4].square(a.c2) # 5S+6A+1i

  # Inverse DFT
  var v {.noInit.}: array[2, Fp2[Name]]
  u[0].sum(rr[0], rr[2])
  u[1].diff(rr[0], rr[2])
  v[0].sum(rr[1], rr[3])
  v[1].diff(rr[1], rr[3])

  v[1].mul_by_i()        # 5S+10A+2i

  # Interpolation
  rr[0].sum(u[0], v[0])
  rr[1].sum(u[1], v[1])
  rr[2].diff(u[0], v[0])
  rr[3].diff(u[1], v[1])
  rr[4] *= 4             # 5S+14A+2D+2i

  # Recomposition
  r.c0.prod(rr[3], NonResidue)
  r.c0 += rr[0]
  r.c0 -= rr[4]          # 5S+16A+2D+1m+2i

  r.c1.prod(rr[4], NonResidue)
  r.c1 += rr[1]

  r.c2 = rr[2]           # 5S+17A+2D+1m+3i

# Torus-based Cryptography for 𝔾ₜ
# ===============================
#
# See paper XXX
#
# T₂(𝔽p6) compression
# -------------------
#
# By moving to a torus we can do 𝔾ₜ with just a single 𝔽p6 element
# similar to elliptic curve, to delay costly inversion we keep track an accumulator
# variable as well.
# We use (x, z) coordinates for this projective coordinate system
#
# T₆(𝔽p2) compression
# -------------------
#
# Besides a factor 2 compression, we can actually do a factor 3 compression
# for 𝔾ₜ with the following direct 𝔽p2 -> 𝔽p12 towering:
#
#   ɑ = a + bv = (a₀+a₁u+a₂u²) + (b₀+b₁u+b₂u²)v
#
# can be compressed into the representation
#   c = -(a+1)/b = c₀+c₁u+c₂u²
# with 3c₀c₁ - 3(t+1)c₂ - 1 = 0
#
# We do not use it for compute but it's an option for serialization.

type
  T2Prj*[F] {.borrow: `.`.} = distinct QuadraticExt[F]
    ## Torus of degree 2 over F
    ##
    ## From a GT element of the form
    ## a + bv
    ##
    ## Store x = -(a+1)/b
    ## and   z = 1 for affine

  T2Aff*[F] = distinct F
    ## Torus of degree 2 over F
    ##
    ## From a GT element of the form
    ## a + bv
    ##
    ## Store x = -(a+1)/b

template x[F](a: T2Prj[F]): F = a.coords[0]
template z[F](a: T2Prj[F]): F = a.coords[1]

proc fromGT_vartime*[F](r: var T2Aff[F], a: QuadraticExt[F]) =
  var t {.noInit.}, one {.noInit.}: F
  t.inv_vartime(a.c1)
  one.setOne()
  F(r).sum(a.c0, one)
  F(r).neg()
  F(r) *= t

proc fromGT_vartime*[F](r: var T2Prj[F], a: QuadraticExt[F]) =
  var t {.noInit.}: F
  t.inv_vartime(a.c1)
  r.z.setOne()
  r.x.sum(a.c0, r.z)
  r.x.neg()
  r.x *= t

proc fromTorus2_vartime*[F](r: var QuadraticExt[F], a: T2Aff[F]) =
  var num {.noInit.}, den {.noInit.}: typeof(r)

  num.c0 = F a
  num.c1.setMinusOne()
  den.c0 = F a
  den.c1.setOne()
  den.inv_vartime()
  r.prod(num, den)

proc fromTorus2_vartime*[F](r: var QuadraticExt[F], a: T2Prj[F]) =
  type QF = QuadraticExt[F]

  var t0 {.noInit.}, t1 {.noInit.}: QF
  t0.conj(QF(a))
  t1.inv_vartime(t0)
  t1.conj()

  r.prod(t0, t1)

proc mixedProd*[F](r: var T2Prj[F], a: T2Prj[F], b: T2Aff[F]) =
  ## Multiplication on a torus.
  ## b MUST be in the cyclotomic subgroup

  var u0 {.noInit.}, u1 {.noInit.}: F
  u0.prod(a.x, F b)
  u1.prod(a.z, F b)

  r.x.prod(a.z, NonResidue)
  r.x += u0
  r.z.sum(u1, a.x)

proc affineProd*[F](r: var T2Prj[F], a, b: T2Aff[F]) =
  r.z.sum(F a, F b)
  r.x.prod(F a, F b)

  var snr {.noInit.}: typeof(r.x.c1)
  snr.setOne()
  r.x.c1 += snr

proc affineSquare*[F](r: var T2Prj[F], a: T2Aff[F]) =

  r.z.double(F a)
  r.x.square(F a)

  var snr {.noInit.}: typeof(r.x.c1)
  snr.setOne()
  r.x.c1 += snr

proc prod*[F](r: var T2Prj[F], a, b: T2Prj[F]) {.inline.} =
  type QF = QuadraticExt[F]
  QF(r).prod(QF a, QF b)

proc square*[F](r: var T2Prj[F], a: T2Prj[F]) {.inline.} =
  type QF = QuadraticExt[F]
  QF(r).square(QF a)

proc inv*[F](r: var T2Prj[F], a: T2Prj[F]) {.inline.} =
  # Cyclotomic inversion on a Torus
  r.x.neg(a.x)
  r.z = a.z
