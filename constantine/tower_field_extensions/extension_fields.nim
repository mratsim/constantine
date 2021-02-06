# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/common,
  ../primitives,
  ../arithmetic

# Note: to avoid burdening the Nim compiler, we rely on generic extension
# to complain if the base field procedures don't exist

# No exceptions allowed
{.push raises: [].}
{.push inline.}

# ############################################################
#                                                            #
#                    Extension Fields                        #
#                                                            #
# ############################################################

type
  NonResidue* = object
    ## Non-Residue
    ##
    ## Placeholder for the appropriate quadratic, cubic or sectic non-residue

  CubicExt* = concept x
    ## Cubic Extension field concept
    type BaseField = auto
    x.c0 is BaseField
    x.c1 is BaseField
    x.c2 is BaseField

  QuadraticExt* = concept x
    ## Quadratic Extension field concept
    not(x is CubicExt)

    type BaseField = auto
    x.c0 is BaseField
    x.c1 is BaseField

  ExtensionField* = QuadraticExt or CubicExt

# Initialization
# -------------------------------------------------------------------

func setZero*(a: var ExtensionField) =
  ## Set ``a`` to 0 in the extension field
  for field in fields(a):
    field.setZero()

func setOne*(a: var ExtensionField) =
  ## Set ``a`` to 1 in the extension field
  for fieldName, fA in fieldPairs(a):
    when fieldName == "c0":
      fA.setOne()
    else:
      fA.setZero()

func fromBig*(a: var ExtensionField, src: BigInt) =
  ## Set ``a`` to the bigint value in the extension field
  for fieldName, fA in fieldPairs(a):
    when fieldName == "c0":
      fA.fromBig(src)
    else:
      fA.setZero()

# Comparison
# -------------------------------------------------------------------

func `==`*(a, b: ExtensionField): SecretBool =
  ## Constant-time equality check
  result = CtTrue
  for fA, fB in fields(a, b):
    result = result and (fA == fB)

func isZero*(a: ExtensionField): SecretBool =
  ## Constant-time check if zero
  result = CtTrue
  for fA in fields(a):
    result = result and fA.isZero()

func isOne*(a: ExtensionField): SecretBool =
  ## Constant-time check if one
  result = CtTrue
  for fieldName, fA in fieldPairs(a):
    when fieldName == "c0":
      result = result and fA.isOne()
    else:
      result = result and fA.isZero()

func isMinusOne*(a: ExtensionField): SecretBool =
  ## Constant-time check if -1
  result = CtTrue
  for fieldName, fA in fieldPairs(a):
    when fieldName == "c0":
      result = result and fA.isMinusOne()
    else:
      result = result and fA.isZero()

# Copies
# -------------------------------------------------------------------

func ccopy*(a: var ExtensionField, b: ExtensionField, ctl: SecretBool) =
  ## Constant-time conditional copy
  ## If ctl is true: b is copied into a
  ## if ctl is false: b is not copied and a is unmodified
  ## Time and memory accesses are the same whether a copy occurs or not
  for fA, fB in fields(a, b):
    ccopy(fA, fB, ctl)

# Abelian group
# -------------------------------------------------------------------

func neg*(r: var ExtensionField, a: ExtensionField) =
  ## Field out-of-place negation
  for fR, fA in fields(r, a):
    fR.neg(fA)

func neg*(a: var ExtensionField) =
  ## Field in-place negation
  for fA in fields(a):
    fA.neg()

func `+=`*(a: var ExtensionField, b: ExtensionField) =
  ## Addition in the extension field
  for fA, fB in fields(a, b):
    fA += fB

func `-=`*(a: var ExtensionField, b: ExtensionField) =
  ## Substraction in the extension field
  for fA, fB in fields(a, b):
    fA -= fB

func double*(r: var ExtensionField, a: ExtensionField) =
  ## Field out-of-place doubling
  for fR, fA in fields(r, a):
    fR.double(fA)

func double*(a: var ExtensionField) =
  ## Field in-place doubling
  for fA in fields(a):
    fA.double()

func div2*(a: var ExtensionField) =
  ## Field in-place division by 2
  for fA in fields(a):
    fA.div2()

func sum*(r: var QuadraticExt, a, b: QuadraticExt) =
  ## Sum ``a`` and ``b`` into ``r``
  r.c0.sum(a.c0, b.c0)
  r.c1.sum(a.c1, b.c1)

func sum*(r: var CubicExt, a, b: CubicExt) =
  ## Sum ``a`` and ``b`` into ``r``
  r.c0.sum(a.c0, b.c0)
  r.c1.sum(a.c1, b.c1)
  r.c2.sum(a.c2, b.c2)

