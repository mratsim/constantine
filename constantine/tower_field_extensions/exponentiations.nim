# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.


import
  ../arithmetic,
  ../config/[common, curves],
  ./tower_common,
  ./quadratic_extensions,
  ./cubic_extensions

# ############################################################
#
#  Exponentiations (pow and square roots) in extension fields
#
# ############################################################

# Square root should be implemented in constant-time for hash-to-curve:
# https://tools.ietf.org/html/draft-irtf-cfrg-hash-to-curve-05#section-4
#
# Further non-constant-time optimization may be used
# - Square Root Computation over Even Extension Fields
#   Gora Adj,  Francisco Rodríguez-Henríquez, 2012
#   https://eprint.iacr.org/2012/685

# No exceptions allowed
{.push raises: [].}

# Pow
# -----------------------------------------------------------

template checkPowScratchSpaceLen(len: int) =
  ## Checks that there is a minimum of scratchspace to hold the temporaries
  debug:
    assert len >= 2, "Internal Error: the scratchspace for powmod should be equal or greater than 2"

func getWindowLen(bufLen: int): uint =
  ## Compute the maximum window size that fits in the scratchspace buffer
  checkPowScratchSpaceLen(bufLen)
  result = 4
  while (1 shl result) + 1 > bufLen:
    dec result

func powPrologue[F](a: var F, scratchspace: var openarray[F]): uint =
  ## Setup the scratchspace, then set a to 1.
  ## Returns the fixed-window size for exponentiation with window optimization
  result = scratchspace.len.getWindowLen
  # Precompute window content, special case for window = 1
  # (i.e scratchspace has only space for 2 temporaries)
  # The content scratchspace[2+k] is set at [k]P
  # with scratchspace[0] untouched
  if result == 1:
    scratchspace[1] = a
  else:
    scratchspace[2] = a
    for k in 2 ..< 1 shl result:
      scratchspace[k+1]
  a.setOne()

func powSquarings[F](
       a: var F,
       exponent: openArray[byte],
       tmp: var F,
       window: uint,
       acc, acc_len: var uint,
       e: var uint
     ): tuple[k, bits: uint] {.inline.}=
  ## Squaring step of exponentiation by squaring
  ## Get the next k bits in range [1, window)
  ## Square k times
  ## Returns the number of squarings done and the corresponding bits
  ##
  ## Updates iteration variables and accumulators
  # Due to the high number of parameters,
  # forcing this inline actually reduces the code size
  #
  # ⚠️: Extreme care should be used to not leak
  #    the exponent bits nor its real bitlength
  #    i.e. if the exponent is zero but encoded in a
  #    256-bit integer, only "256" should leak
  #    as for some application like RSA
  #    the exponent might be the user secret key.

  # Get the next bits
  # acc/acc_len must be uint to avoid Nim runtime checks leaking bits
  # acc/acc_len must be uint to avoid Nim runtime checks leaking bits
  # e is public
  var k = window
  if acc_len < window:
    if e < exponent.len:
      acc = (acc shl 8) or exponent[e].uint
      inc e
      acc_len += 8
    else: # Drained all exponent bits
      k = acc_len

  let bits = (acc shr (acc_len - k)) and ((1'u32 shl k) - 1)
  acc_len -= k

  # We have k bits and can do k squaring
  for i in 0 ..< k:
    a.square()

  return (k, bits)

func powUnsafeExponent(
       a: var ExtensionField,
       exponent: openArray[byte],
       scratchspace: var openArray[byte]
     ) =
  ## Extension field exponentiation r = a^exponent (mod p^m)
  ##
  ## Warning ⚠️ :
  ## This is an optimization for public exponent
  ## Otherwise bits of the exponent can be retrieved with:
  ## - memory access analysis
  ## - power analysis
  ## - timing analysis

  # TODO: scratchspace[1] is unused when window > 1
  let window = powPrologue(a, scratchspace)

  var
    acc, acc_len: uint
    e = 0
  while acc_len > 0 or e < exponent.len:
    let (k, bits) = powSquarings(
      a, exponent,
      scratchspace[0], window,
      acc, acc_len, e
    )

    ## Warning ⚠️: Exposes the exponent bits
    if bits != 0:
      if window > 1:
        scratchspace[0].prod(a, scratchspace[1+bits])
      else:
        # scratchspace[1] holds the original `a`
        scratchspace[0].prod(a, scratchspace[1])
      a = scratchspace[0]

# Square root
# -----------------------------------------------------------
#
# Warning ⚠️:
#   p the characteristic, i.e. the prime modulus of the base field
#   in extension field we require q = p^m be of special form
#   i.e. q ≡ 3 (mod 4) or q ≡ 9 (mod 16)
#
#   In Fp2 in particular p² ≡ 1 (mod 4) always hold
#   and p² ≡ 5 (mod 8) is not possible

func isSquare*(a: QuadraticExt): SecretBool =
  ## Returns true if ``a`` is a square (quadratic residue) in 𝔽p2
  ##
  ## Assumes that the prime modulus ``p`` is public.
  # Implementation:
  #
  # (a0, a1) = a in F(p^2)
  # is_square(a) = is_square(|a|) over F(p)
  # where |a| = a0^2 + a1^2
  #
  # This can be done recursively in an extension tower
  #
  # https://tools.ietf.org/html/draft-irtf-cfrg-hash-to-curve-08#appendix-G.5
  # https://eprint.iacr.org/2012/685

  mixin fromComplexExtension # TODO: relax this
  static: doAssert a.fromComplexExtension()

  var tv1{.noInit.}, tv2{.noInit.}: typeof(a.c0)

  tv1.square(a.c0) #     a0²
  tv2.square(a.c1) # - β a1² with β = 𝑖² in a complex extension field

  tv1 += tv2       # a0 - (-1) a1²
  result = tv1.isSquare()

func sqrt_if_square*(a: var QuadraticExt): SecretBool =
  ## If ``a`` is a square, compute the square root of ``a``
  ## if not, ``a`` is unmodified.
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  #
  # Implementation via the complex method (which confusingly does not require a complex field)
  # We make it constant-time via conditional copies

  mixin fromComplexExtension # TODO: relax this
  static: doAssert a.fromComplexExtension()

  var t1{.noInit.}, t2{.noInit.}, t3{.noInit.}: typeof(a.c0)

  t1.square(a.c0) #     a0²
  t2.square(a.c1) # - β a1² with β = 𝑖² in a complex extension field

  t1 += t2        # a0 - (-1) a1²
  result = t1.sqrt_if_square_p3mod4()

  t2.sum(a.c0, t1)
  t2.div2()

  t3.diff(a.c0, t1)
  t3.div2()

  let quadResidTest = t2.isSquare()
  t2.ccopy(t3, not quadResidTest)

  t2.sqrt_p3mod4()
  a.c0.ccopy(t2, result)

  t2.double()
  t1.inv(t2)
  t1 *= a.c1
  a.c1.ccopy(t1, result)
