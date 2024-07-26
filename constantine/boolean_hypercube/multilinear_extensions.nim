# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/[abstractions, allocs]

# Resources:
# - https://people.cs.georgetown.edu/jthaler/IPsandextensions.pdf
# - https://people.cs.georgetown.edu/jthaler/ProofsArgsAndZK.pdf
#   Chapter 3.5

type
  MultilinearExtension*[F] = object
    ## Note: to follow mathematical description, indices start at 1 and end of range is inclusive
    ##       actual implementation will have indices start at 0
    ##
    ## Given a sequence of bits of size s {0,1}ˢ
    ## and an arbitrary function f: {0,1}ˢ -> 𝔽
    ## i.e. that maps a sequence of bits to a finite field 𝔽
    ##
    ## there is an unique multilinear polynomial f̃
    ## called multilinear extension of f
    ## that satisfies f̃(xᵢ) = f(xᵢ) for xᵢ ∈ {0,1}ˢ
    ##
    ## f̃(x₁, ...,xₛ) = ∑ₑ f(e) 𝛘ₑ(x₁, ...,xₛ)
    ## with e ∈ {0,1}ˢ and f(e) the evaluation of f at e.
    ##
    ## 𝛘ₑ(x₁, ...,xₛ) is the multilinear Lagrange basis polynomial
    ## which takes value 1 at 𝛘ₑ(e) and 0 at Xₑ(e̅) e̅ any other element ∈ {0,1}ˢ
    ##
    ## 𝛘ₑ(x₁, ...,xₛ) = ∏ᵢ₌₁ˢ(xᵢeᵢ + (1-xᵢ)(1-eᵢ)), i ∈ [1, s]
    ##
    ## A multilinear polynomial is linear (i.e. degree at most 1) in each
    ## of its variables.
    num_vars*: int
    base_poly_evals*: ptr UncheckedArray[F]

proc `=copy`*[F](dst: var MultilinearExtension[F], src: MultilinearExtension[F]) {.error: "A multilinear extension cannot be copied".}

proc `=wasMoved`*[F](mle: var MultilinearExtension[F]) =
  mle.base_poly_evals = nil

proc `=destroy`*[F](mle: var MultilinearExtension[F]) =
  if not mle.base_poly_evals.isNil:
    freeHeapAligned(mle.base_poly_evals)

func new*[F](T: type MultilinearExtension[F], num_vars: int, poly_evals: openArray[F]): T =
  debug:
    doAssert 1 shl num_vars == poly_evals.len, block:
      "The MLE has " & $num_vars " variables\n" &
      "but the poly it's derived from has " & $poly_evals.len & " evaluations.\n" &
      "2^" & $num_vars & " = " & $(1 shl num_vars) & " were expected instead."
  result.num_vars = num_vars
  let L = 1 shl num_vars
  result.base_poly_evals = allocHeapArrayAligned(F, L, alignment = 64)
  for i in 0 ..< L:
    result.base_poly_evals[i] = poly_evals[i]

# Big-endian Multilinear Lagrange Basis
# ------------------------------------------------------------------------------------

iterator bits_be(n: SomeInteger, len: int): (int, bool) =
  for i in 0 ..< len:
    yield (i, bool((n shr (len-1-i)) and 1))

func evalMultilinearExtensionAt_BE_reference[F](
      r: var F,
      mle: MultilinearExtension[F],
      xs: openArray[F]) =
  ## Compute
  ##   f̃(x₁, ...,xₛ) = ∑ₑ f(e) ∏ᵢ(xᵢeᵢ + (1-xᵢ)(1-eᵢ))
  ##   at supplied (x₁, ...,xₛ)
  ## e is interpreted as a big-endian bitstring
  ##
  ## This is a reference implementation using naive computation
  ## in O(n log n) with n being the number of evaluations of the original polynomial.
  debug: doAssert mle.num_vars == coords.len

  let L = 1 shl mle.num_vars

  r.setZero()
  for e in 0 ..< L:
    # 𝛘ₑ(x₁, ...,xₛ) = ∏ᵢ(xᵢeᵢ + (1-xᵢ)(1-eᵢ))
    # e ∈ {0,1}ˢ hence each factor is either:
    # (1-xᵢ) or xᵢ
    var chi_e {.noInit.}: F
    chi_e.setOne()

    for (i, ei) in bits_be(e, mle.num_vars):
      if ei:
        chi_e *= xs[i]
      else:
        var t {.noInit.}: F
        t.diff(F.getOne(), xs[i])
        chi_e *= t

    var t {.noInit.}: F
    t.prod(mle.base_poly_evals[e], chi_e)
    r += t

