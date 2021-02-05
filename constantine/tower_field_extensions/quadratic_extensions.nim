# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../arithmetic,
  ../primitives,
  ./tower_common

# No exceptions allowed
{.push raises: [].}

# Commutative ring implementation for complex extension fields
# -------------------------------------------------------------------

func square_complex(r: var QuadraticExt, a: QuadraticExt) =
  ## Return a² in 𝔽p2 = 𝔽p[𝑖] in ``r``
  ## ``r`` is initialized/overwritten
  ##
  ## Requires a complex extension field
  # (c0, c1)² => (c0 + c1𝑖)²
  #           => c0² + 2 c0 c1𝑖 + (c1𝑖)²
  #           => c0²-c1² + 2 c0 c1𝑖
  #           => (c0²-c1², 2 c0 c1)
  #           or
  #           => ((c0-c1)(c0+c1), 2 c0 c1)
  #           => ((c0-c1)(c0-c1 + 2 c1), c0 * 2 c1)
  #
  # Costs (naive implementation)
  # - 1 Multiplication 𝔽p
  # - 2 Squarings 𝔽p
  # - 1 Doubling 𝔽p
  # - 1 Substraction 𝔽p
  # Stack: 4 * ModulusBitSize (4x 𝔽p element)
  #
  # Or (with 1 less Mul/Squaring at the cost of 1 addition and extra 2 𝔽p stack space)
  #
  # - 2 Multiplications 𝔽p
  # - 1 Addition 𝔽p
  # - 1 Doubling 𝔽p
  # - 1 Substraction 𝔽p
  #
  # To handle aliasing between r and a, we need
  # r to be used only when a is unneeded
  # so we can't use r fields as a temporary
  mixin fromComplexExtension
  static: doAssert r.fromComplexExtension()

  var v0 {.noInit.}, v1 {.noInit.}: typeof(r.c0)
  v0.diff(a.c0, a.c1)    # v0 = c0 - c1               [1 Sub]
  v1.sum(a.c0, a.c1)     # v1 = c0 + c1               [1 Dbl, 1 Sub]
  r.c1.prod(a.c0, a.c1)  # r.c1 = c0 c1               [1 Mul, 1 Dbl, 1 Sub]
  # aliasing: a unneeded now
  r.c1.double()          # r.c1 = 2 c0 c1             [1 Mul, 2 Dbl, 1 Sub]
  r.c0.prod(v0, v1)      # r.c0 = (c0 + c1)(c0 - c1)  [2 Mul, 2 Dbl, 1 Sub]

