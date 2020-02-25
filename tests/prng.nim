# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../constantine/arithmetic/bigints_checked,
  ../constantine/config/[common, curves]

# ############################################################
#
#              Pseudo-Random Number Generator
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

# ############################################################
#
#            Create a random BigInt or Field element
#
# ############################################################

func random[T](rng: var RngState, a: var T, C: static Curve) {.noInit.}=
  ## Recursively initialize a BigInt or Field element
  when T is BigInt:
    var unreduced{.noInit.}: T

    unreduced.setInternalBitLength()
    for i in 0 ..< unreduced.limbs.len:
      unreduced.limbs[i] = Word(rng.next())

    # Note: a simple modulo will be biaised but it's simple and "fast"
    a.reduce(unreduced, C.Mod.mres)

  else:
    for field in fields(a):
      rng.random(field, C)

func random*(rng: var RngState, T: typedesc): T =
  ## Create a random Field or Extension FIeld Element
  rng.random(result, T.C)