func diff*(r: var QuadraticExt, a, b: QuadraticExt) =
  ## Diff ``a`` and ``b`` into ``r``
  r.c0.diff(a.c0, b.c0)
  r.c1.diff(a.c1, b.c1)

func diff*(r: var CubicExt, a, b: CubicExt) =
  ## Diff ``a`` and ``b`` into ``r``
  r.c0.diff(a.c0, b.c0)
  r.c1.diff(a.c1, b.c1)
  r.c2.diff(a.c2, b.c2)

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

# Conditional arithmetic
# -------------------------------------------------------------------

func cneg*(a: var ExtensionField, ctl: SecretBool) =
  ## Constant-time in-place conditional negation
  ## Only negate if ctl is true
  for fA in fields(a):
    fA.cneg(ctl)

func cadd*(a: var ExtensionField, b: ExtensionField, ctl: SecretBool) =
  ## Constant-time in-place conditional addition
  for fA, fB in fields(a, b):
    fA.cadd(fB, ctl)

func csub*(a: var ExtensionField, b: ExtensionField, ctl: SecretBool) =
  ## Constant-time in-place conditional substraction
  for fA, fB in fields(a, b):
    fA.csub(fB, ctl)

# Multiplication by a small integer known at compile-time
# -------------------------------------------------------------------

func `*=`*(a: var ExtensionField, b: static int) =
  ## Multiplication by a small integer known at compile-time

  const negate = b < 0
  const b = if negate: -b
            else: b
  when negate:
    a.neg(a)
  when b == 0:
    a.setZero()
  elif b == 1:
    return
  elif b == 2:
    a.double()
  elif b == 3:
    let t1 = a
    a.double()
    a += t1
  elif b == 4:
    a.double()
    a.double()
  elif b == 5:
    let t1 = a
    a.double()
    a.double()
    a += t1
  elif b == 6:
    a.double()
    let t2 = a
    a.double() # 4
    a += t2
  elif b == 7:
    let t1 = a
    a.double()
    let t2 = a
    a.double() # 4
    a += t2
    a += t1
  elif b == 8:
    a.double()
    a.double()
    a.double()
  elif b == 9:
    let t1 = a
    a.double()
    a.double()
    a.double() # 8
    a += t1
  elif b == 10:
    a.double()
    let t2 = a
    a.double()
    a.double() # 8
    a += t2
  elif b == 11:
    let t1 = a
    a.double()
    let t2 = a
    a.double()
    a.double() # 8
    a += t2
    a += t1
  elif b == 12:
    a.double()
    a.double() # 4
    let t4 = a
    a.double() # 8
    a += t4
  else:
    {.error: "Multiplication by this small int not implemented".}

func prod*(r: var ExtensionField, a: ExtensionField, b: static int) =
  ## Multiplication by a small integer known at compile-time
  const negate = b < 0
  const b = if negate: -b
            else: b
  when negate:
    r.neg(a)
  else:
    r = a
  r *= b

{.pop.} # inline

# ############################################################
#                                                            #
#                Quadratic extensions                        #
#                                                            #
# ############################################################

# Commutative ring implementation for complex quadratic extension fields
# ----------------------------------------------------------------------

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
# ----------------------------------------------------------------------

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
  v1.prod(a.c1, NonResidue)
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

func mul_sparse_generic_by_0y(
       r: var QuadraticExt, a: QuadraticExt,
       sparseB: static int) =
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
  template b(): untyped = sparseB

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
    var t {.noInit.}: typeof(r.c0)
    t.prod(v1, NonResidue)
    v0 -= t               # v0 = a0² - β a1² (the norm / squared magnitude of a)

  # [1 Inv, 2 Sqr, 1 Add]
  v1.inv(v0)              # v1 = 1 / (a0² - β a1²)

  # [1 Inv, 2 Mul, 2 Sqr, 1 Add, 1 Neg]
  r.c0.prod(a.c0, v1)     # r0 = a0 / (a0² - β a1²)
  v0.neg(v1)              # v0 = -1 / (a0² - β a1²)
  r.c1.prod(a.c1, v0)     # r1 = -a1 / (a0² - β a1²)

# Exported quadratic symbols
# -------------------------------------------------------------------

{.push inline.}

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

func mul_sparse_by_0y*(r: var QuadraticExt, a: QuadraticExt, sparseB: static int) =
  ## Sparse multiplication
  mixin fromComplexExtension
  when a.fromComplexExtension():
    {.error: "Not implemented.".}
  else:
    r.mul_sparse_generic_by_0y(a, sparseB)

func mul_sparse_by_0y*(a: var QuadraticExt, sparseB: auto) =
  ## Sparse in-place multiplication
  a.mul_sparse_by_0y(a, sparseB)

