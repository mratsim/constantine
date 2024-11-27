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
template `x=`[F](a: var T2Prj[F], v: F) = a.coords[0] = v
template `z=`[F](a: var T2Prj[F], v: F) = a.coords[1] = v

proc setNeutral*[F](a: var T2Aff[F]) =
  # We special-case the neutral element to 0
  # TODO: this is in case an element of the Torus might be compressed
  # to coordinate 1
  # TODO: Can a GT element of the form a + bv have a == 0?
  F(a).setZero()

proc isNeutral*[F](a: T2Aff[F]): SecretBool =
  F(a).isZero()

proc setNeutral*(a: var T2Prj) =
  a.x.setOne()
  a.z.setZero()

proc isNeutral*(a: T2Prj): SecretBool =
  a.z.isZero()

proc fromGT_vartime*[F](r: var T2Aff[F], a: QuadraticExt[F]) =
  # Special case identity element
  if bool a.isOne():
    r.setNeutral()
    return

  var t {.noInit.}, one {.noInit.}: F
  t.inv_vartime(a.c1)
  one.setOne()
  F(r).sum(a.c0, one)
  F(r).neg()
  F(r) *= t

proc fromGT_vartime*[F](r: var T2Prj[F], a: QuadraticExt[F]) =
  # Special case identity element
  if bool a.isOne():
    r.setNeutral()
    return

  var t {.noInit.}: F
  t.inv_vartime(a.c1)
  r.z.setOne()
  r.x.sum(a.c0, r.z)
  r.x.neg()
  r.x *= t

proc fromTorus2_vartime*[F](r: var QuadraticExt[F], a: T2Aff[F]) =

  # Special case identity element
  if bool a.isNeutral():
    r.setNeutral()
    return

  var num {.noInit.}, den {.noInit.}: typeof(r)
  num.c0 = F a
  num.c1.setMinusOne()
  den.c0 = F a
  den.c1.setOne()
  den.inv_vartime()
  r.prod(num, den)

proc fromTorus2_vartime*[F](r: var QuadraticExt[F], a: T2Prj[F]) =

  # Special case identity element
  if bool a.isNeutral():
    r.setOne()
    return

  type QF = QuadraticExt[F]

  var t0 {.noInit.}, t1 {.noInit.}: QF
  t0.conj(QF(a))
  t1.inv_vartime(t0)
  t1.conj()

  r.prod(t0, t1)

proc fromAffine_vartime*[F](r: var T2Prj[F], a: T2Aff[F]) =
  mixin `x=`
  if bool a.isNeutral():
    r.setNeutral()
  else:
    r.coords[0] = F(a) # r.x doesn't work despite bind, mixin, exports and usual generic sandwich workarounds
    r.z.setOne()

proc mixedProd_vartime*[F](r: var T2Prj[F], a: T2Prj[F], b: T2Aff[F]) =
  ## Multiplication on a torus.
  ## b MUST be in the cyclotomic subgroup

  # Special case identity element
  if bool a.isNeutral():
    r.fromAffine_vartime(b) # handles b == 1 as well
    return
  if bool b.isNeutral():
    r = a
    return

  var u0 {.noInit.}, u1 {.noInit.}, t {.noInit.}: F
  u0.prod(a.x, F b)
  u1.prod(a.z, F b)
  t.prod(a.z, NonResidue)

  # Aliasing: a.x must be read before r.x is written to
  r.z.sum(u1, a.x)
  r.x.sum(u0, t)

proc affineProd_vartime*[F](r: var T2Prj[F], a, b: T2Aff[F]) =

  # Special case identity element
  if bool a.isNeutral():
    r.fromAffine_vartime(b) # handles b == 1 as well
    return
  if bool b.isNeutral():
    r.fromAffine_vartime(a)
    return

  r.z.sum(F a, F b)
  r.x.prod(F a, F b)

  var snr {.noInit.}: typeof(r.x.c1)
  snr.setOne()
  r.x.c1 += snr

proc affineSquare_vartime*[F](r: var T2Prj[F], a: T2Aff[F]) =

  # Special case identity element
  if bool a.isNeutral():
    r.setNeutral()
    return

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

template cyclotomic_square*[F](r: var T2Prj[F], a: T2Prj[F]) =
  # Alias
  r.square(a)