func evalMultilinearExtensionAt_BE[F](
      r: var F,
      mle: MultilinearExtension[F],
      xs: openArray[F]) =
  ## Compute
  ##   f̃(x₁, ...,xₛ) = ∑ₑ f(e) ∏ᵢ(xᵢeᵢ + (1-xᵢ)(1-eᵢ))
  ##   at supplied (x₁, ...,xₛ)
  ## e is interpreted as a big-endian bitstring
  ##
  ## This is an optimized implementation that
  ##
  ## evaluates 𝛘ₑ(x₁, ...,xₛ) = ∏ᵢ(xᵢeᵢ + (1-xᵢ)(1-eᵢ))
  ## in O(n)
  #
  # e ∈ {0,1}ˢ hence each factor is either:
  # (1-xᵢ) or xᵢ
  #
  # See the algorithm in split_scalars to build
  # a binary lookup table for O(n) evaluations
  #
  # Algorithm:
  # for u in 0 ..< 2ˢ
  #   lagrange[u] = 1
  #   iterate on the bit representation of u
  #     if the bit is set, multiply by matching xᵤ
  #     if not, multiply by (1-xᵤ)
  #
  # Implementation:
  #   We optimize the basic algorithm to reuse already computed table entries
  #   by noticing for example that:
  #   - 6 represented as 0b110 requires     x₂.x₁(1-x₀)
  #   - 2 represented as 0b010 requires (1-x₂).x₁(1-x₀)

  let L = 1 shl mle.num_vars
  let buf = allocHeapArrayAligned(F, L, alignment = 64)
  for i in 0 ..< L:
    buf[i] = mle.base_poly_evals[i]

  # number of operations:
  # ∑ᵢ₌₀ˡᵒᵍ²⁽ˢ⁾⁻¹ 2ˡᵒᵍ²⁽ˢ⁾⁻¹⁻ⁱ = 2ˡᵒᵍ²⁽ˢ⁾-1 = s-1
  # Using sum of consecutive powers of 2 formula
  # So we're linear in the original polynomial size
  for i in countdown(xs.len-1, 0):
    for e in 0 ..< 1 shl i:
      # Implicit binary tree representation with root at 1
      #                  root at 1
      # Left child        e*2 + 0
      # Right child       e*2 + 1
      # Parent            e/2
      #
      # Representation
      #
      #  depth 0          ------ 1 ------
      #  depth 1      -- 2 --       --- 3 ---
      #  depth 2      4     5       6       7
      #  depth 3    8  9  10 11  12  13  14  15
      #
      # In an array, storage is linear
      template left(): untyped = buf[e shl 1]
      template right(): untyped = buf[(e shl 1) + 1]

      var t {.noInit.}: F
      t.diff(right, left)
      t *= xs[i]
      buf[e].sum(left, t)

  r = buf[0]
  freeHeapAligned(buf)

# Little-endian Multilinear Lagrange Basis
# ------------------------------------------------------------------------------------

iterator bits_le(n: SomeInteger, len: int): (int, bool) =
  for i in 0 ..< len:
    yield (i, bool((n shr i) and 1))

func evalMultilinearExtensionAt_LE_reference[F](
      r: var F,
      mle: MultilinearExtension[F],
      xs: openArray[F]) =
  ## Compute
  ##   f̃(x₁, ...,xₛ) = ∑ₑ f(e) ∏ᵢ(xᵢeᵢ + (1-xᵢ)(1-eᵢ))
  ##   at supplied (x₁, ...,xₛ)
  ## e is interpreted as a little-endian bitstring
  ##
  ## This is a reference implementation using naive computation
  ## in O(n log n) with n being the number of evaluations of the original polynomial.
  debug: doAssert mle.num_vars == coords.len

  let L = 1 shl mle.num_vars

  r.setZero()
  for e in 0 ..< L:
    # 𝛘ₑ(x₁, ...,xₛ) = ∏ᵢ(xᵢeᵢ + (1-xᵢ)(1-eᵢ))
    # e ∈ {0,1}ˢ hence each factor is either:
    # (1-xᵢ) or xᵢ
    var chi_e {.noInit.}: F
    chi_e.setOne()

    for (i, ei) in bits_le(e, mle.num_vars):
      if ei:
        chi_e *= xs[i]
      else:
        var t {.noInit.}: F
        t.diff(F.getOne(), xs[i])
        chi_e *= t

    var t {.noInit.}: F
    t.prod(mle.base_poly_evals[e], chi_e)
    r += t