func prod_complex(r: var QuadraticExt, a, b: QuadraticExt) =
  ## Return a * b in 𝔽p2 = 𝔽p[𝑖] in ``r``
  ## ``r`` is initialized/overwritten
  ##
  ## Requires a complex extension field
  # (a0, a1) (b0, b1) => (a0 + a1𝑖) (b0 + b1𝑖)
  #                   => (a0 b0 - a1 b1) + (a0 b1 + a1 b0) 𝑖
  #
  # In Fp, multiplication has cost O(n²) with n the number of limbs
  # while addition has cost O(3n) (n for addition, n for overflow, n for conditional substraction)
  # and substraction has cost O(2n) (n for substraction + underflow, n for conditional addition)
  #
  # Even for 256-bit primes, we are looking at always a minimum of n=5 limbs (with 2^63 words)
  # where addition/substraction are significantly cheaper than multiplication
  #
  # So we always reframe the imaginary part using Karatsuba approach to save a multiplication
  # (a0, a1) (b0, b1) => (a0 b0 - a1 b1) + 𝑖( (a0 + a1)(b0 + b1) - a0 b0 - a1 b1 )
  #
  # Costs (naive implementation)
  # - 4 Multiplications 𝔽p
  # - 1 Addition 𝔽p
  # - 1 Substraction 𝔽p
  # Stack: 6 * ModulusBitSize (4x 𝔽p element + 2x named temporaries)
  #
  # Costs (Karatsuba)
  # - 3 Multiplications 𝔽p
  # - 3 Substraction 𝔽p (2 are fused)
  # - 2 Addition 𝔽p
  # Stack: 6 * ModulusBitSize (4x 𝔽p element + 2x named temporaries + 1 in-place multiplication temporary)
  mixin fromComplexExtension
  static: doAssert r.fromComplexExtension()

  # TODO: GCC is adding an unexplainable 30 cycles tax to this function (~10% slow down)
  #       for seemingly no reason

  when false: # Single-width implementation - BLS12-381
              # Clang 348 cycles on i9-9980XE @3.9 GHz
    var a0b0 {.noInit.}, a1b1 {.noInit.}: typeof(r.c0)
    a0b0.prod(a.c0, b.c0)                                         # [1 Mul]
    a1b1.prod(a.c1, b.c1)                                         # [2 Mul]

    r.c0.sum(a.c0, a.c1)  # r0 = (a0 + a1)                        # [2 Mul, 1 Add]
    r.c1.sum(b.c0, b.c1)  # r1 = (b0 + b1)                        # [2 Mul, 2 Add]
    # aliasing: a and b unneeded now
    r.c1 *= r.c0          # r1 = (b0 + b1)(a0 + a1)               # [3 Mul, 2 Add] - 𝔽p temporary

    r.c0.diff(a0b0, a1b1) # r0 = a0 b0 - a1 b1                    # [3 Mul, 2 Add, 1 Sub]
    r.c1 -= a0b0          # r1 = (b0 + b1)(a0 + a1) - a0b0        # [3 Mul, 2 Add, 2 Sub]
    r.c1 -= a1b1          # r1 = (b0 + b1)(a0 + a1) - a0b0 - a1b1 # [3 Mul, 2 Add, 3 Sub]

  else: # Double-width implementation with lazy reduction
        # Clang 341 cycles on i9-9980XE @3.9 GHz
    var a0b0 {.noInit.}, a1b1 {.noInit.}: doubleWidth(typeof(r.c0))
    var d {.noInit.}: doubleWidth(typeof(r.c0))
    const msbSet = r.c0.typeof.canUseNoCarryMontyMul()

    a0b0.mulNoReduce(a.c0, b.c0)     # 44 cycles - cumul 44
    a1b1.mulNoReduce(a.c1, b.c1)     # 44 cycles - cumul 88
    when msbSet:
      r.c0.sum(a.c0, a.c1)
      r.c1.sum(b.c0, b.c1)
    else:
      r.c0.sumNoReduce(a.c0, a.c1)   # 5 cycles  - cumul 93
      r.c1.sumNoReduce(b.c0, b.c1)   # 5 cycles  - cumul 98
    # aliasing: a and b unneeded now
    d.mulNoReduce(r.c0, r.c1)        # 44 cycles - cumul 142
    when msbSet:
      d -= a0b0
      d -= a1b1
    else:
      d.diffNoReduce(d, a0b0)        # 11 cycles - cumul 153
      d.diffNoReduce(d, a1b1)        # 11 cycles - cumul 164
    a0b0.diff(a0b0, a1b1)            # 19 cycles - cumul 183
    r.c0.reduce(a0b0)                # 50 cycles - cumul 233
    r.c1.reduce(d)                   # 50 cycles - cumul 288

  # Single-width [3 Mul, 2 Add, 3 Sub]
  #    3*88 + 2*14 + 3*14 = 334 theoretical cycles
  #    348 measured
  # Double-Width
  #    288 theoretical cycles
  #    329 measured
  #    Unexplained 40 cycles diff between theo and measured
  #    and unexplained 30 cycles between Clang and GCC
  #    - Function calls?
  #    - push/pop stack?

func mul_sparse_complex_by_0y(
       r: var QuadraticExt, a: QuadraticExt,
       sparseB: auto) =
  ## Multiply `a` by `b` with sparse coordinates (0, y)
  ## On a complex quadratic extension field 𝔽p2 = 𝔽p[𝑖]
  #
  # r0 = a0 b0 - a1 b1
  # r1 = (a0 + a1) (b0 + b1) - a0 b0 - a1 b1 (Karatsuba)
  #
  # with b0 = 0, hence
  #
  # r0 = - a1 b1
  # r1 = (a0 + a1) b1 - a1 b1 = a0 b1
  mixin fromComplexExtension
  static: doAssert r.fromComplexExtension()

  when typeof(sparseB) is typeof(a):
    template b(): untyped = sparseB.c1
  elif typeof(sparseB) is typeof(a.c0):
    template b(): untyped = sparseB
  else:
    {.error: "sparseB type is " & $typeof(sparseB) &
      " which does not match with either a (" & $typeof(a) &
      ") or a.c0 (" & $typeof(a.c0) & ")".}

  var t{.noInit.}: typeof(a.c0)
  t.prod(a.c1, b)
  r.c1.prod(a.c0, b)
  r.c0.neg(t)

# Commutative ring implementation for generic quadratic extension fields
# -------------------------------------------------------------------

