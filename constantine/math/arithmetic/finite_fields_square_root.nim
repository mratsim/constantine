# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/abstractions,
  ../config/curves,
  ../constants/zoo_square_roots,
  ./bigints, ./finite_fields, ./limbs_exgcd

# ############################################################
#
#                Field arithmetic square roots
#
# ############################################################

# No exceptions allowed
{.push raises: [].}
{.push inline.}

# Specialized routine for p ≡ 3 (mod 4)
# ------------------------------------------------------------

func invsqrt_p3mod4(r: var Fp, a: Fp) =
  ## Compute the inverse square root of ``a``
  ##
  ## This requires ``a`` to be a square
  ## and the prime field modulus ``p``: p ≡ 3 (mod 4)
  ##
  ## The result is undefined otherwise
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  # Algorithm
  #
  #
  # From Euler's criterion:
  #    𝛘(a) = a^((p-1)/2)) ≡ 1 (mod p) if square
  # a^((p-1)/2)) * a^-1 ≡ 1/a  (mod p)
  # a^((p-3)/2))        ≡ 1/a  (mod p)
  # a^((p-3)/4))        ≡ 1/√a (mod p)      # Requires p ≡ 3 (mod 4)
  static: doAssert Fp.C.has_P_3mod4_primeModulus()
  when FP.C.hasSqrtAddchain():
    r.invsqrt_addchain(a)
  else:
    r = a
    r.pow_vartime(Fp.getPrimeMinus3div4_BE())

# Specialized routine for p ≡ 5 (mod 8)
# ------------------------------------------------------------

func invsqrt_p5mod8(r: var Fp, a: Fp) =
  ## Compute the inverse square root of ``a``
  ##
  ## This requires ``a`` to be a square
  ## and the prime field modulus ``p``: p ≡ 5 (mod 8)
  ##
  ## The result is undefined otherwise
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  #
  # Intuition: Branching algorithm, that requires √-1 (mod p) precomputation
  #
  # From Euler's criterion:
  #    𝛘(a) = a^((p-1)/2)) ≡ 1 (mod p) if square
  # a^((p-1)/4))² ≡ 1 (mod p)
  # if a is square, a^((p-1)/4)) ≡ ±1 (mod p)
  #
  # Case a^((p-1)/4)) ≡ 1 (mod p)
  #   a^((p-1)/4)) * a⁻¹ ≡  1/a  (mod p)
  #   a^((p-5)/4))        ≡  1/a  (mod p)
  #   a^((p-5)/8))        ≡ ±1/√a (mod p)  # Requires p ≡ 5 (mod 8)
  #
  # Case a^((p-1)/4)) ≡ -1 (mod p)
  #   a^((p-1)/4)) * a⁻¹ ≡  -1/a  (mod p)
  #   a^((p-5)/4))       ≡  -1/a  (mod p)
  #   a^((p-5)/8))       ≡ ± √-1/√a (mod p)
  # as p ≡ 5 (mod 8), hence 𝑖 ∈ Fp with 𝑖² ≡ −1 (mod p)
  #   a^((p-5)/8)) * 𝑖    ≡ ± 1/√a (mod p)
  #
  # Atkin Algorithm: branchless, no precomputation
  #   Atkin, 1992, http://algo.inria.fr/seminars/sem91-92/atkin.pdf
  #   Gora Adj 2012, https://eprint.iacr.org/2012/685
  #   Rotaru, 2013, https://profs.info.uaic.ro/~siftene/fi125(1)04.pdf
  #
  # We express √a = αa(β − 1) where β² = −1 and 2aα² = β
  # confirm that        (αa(β − 1))² = α²a²(β²-2β+1) = α²a²β² - 2a²α²β - a²α²
  # Which simplifies to (αa(β − 1))² = -aβ² = a
  #
  # 𝛘(2) = 2^((p-1)/2) ≡ (-1)^((p²-1)/8) (mod p) hence 2 is QR iff p ≡ ±1 (mod 8)
  # Here p ≡ 5 (mod 8), so 2 is a QNR, hence 2^((p-1)/2) ≡ -1 (mod 8)
  #
  # The product of a quadratic non-residue with quadratic residue is a QNR
  # as 𝛘(QNR*QR) = 𝛘(QNR).𝛘(QR) = -1*1 = -1, hence:
  #   (2a)^((p-1)/2) ≡ -1 (mod p)
  #   (2a)^((p-1)/4) ≡ ± √-1 (mod p)
  #
  # Hence we set β = (2a)^((p-1)/4)
  # and α = (β/2a)⁽¹⸍²⁾= (2a)^(((p-1)/4 - 1)/2) = (2a)^((p-5)/8)
  static: doAssert Fp.C.has_P_5mod8_primeModulus()
  var alpha{.noInit.}, beta{.noInit.}: Fp

  # α = (2a)^((p-5)/8)
  alpha.double(a)
  beta = alpha
  when Fp.C.hasSqrtAddchain():
    alpha.invsqrt_addchain_pminus5over8(alpha)
  else:
    alpha.pow_vartime(Fp.getPrimeMinus5div8_BE())

  # Note: if r aliases a, for inverse square root we don't use `a` again

  # β = 2aα²
  r.square(alpha)
  beta *= r

  # √a = αa(β − 1), so 1/√a = α(β − 1)
  r.setOne()
  beta -= r
  r.prod(alpha, beta)


# Specialized routines for addchain-based square roots
# ------------------------------------------------------------

{.pop.} # inline

# Tonelli Shanks for any prime
# ------------------------------------------------------------