func evalMultilinearExtensionAt_LE[F](
      r: var F,
      mle: MultilinearExtension[F],
      xs: openArray[F]) =
  ## Compute
  ##   f̃(x₁, ...,xₛ) = ∑ₑ f(e) ∏ᵢ(xᵢeᵢ + (1-xᵢ)(1-eᵢ))
  ##   at supplied (x₁, ...,xₛ)
  ## e is interpreted as a little-endian bitstring
  ##
  ## This is an optimized implementation that
  ##
  ## evaluates 𝛘ₑ(x₁, ...,xₛ) = ∏ᵢ(xᵢeᵢ + (1-xᵢ)(1-eᵢ))
  ## in O(n)
  #
  # e ∈ {0,1}ˢ hence each factor is either:
  # (1-xᵢ) or xᵢ
  #
  # See the algorithm in split_scalars to build
  # a binary lookup table for O(n) evaluations
  #
  # Algorithm:
  # for u in 0 ..< 2ˢ
  #   lagrange[u] = 1
  #   iterate on the bit representation of u
  #     if the bit is set, multiply by matching xᵤ
  #     if not, multiply by (1-xᵤ)
  #
  # Implementation:
  #   We optimize the basic algorithm to reuse already computed table entries
  #   by noticing for example that:
  #   - 6 represented as 0b110 requires     x₂.x₁(1-x₀)
  #   - 2 represented as 0b010 requires (1-x₂).x₁(1-x₀)

  let L = 1 shl mle.num_vars
  let buf = allocHeapArrayAligned(F, L, alignment = 64)
  for i in 0 ..< L:
    buf[i] = mle.base_poly_evals[i]

  # number of operations:
  # ∑ᵢ₌₀ˡᵒᵍ²⁽ˢ⁾⁻¹ 2ˡᵒᵍ²⁽ˢ⁾⁻¹⁻ⁱ = 2ˡᵒᵍ²⁽ˢ⁾-1 = s-1
  # Using sum of consecutive powers of 2 formula
  # So we're linear in the original polynomial size
  for i in 0 ..< xs.len:
    for e in 0 ..< 1 shl (mle.num_vars - 1 - i):
      # Implicit binary tree representation with root at 1
      #                  root at 1
      # Left child        e*2 + 0
      # Right child       e*2 + 1
      # Parent            e/2
      #
      # Representation
      #
      #  depth 0          ------ 1 ------
      #  depth 1      -- 2 --       --- 3 ---
      #  depth 2      4     5       6       7
      #  depth 3    8  9  10 11  12  13  14  15
      #
      # In an array, storage is linear
      template left(): untyped = buf[e shl 1]
      template right(): untyped = buf[(e shl 1) + 1]

      var t {.noInit.}: F
      t.diff(right, left)
      t *= xs[i]
      buf[e].sum(left, t)

  r = buf[0]
  freeHeapAligned(buf)

# Public API
# ------------------------------------------------------------------------------------

func evalMultilinearExtensionAt_reference*[F](
      r: var F,
      mle: MultilinearExtension[F],
      xs: openArray[F],
      endian: static Endianness = bigEndian) {.inline.} =
  ## Compute
  ##   f̃(x₁, ...,xₛ) = ∑ₑ f(e) ∏ᵢ(xᵢeᵢ + (1-xᵢ)(1-eᵢ))
  ##   at supplied (x₁, ...,xₛ)
  ## By default, e is interpreted as a big-endian bitstring
  ##
  ## This is a reference implementation using naive computation
  ## in O(n log n) with n being the number of evaluations of the original polynomial.
  when endian == bigEndian:
    evalMultilinearExtensionAt_BE_reference(r, mle, xs)
  else:
    evalMultilinearExtensionAt_LE_reference(r, mle, xs)

func evalMultilinearExtensionAt*[F](
      r: var F,
      mle: MultilinearExtension[F],
      xs: openArray[F],
      endian: static Endianness = bigEndian) {.inline.} =
  ## Compute
  ##   f̃(x₁, ...,xₛ) = ∑ₑ f(e) ∏ᵢ(xᵢeᵢ + (1-xᵢ)(1-eᵢ))
  ##   at supplied (x₁, ...,xₛ)
  ## By default, e is interpreted as a little-endian bitstring
  ##
  ## This is an optimized implementation that
  ##
  ## evaluates 𝛘ₑ(x₁, ...,xₛ) = ∏ᵢ(xᵢeᵢ + (1-xᵢ)(1-eᵢ))
  ## in O(n)
  when endian == bigEndian:
    evalMultilinearExtensionAt_BE(r, mle, xs)
  else:
    evalMultilinearExtensionAt_LE(r, mle, xs)