func square_generic(r: var QuadraticExt, a: QuadraticExt) =
  ## Return a² in ``r``
  ## ``r`` is initialized/overwritten
  # Algorithm (with β the non-residue in the base field)
  #
  # (c0, c1)² => (c0 + c1 w)²
  #           => c0² + 2 c0 c1 w + c1²w²
  #           => c0² + β c1² + 2 c0 c1 w
  #           => (c0² + β c1², 2 c0 c1)
  # We have 2 squarings and 1 multiplication in the base field
  # which are significantly more costly than additions.
  # For example when construction 𝔽p12 from 𝔽p6:
  # - 4 limbs like BN254:     multiplication is 20x slower than addition/substraction
  # - 6 limbs like BLS12-381: multiplication is 28x slower than addition/substraction
  #
  # We can save operations with one of the following expressions
  # of c0² + β c1² and noticing that c0c1 is already computed for the "y" coordinate
  #
  # Alternative 1:
  #   c0² + β c1² <=> (c0 - c1)(c0 - β c1) + β c0c1 + c0c1
  #
  # Alternative 2:
  #   c0² + β c1² <=> (c0 + c1)(c0 + β c1) - β c0c1 - c0c1
  mixin prod
  var v0 {.noInit.}, v1 {.noInit.}: typeof(r.c0)

  # v1 <- (c0 + β c1)
  v1 = a.c1
  v1 *= NonResidue
  v1 += a.c0

  # v0 <- (c0 + c1)(c0 + β c1)
  v0.sum(a.c0, a.c1)
  v0 *= v1

  # v1 <- c0 c1
  v1.prod(a.c0, a.c1)

  # aliasing: a unneeded now

  # r0 = (c0 + c1)(c0 + β c1) - c0c1
  v0 -= v1

  # r1 = 2 c0c1
  r.c1.double(v1)

  # r0 = (c0 + c1)(c0 + β c1) - c0c1 - β c0c1
  v1 *= NonResidue
  r.c0.diff(v0, v1)

func prod_generic(r: var QuadraticExt, a, b: QuadraticExt) =
  ## Returns r = a * b
  # Algorithm (with β the non-residue in the base field)
  #
  # r0 = a0 b0 + β a1 b1
  # r1 = (a0 + a1) (b0 + b1) - a0 b0 - a1 b1 (Karatsuba)
  mixin prod
  var v0 {.noInit.}, v1 {.noInit.}, v2 {.noInit.}: typeof(r.c0)

  # v2 <- (a0 + a1)(b0 + b1)
  v0.sum(a.c0, a.c1)
  v1.sum(b.c0, b.c1)
  v2.prod(v0, v1)

  # v0 <- a0 b0
  # v1 <- a1 b1
  v0.prod(a.c0, b.c0)
  v1.prod(a.c1, b.c1)

  # aliasing: a and b unneeded now

  # r1 <- (a0 + a1)(b0 + b1) - a0 b0 - a1 b1
  r.c1.diff(v2, v1)
  r.c1 -= v0

  # r0 <- a0 b0 + β a1 b1
  v1 *= NonResidue
  r.c0.sum(v0, v1)

func mul_sparse_generic_by_x0(r: var QuadraticExt, a, sparseB: QuadraticExt) =
  ## Multiply `a` by `b` with sparse coordinates (x, 0)
  ## On a generic quadratic extension field
  # Algorithm (with β the non-residue in the base field)
  #
  # r0 = a0 b0 + β a1 b1
  # r1 = (a0 + a1) (b0 + b1) - a0 b0 - a1 b1 (Karatsuba)
  #
  # with b1 = 0, hence
  #
  # r0 = a0 b0
  # r1 = (a0 + a1) b0 - a0 b0 = a1 b0
  mixin prod
  template b(): untyped = sparseB

  r.c0.prod(a.c0, b.c0)
  r.c1.prod(a.c1, b.c0)

func mul_sparse_generic_by_0y(
       r: var QuadraticExt, a: QuadraticExt,
       sparseB: auto) =
  ## Multiply `a` by `b` with sparse coordinates (0, y)
  ## On a generic quadratic extension field
  # Algorithm (with β the non-residue in the base field)
  #
  # r0 = a0 b0 + β a1 b1
  # r1 = (a0 + a1) (b0 + b1) - a0 b0 - a1 b1 (Karatsuba)
  #
  # with b0 = 0, hence
  #
  # r0 = β a1 b1
  # r1 = (a0 + a1) b1 - a1 b1 = a0 b1
  when typeof(sparseB) is typeof(a):
    template b(): untyped = sparseB.c1
  elif typeof(sparseB) is typeof(a.c0):
    template b(): untyped = sparseB
  else:
    {.error: "sparseB type is " & $typeof(sparseB) &
      " which does not match with either a (" & $typeof(a) &
      ") or a.c0 (" & $typeof(a.c0) & ")".}

  var t{.noInit.}: typeof(a.c0)

  t.prod(a.c1, b)
  t *= NonResidue
  r.c1.prod(a.c0, b)
  # aliasing: a unneeded now
  r.c0 = t

