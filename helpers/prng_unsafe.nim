# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../constantine/arithmetic/bigints,
  ../constantine/config/[common, curves],
  ../constantine/elliptic/[ec_weierstrass_affine, ec_weierstrass_projective]

# ############################################################
#
#              Pseudo-Random Number Generator
#       Unsafe: for testing and benchmarking purposes
#
# ############################################################
#
# Our field elements for elliptic curve cryptography
# are in the 2^256~2^512 range.
# For pairings, with embedding degrees of 12 to 48
# We would need 12~48 field elements per point on the curve
#
# The recommendation by Vigna at http://prng.di.unimi.it
# is to have a period of t^2 if we need t values (i.e. about 2^1024)
# but also that for all practical purposes 2^256 period is enough
#
# We use 2^512 to cover the range the base field elements

type RngState* = object
  ## This is the state of a Xoshiro512** PRNG
  ## Unsafe: for testing and benchmarking purposes only
  s: array[8, uint64]

func splitMix64(state: var uint64): uint64 =
  state += 0x9e3779b97f4a7c15'u64
  result = state
  result = (result xor (result shr 30)) * 0xbf58476d1ce4e5b9'u64
  result = (result xor (result shr 27)) * 0xbf58476d1ce4e5b9'u64
  result = result xor (result shr 31)

func seed*(rng: var RngState, x: SomeInteger) =
  ## Seed the random number generator with a fixed seed
  var sm64 = uint64(x)
  rng.s[0] = splitMix64(sm64)
  rng.s[1] = splitMix64(sm64)
  rng.s[2] = splitMix64(sm64)
  rng.s[3] = splitMix64(sm64)
  rng.s[4] = splitMix64(sm64)
  rng.s[5] = splitMix64(sm64)
  rng.s[6] = splitMix64(sm64)
  rng.s[7] = splitMix64(sm64)

func rotl(x: uint64, k: static int): uint64 {.inline.} =
  return (x shl k) or (x shr (64 - k))

template `^=`(x: var uint64, y: uint64) =
  x = x xor y

func next(rng: var RngState): uint64 =
  ## Compute a random uint64 from the input state
  ## using xoshiro512** algorithm by Vigna et al
  ## State is updated.
  result = rotl(rng.s[1] * 5, 7) * 9

  let t = rng.s[1] shl 11
  rng.s[2] ^= rng.s[0];
  rng.s[5] ^= rng.s[1];
  rng.s[1] ^= rng.s[2];
  rng.s[7] ^= rng.s[3];
  rng.s[3] ^= rng.s[4];
  rng.s[4] ^= rng.s[5];
  rng.s[0] ^= rng.s[6];
  rng.s[6] ^= rng.s[7];

  rng.s[6] ^= t;

  rng.s[7] = rotl(rng.s[7], 21);

# BigInts and Fields
# ------------------------------------------------------------

func random_unsafe[T](rng: var RngState, a: var T, C: static Curve) {.noInit.}=
  ## Recursively initialize a BigInt or Field element
  ## Unsafe: for testing and benchmarking purposes only
  when T is BigInt:
    var reduced, unreduced{.noInit.}: T

    for i in 0 ..< unreduced.limbs.len:
      unreduced.limbs[i] = Word(rng.next())

    # Note: a simple modulo will be biaised but it's simple and "fast"
    reduced.reduce(unreduced, C.Mod)
    a.montyResidue(reduced, C.Mod, C.getR2modP(), C.getNegInvModWord(), C.canUseNoCarryMontyMul())

  else:
    for field in fields(a):
      rng.random_unsafe(field, C)

# Elliptic curves
# ------------------------------------------------------------

func random_unsafe[F](rng: var RngState, a: var ECP_SWei_Proj[F]) =
  ## Initialize a random curve point with Z coordinate == 1
  ## Unsafe: for testing and benchmarking purposes only
  var fieldElem {.noInit.}: F
  var success = CtFalse

  while not bool(success):
    # Euler's criterion: there are (p-1)/2 squares in a field with modulus `p`
    #                    so we have a probability of ~0.5 to get a good point
    rng.random_unsafe(fieldElem, F.C)
    success = trySetFromCoordX(a, fieldElem)

func random_unsafe_with_randZ[F](rng: var RngState, a: var ECP_SWei_Proj[F]) =
  ## Initialize a random curve point with Z coordinate being random
  ## Unsafe: for testing and benchmarking purposes only
  var Z{.noInit.}: F
  rng.random_unsafe(Z, F.C) # If Z is zero, X will be zero and that will be an infinity point

  var fieldElem {.noInit.}: F
  var success = CtFalse

  while not bool(success):
    rng.random_unsafe(fieldElem, F.C)
    success = trySetFromCoordsXandZ(a, fieldElem, Z)

# Integer ranges
# ------------------------------------------------------------

func random_unsafe(rng: var RngState, maxExclusive: uint32): uint32 =
  ## Generate a random integer in 0 ..< maxExclusive
  ## Uses an unbiaised generation method
  ## See Lemire's algorithm modified by Melissa O'Neill
  ##   https://www.pcg-random.org/posts/bounded-rands.html
  let max = maxExclusive
  var x = uint32 rng.next()
  var m = x.uint64 * max.uint64
  var l = uint32 m
  if l < max:
    var t = not(max) + 1 # -max
    if t >= max:
      t -= max
      if t >= max:
        t = t mod max
    while l < t:
      x = uint32 rng.next()
      m = x.uint64 * max.uint64
      l = uint32 m
  return uint32(m shr 32)

# Generic over any supported type
# ------------------------------------------------------------

func random_unsafe*[T: SomeInteger](rng: var RngState, inclRange: Slice[T]): T =
  ## Return a random integer in the given range.
  ## The range bounds must fit in an int32.
  let maxExclusive = inclRange.b + 1 - inclRange.a
  result = T(rng.random_unsafe(uint32 maxExclusive))
  result += inclRange.a

func random_unsafe*(rng: var RngState, T: typedesc): T =
  ## Create a random Field or Extension Field or Curve Element
  ## Unsafe: for testing and benchmarking purposes only
  when T is ECP_SWei_Proj:
    rng.random_unsafe(result)
  else:
    rng.random_unsafe(result, T.C)

func random_unsafe_with_randZ*(rng: var RngState, T: typedesc[ECP_SWei_Proj]): T =
  ## Create a random curve element with a random Z coordinate
  ## Unsafe: for testing and benchmarking purposes only
  rng.random_unsafe_with_randZ(result)

# Sanity checks
# ------------------------------------------------------------

when isMainModule:
  import std/[tables, times]

  var rng: RngState
  let timeSeed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  rng.seed(timeSeed)
  echo "prng_sanity_checks xoshiro512** seed: ", timeSeed


  proc test[T](s: Slice[T]) =
    var c = initCountTable[int]()

    for _ in 0 ..< 1_000_000:
      c.inc(rng.random_unsafe(s))

    echo "1'000'000 pseudo-random outputs from ", s.a, " to ", s.b, " (incl): ", c

  test(0..1)
  test(0..2)
  test(1..52)
  test(-10..10)