func mul_sparse_by_x0*(a: var QuadraticExt, sparseB: QuadraticExt) =
  ## Sparse in-place multiplication
  a.mul_sparse_generic_by_x0(a, sparseB)

{.pop.} # inline

# ############################################################
#                                                            #
#                    Cubic extensions                        #
#                                                            #
# ############################################################

# Commutative ring implementation for Cubic Extension Fields
# -------------------------------------------------------------------
# Cubic extensions can use specific squaring procedures
# beyond Schoolbook and Karatsuba:
# - Chung-Hasan (3 different algorithms)
# - Toom-Cook-3x
#
# Chung-Hasan papers
# http://cacr.uwaterloo.ca/techreports/2006/cacr2006-24.pdf
# https://www.lirmm.fr/arith18/papers/Chung-Squaring.pdf
#
# The papers focus on polynomial squaring, they have been adapted
# to towered extension fields with the relevant costs in
#
# - Multiplication and Squaring on Pairing-Friendly Fields
#   Augusto Jun Devegili and Colm Ó hÉigeartaigh and Michael Scott and Ricardo Dahab, 2006
#   https://eprint.iacr.org/2006/471
#
# Costs in the underlying field
# M: Mul, S: Square, A: Add/Sub, B: Mul by non-residue
#
# | Method      | > Linear | Linear            |
# |-------------|----------|-------------------|
# | Schoolbook  | 3M + 3S  | 6A + 2B           |
# | Karatsuba   | 6S       | 13A + 2B          |
# | Tom-Cook-3x | 5S       | 33A + 2B          |
# | CH-SQR1     | 3M + 2S  | 11A + 2B          |
# | CH-SQR2     | 2M + 3S  | 10A + 2B          |
# | CH-SQR3     | 1M + 4S  | 11A + 2B + 1 Div2 |
# | CH-SQR3x    | 1M + 4S  | 14A + 2B          |

func square_Chung_Hasan_SQR2(r: var CubicExt, a: CubicExt) {.used.}=
  ## Returns r = a²
  mixin prod, square, sum
  var s0{.noInit.}, m01{.noInit.}, m12{.noInit.}: typeof(r.c0)

  # precomputations that use a
  m01.prod(a.c0, a.c1)
  m01.double()
  m12.prod(a.c1, a.c2)
  m12.double()
  s0.square(a.c2)
  # aliasing: a₂ unused

  # r₂ = (a₀ - a₁ + a₂)²
  r.c2.sum(a.c2, a.c0)
  r.c2 -= a.c1
  r.c2.square()
  # aliasing, a almost unneeded now

  # r₂ = (a₀ - a₁ + a₂)² + 2a₀a₁ + 2a₁a₂ - a₂²
  r.c2 += m01
  r.c2 += m12
  r.c2 -= s0

  # r₁ = 2a₀a₁ + β a₂²
  r.c1.prod(s0, NonResidue)
  r.c1 += m01

  # r₂ = (a₀ - a₁ + a₂)² + 2a₀a₁ + 2a₁a₂ - a₀² - a₂²
  s0.square(a.c0)
  r.c2 -= s0

  # r₀ = a₀² + β 2a₁a₂
  r.c0.prod(m12, NonResidue)
  r.c0 += s0

func square_Chung_Hasan_SQR3(r: var CubicExt, a: CubicExt) =
  ## Returns r = a²
  mixin prod, square, sum
  var s0{.noInit.}, t{.noInit.}, m12{.noInit.}: typeof(r.c0)

  # s₀ = (a₀ + a₁ + a₂)²
  # t = ((a₀ + a₁ + a₂)² + (a₀ - a₁ + a₂)²) / 2
  s0.sum(a.c0, a.c2)
  t.diff(s0, a.c1)
  s0 += a.c1
  s0.square()
  t.square()
  t += s0
  t.div2()

  # m12 = 2a₁a₂ and r₁ = a₂²
  # then a₁ and a₂ are unused for aliasing
  m12.prod(a.c1, a.c2)
  m12.double()
  r.c1.square(a.c2)       # r₁ = a₂²

  r.c2.diff(t, r.c1)      # r₂ = t - a₂²
  r.c1 *= NonResidue      # r₁ = β a₂²
  r.c1 += s0              # r₁ = (a₀ + a₁ + a₂)² + β a₂²
  r.c1 -= m12             # r₁ = (a₀ + a₁ + a₂)² - 2a₁a₂ + β a₂²
  r.c1 -= t               # r₁ = (a₀ + a₁ + a₂)² - 2a₁a₂ - t + β a₂²

  s0.square(a.c0)
  # aliasing: a₀ unused

  r.c2 -= s0
  r.c0.prod(m12, NonResidue)
  r.c0 += s0