func invImpl(r: var QuadraticExt, a: QuadraticExt) =
  ## Compute the multiplicative inverse of ``a``
  ##
  ## The inverse of 0 is 0.
  #
  # Algorithm:
  #
  # 1 / (a0 + a1 w) <=> (a0 - a1 w) / (a0 + a1 w)(a0 - a1 w)
  #                 <=> (a0 - a1 w) / (a0² - a1² w²)
  # with w being our coordinate system and β the quadratic non-residue
  # we have w² = β
  # So the inverse is (a0 - a1 w) / (a0² - β a1²)
  mixin fromComplexExtension

  # [2 Sqr, 1 Add]
  var v0 {.noInit.}, v1 {.noInit.}: typeof(r.c0)
  v0.square(a.c0)
  v1.square(a.c1)
  when r.fromComplexExtension():
    v0 += v1
  else:
    var t = v1
    t *= NonResidue
    v0 -= t               # v0 = a0² - β a1² (the norm / squared magnitude of a)

  # [1 Inv, 2 Sqr, 1 Add]
  v1.inv(v0)              # v1 = 1 / (a0² - β a1²)

  # [1 Inv, 2 Mul, 2 Sqr, 1 Add, 1 Neg]
  r.c0.prod(a.c0, v1)     # r0 = a0 / (a0² - β a1²)
  v0.neg(v1)              # v0 = -1 / (a0² - β a1²)
  r.c1.prod(a.c1, v0)     # r1 = -a1 / (a0² - β a1²)

# Exported symbols
# -------------------------------------------------------------------

{.push inline.}

func conj*(a: var QuadraticExt) =
  ## Computes the conjugate in-place
  a.c1.neg()

func conj*(r: var QuadraticExt, a: QuadraticExt) =
  ## Computes the conjugate out-of-place
  r.c0 = a.c0
  r.c1.neg(a.c1)

func conjneg*(a: var QuadraticExt) =
  ## Computes the negated conjugate in-place
  a.c0.neg()

func conjneg*(r: var QuadraticExt, a: QuadraticExt) =
  ## Computes the negated conjugate out-of-place
  r.c0.neg(a.c0)
  r.c1 = a.c1

func square*(r: var QuadraticExt, a: QuadraticExt) =
  mixin fromComplexExtension
  when r.fromComplexExtension():
    r.square_complex(a)
  else:
    r.square_generic(a)

func prod*(r: var QuadraticExt, a, b: QuadraticExt) =
  mixin fromComplexExtension
  when r.fromComplexExtension():
    r.prod_complex(a, b)
  else:
    r.prod_generic(a, b)

func inv*(r: var QuadraticExt, a: QuadraticExt) =
  ## Compute the multiplicative inverse of ``a``
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  r.invImpl(a)

func inv*(a: var QuadraticExt) =
  ## Compute the multiplicative inverse of ``a``
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  a.invImpl(a)

func `*=`*(a: var QuadraticExt, b: QuadraticExt) =
  ## In-place multiplication
  a.prod(a, b)

func square*(a: var QuadraticExt) =
  ## In-place squaring
  a.square(a)

func mul_sparse_by_0y*(r: var QuadraticExt, a: QuadraticExt, sparseB: auto) =
  ## Sparse multiplication
  mixin fromComplexExtension
  when a.fromComplexExtension():
    r.mul_sparse_complex_by_0y(a, sparseB)
  else:
    r.mul_sparse_generic_by_0y(a, sparseB)

func mul_sparse_by_0y*(a: var QuadraticExt, sparseB: auto) =
  ## Sparse in-place multiplication
  a.mul_sparse_by_0y(a, sparseB)

func mul_sparse_by_x0*(a: var QuadraticExt, sparseB: QuadraticExt) =
  ## Sparse in-place multiplication
  a.mul_sparse_generic_by_x0(a, sparseB)

{.pop.} # inline
{.pop.} # raises no exceptions