func precompute_tonelli_shanks(a_pre_exp: var Fp, a: Fp) =
  when FP.C.hasTonelliShanksAddchain():
    a_pre_exp.precompute_tonelli_shanks_addchain(a)
  else:
    a_pre_exp = a
    a_pre_exp.pow_vartime(Fp.C.tonelliShanks(exponent))

func invsqrt_tonelli_shanks_pre(
       invsqrt: var Fp,
       a, a_pre_exp: Fp) =
  ## Compute the inverse_square_root
  ## of `a` via constant-time Tonelli-Shanks
  ##
  ## a_pre_exp is a precomputation a^((p-1-2^e)/(2*2^e))
  ## That is shared with the simultaneous isSquare routine
  template z: untyped = a_pre_exp
  template r: untyped = invsqrt
  var t {.noInit.}: Fp
  const e = Fp.C.tonelliShanks(twoAdicity)

  t.square(z)
  t *= a
  r = z
  var b {.noInit.} = t
  var root {.noInit.} = Fp.C.tonelliShanks(root_of_unity)

  var buf {.noInit.}: Fp

  for i in countdown(e, 2, 1):
    if i-2 >= 1:
      b.square_repeated(i-2)

    let bNotOne = not b.isOne()
    buf.prod(r, root)
    r.ccopy(buf, bNotOne)
    root.square()
    buf.prod(t, root)
    t.ccopy(buf, bNotOne)
    b = t

func invsqrt_tonelli_shanks*(r: var Fp, a: Fp) =
  ## Compute the inverse square root of ``a``
  ##
  ## This requires ``a`` to be a square
  ##
  ## The result is undefined otherwise
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  ## This procedure is constant-time
  var a_pre_exp{.noInit.}: Fp
  a_pre_exp.precompute_tonelli_shanks(a)
  invsqrt_tonelli_shanks_pre(r, a, a_pre_exp)

# Public routines
# ------------------------------------------------------------

{.push inline.}

func invsqrt*[C](r: var Fp[C], a: Fp[C]) =
  ## Compute the inverse square root of ``a``
  ##
  ## This requires ``a`` to be a square
  ##
  ## The result is undefined otherwise
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  ## This procedure is constant-time
  when C.has_P_3mod4_primeModulus():
    r.invsqrt_p3mod4(a)
  elif C.has_P_5mod8_primeModulus():
    r.invsqrt_p5mod8(a)
  else:
    r.invsqrt_tonelli_shanks(a)

func sqrt*[C](a: var Fp[C]) =
  ## Compute the square root of ``a``
  ##
  ## This requires ``a`` to be a square
  ##
  ## The result is undefined otherwise
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  ## This procedure is constant-time
  var t {.noInit.}: Fp[C]
  t.invsqrt(a)
  a *= t

func sqrt_invsqrt*[C](sqrt, invsqrt: var Fp[C], a: Fp[C]) =
  ## Compute the square root and inverse square root of ``a``
  ##
  ## This requires ``a`` to be a square
  ##
  ## The result is undefined otherwise
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  invsqrt.invsqrt(a)
  sqrt.prod(invsqrt, a)

func sqrt_invsqrt_if_square*[C](sqrt, invsqrt: var Fp[C], a: Fp[C]): SecretBool  =
  ## Compute the square root and ivnerse square root of ``a``
  ##
  ## This returns true if ``a`` is square and sqrt/invsqrt contains the square root/inverse square root
  ##
  ## The result is undefined otherwise
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  sqrt_invsqrt(sqrt, invsqrt, a)
  var test {.noInit.}: Fp[C]
  test.square(sqrt)
  result = test == a

func sqrt_if_square*[C](a: var Fp[C]): SecretBool =
  ## If ``a`` is a square, compute the square root of ``a``
  ## if not, ``a`` is undefined.
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  ## This procedure is constant-time
  var sqrt{.noInit.}, invsqrt{.noInit.}: Fp[C]
  result = sqrt_invsqrt_if_square(sqrt, invsqrt, a)
  a = sqrt

func invsqrt_if_square*[C](r: var Fp[C], a: Fp[C]): SecretBool =
  ## If ``a`` is a square, compute the inverse square root of ``a``
  ## if not, ``a`` is undefined.
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  ## This procedure is constant-time
  var sqrt{.noInit.}: Fp[C]
  result = sqrt_invsqrt_if_square(sqrt, r, a)

# Legendre symbol / Euler's Criterion / Kronecker's symbol
# ------------------------------------------------------------

func isSquare*(a: Fp): SecretBool =
  ## Returns true if ``a`` is a square (quadratic residue) in 𝔽p
  ##
  ## Assumes that the prime modulus ``p`` is public.
  var aa {.noInit.}: matchingBigInt(Fp.C)
  aa.fromField(a)
  let symbol = legendre(aa.limbs, Fp.fieldMod().limbs, aa.bits)
  return not(symbol == MaxWord)

{.pop.} # inline

# Fused routines
# ------------------------------------------------------------

func sqrt_ratio_if_square*(r: var Fp, u, v: Fp): SecretBool {.inline.} =
  ## If u/v is a square, compute √(u/v)
  ## if not, the result is undefined
  ##
  ## r must not alias u or v
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both (u/v)² == (-u/v)²
  ## This procedure returns a deterministic result
  ## This procedure is constant-time

  # u/v is square iff 𝛘(u/v) = 1 (mod p)
  # As 𝛘(a) = 1 or -1
  # 𝛘(u/v) = 𝛘(ub)
  var uv{.noInit.}: Fp
  uv.prod(u, v)                    # uv
  result = r.invsqrt_if_square(uv) # 1/√uv
  r *= u                           # √u/√v

{.pop.} # raises no exceptions