func square*(r: var CubicExt, a: CubicExt) {.inline.} =
  ## Returns r = a²
  square_Chung_Hasan_SQR3(r, a)

func prod*(r: var CubicExt, a, b: CubicExt) =
  ## Returns r = a * b  # Algorithm is Karatsuba
  var v0{.noInit.}, v1{.noInit.}, v2{.noInit.}: typeof(r.c0)
  var t0{.noInit.}, t1{.noInit.}, t2{.noInit.}: typeof(r.c0)

  v0.prod(a.c0, b.c0)
  v1.prod(a.c1, b.c1)
  v2.prod(a.c2, b.c2)

  # r₀ = β ((a₁ + a₂)(b₁ + b₂) - v₁ - v₂) + v₀
  t0.sum(a.c1, a.c2)
  t1.sum(b.c1, b.c2)
  t0 *= t1
  t0 -= v1
  t0 -= v2
  t0 *= NonResidue
  # r₀ = t₀ + v₀ at the end to handle aliasing

  # r₁ = (a₀ + a₁) * (b₀ + b₁) - v₀ - v₁ + β v₂
  t1.sum(a.c0, a.c1)
  t2.sum(b.c0, b.c1)
  r.c1.prod(t1, t2)
  r.c1 -= v0
  r.c1 -= v1
  t1.prod(v2, NonResidue)
  r.c1 += t1

  # r₂ = (a₀ + a₂) * (b₀ + b₂) - v₀ - v₂ + v₁
  t1.sum(a.c0, a.c2)
  t2.sum(b.c0, b.c2)
  r.c2.prod(t1, t2)
  r.c2 -= v0
  r.c2 -= v2
  r.c2 += v1

  # Finish r₀
  r.c0.sum(t0, v0)

func inv*(r: var CubicExt, a: CubicExt) =
  ## Compute the multiplicative inverse of ``a``
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  #
  # Algorithm 5.23
  #
  # Arithmetic of Finite Fields
  # Chapter 5 of Guide to Pairing-Based Cryptography
  # Jean Luc Beuchat, Luis J. Dominguez Perez, Sylvain Duquesne, Nadia El Mrabet, Laura Fuentes-Castañeda, Francisco Rodríguez-Henríquez, 2017\
  # https://www.researchgate.net/publication/319538235_Arithmetic_of_Finite_Fields
  #
  # We optimize for stack usage and use 4 temporaries (+r as temporary)
  # instead of 9, because 5 * 2 (𝔽p2) * Bitsize would be:
  # - ~2540 bits for BN254
  # - ~3810 bits for BLS12-381
  var v1 {.noInit.}, v2 {.noInit.}, v3 {.noInit.}: typeof(r.c0)

  # A in r0
  # A <- a0² - β a1 a2
  r.c0.square(a.c0)
  v1.prod(a.c1, a.c2)
  v1 *= NonResidue
  r.c0 -= v1

  # B in v1
  # B <- β a2² - a0 a1
  v1.square(a.c2)
  v1 *= NonResidue
  v2.prod(a.c0, a.c1)
  v1 -= v2

  # C in v2
  # C <- a1² - a0 a2
  v2.square(a.c1)
  v3.prod(a.c0, a.c2)
  v2 -= v3

  # F in v3
  # F <- β a1 C + a0 A + β a2 B
  v3.prod(a.c2, NonResidue)
  r.c1.prod(v1, v3)
  v3.prod(a.c1, NonResidue)
  r.c2.prod(v2, v3)
  v3.prod(r.c0, a.c0)
  v3 += r.c1
  v3 += r.c2

  let t = v3 # TODO, support aliasing in all primitives
  v3.inv(t)

  # (a0 + a1 v + a2 v²)^-1 = (A + B v + C v²) / F
  r.c0 *= v3
  r.c1.prod(v1, v3)
  r.c2.prod(v2, v3)

# Exported cubic symbols
# -------------------------------------------------------------------
{.push inline.}

func inv*(a: var CubicExt) =
  ## Compute the multiplicative inverse of ``a``
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  let t = a
  a.inv(t)

func `*=`*(a: var CubicExt, b: CubicExt) =
  ## In-place multiplication
  a.prod(a, b)

func conj*(a: var CubicExt) =
  ## Computes the conjugate in-place
  mixin conj, conjneg
  a.c0.conj()
  a.c1.conjneg()
  a.c2.conj()

func conj*(r: var CubicExt, a: CubicExt) =
  ## Computes the conjugate out-of-place
  mixin conj, conjneg
  r.c0.conj(a.c0)
  r.c1.conjneg(a.c1)
  r.c2.conj(a.c2)

func square*(a: var CubicExt) =
  ## In-place squaring
  a.square(a)

{.pop.} # inline
{.pop.} # raises no exceptions