template cyclotomic_square*[F](a: var T2Prj[F]) =
  # Alias
  a.square(a)

proc inv*[F](r: var T2Aff[F], a: T2Aff[F]) {.inline.} =
  ## Cyclotomic inversion on a Torus
  # Note: for neutral element this is valid only
  # if the implementation uses 0 as special-value
  F(r).neg(F(a))

proc inv*[F](r: var T2Prj[F], a: T2Prj[F]) {.inline.} =
  ## Cyclotomic inversion on a Torus
  r.x.neg(a.x)
  r.z = a.z

# Batched conversions
# -------------------

proc batchFromGT_vartime*[F](dst: var openArray[T2Aff[F]],
                             src: openArray[QuadraticExt[F]]) =
  ## Batch conversion to Torus
  ##
  ## This requires all `src` to be different from 0.
  ## This is always true for elements in 𝔾ₜ.
  ##
  ## This replaces all inversions but one (on 𝔽p6 for 𝔾ₜ in 𝔽p12)
  ## by 3 multiplications.
  ##
  ## Note: on 𝔽p6, the ratio of inversion I/M is about 3.8
  ## so this is about a ~25% speedup

  # TODO: handle neutral element
  # TODO: Parallel batch inversion

  debug: doAssert dst.len == src.len

  F(dst[0]) = src[0].c1
  for i in 1 ..< dst.len:
    F(dst[i]).prod(F dst[i-1], src[i].c1)

  var accInv {.noInit.}: F
  accInv.inv_vartime(F dst[dst.len-1])

  for i in countdown(dst.len-1, 1):
    # Compute inverse
    F(dst[i]).prod(accInv, F dst[i-1])
    # Next iteration
    accInv *= src[i].c1

  F(dst[0]) = accInv

  var minusOne {.noInit.}: F
  minusOne.setMinusOne()

  for i in 0 ..< dst.len:
    var t {.noInit.}: F
    t.diff(minusOne, src[i].c0)
    F(dst[i]) *= t

proc batchFromTorus2_vartime*[F](dst: var openArray[QuadraticExt[F]],
                                 src: openArray[T2Prj[F]]) =
  ## Batch conversion to 𝔾ₜ
  ##
  ## This requires all `src` to be different from 0.
  ## This is always true for elements in 𝔾ₜ.
  ##
  ## This replaces all inversions but one (on 𝔽p12 for 𝔾ₜ in 𝔽p12)
  ## by 3 multiplications.
  ##
  ## Note: on 𝔽p12, the ratio of inversion I/M is about 3
  ## so this has likely no speedup, and is not trivial to parallelize

  # TODO: handle neutral element
  debug: doAssert dst.len == src.len

  # We consciously choose to recompute conj(src[i]) to avoid an allocation
  # On BLS12-381, src[i] elements are 12*48 bytes = 576 bytes
  type QF = QuadraticExt[F]

  dst[0].conj(QF src[0])
  for i in 1 ..< dst.len:
    var ti {.noInit.}: QF
    ti.conj(QF src[i])
    dst[i].prod(dst[i-1], ti)

  var accInv{.noInit.}: QF
  accInv.inv(dst[dst.len-1])

  for i in countdown(dst.len-1, 1):
    # Compute inverse
    dst[i].prod(accInv, dst[i-1])
    # Conjugate it
    dst[i].conj()
    # Next iteration
    var ti {.noInit.}: QF
    ti.conj(QF src[i])
    accInv *= ti
    # Finalize conversion
    dst[i] *= ti

  dst[0].conj(accInv)
  var t {.noInit.}: QF
  t.conj(QF src[0])
  dst[0] *= t

func toHex*[F](a: T2Aff[F] or T2Prj[F], indent = 0, order: static Endianness = bigEndian): string =
  var t {.noInit.}: QuadraticExt[F]
  t.fromTorus2_vartime(a)
  t.toHex(indent, order)

when isMainModule:
  var a, c: QuadraticExt[Fp6[BLS12_381]]
  var b: T2Prj[Fp6[BLS12_381]]

  a.setOne()
  b.fromGT_vartime(a)
  c.fromTorus2_vartime(b)

  echo "a: ", a.toHex(indent = 4)
  echo "b: ", QuadraticExt[Fp6[BLS12_381]](b).toHex(indent = 4)
  echo "c: ", c.toHex(indent = 4)
