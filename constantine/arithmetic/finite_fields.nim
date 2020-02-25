# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#    Fp: Finite Field arithmetic with prime field modulus P
#
# ############################################################

# Constraints:
# - We assume that p is known at compile-time
# - We assume that p is not even:
#   - Operations are done in the Montgomery domain
#   - The Montgomery domain introduce a Montgomery constant that must be coprime
#     with the field modulus.
#   - The constant is chosen a power of 2
#   => to be coprime with a power of 2, p must be odd
# - We assume that p is a prime
#   - Modular inversion uses the Fermat's little theorem
#     which requires a prime

import
  ../primitives/constant_time,
  ../config/[common, curves],
  ./bigints_checked

from ../io/io_bigints import exportRawUint # for "pow"

# type
#   `Fp`*[C: static Curve] = object
#     ## All operations on a field are modulo P
#     ## P being the prime modulus of the Curve C
#     ## Internally, data is stored in Montgomery n-residue form
#     ## with the magic constant chosen for convenient division (a power of 2 depending on P bitsize)
#     mres*: matchingBigInt(C)
export Fp # defined in ../config/curves to avoid recursive module dependencies

debug:
  func `==`*(a, b: Fp): CTBool[Word] =
    ## Returns true if 2 big ints are equal
    a.mres == b.mres

  func `$`*[C: static Curve](a: Fp[C]): string =
    result = "Fp[" & $C
    result.add "]("
    result.add $a.mres
    result.add ')'

# No exceptions allowed
{.push raises: [].}
{.push inline.}

# ############################################################
#
#                        Conversion
#
# ############################################################

func fromBig*[C: static Curve](T: type Fp[C], src: BigInt): Fp[C] {.noInit.} =
  ## Convert a BigInt to its Montgomery form
  result.mres.montyResidue(src, C.Mod.mres, C.getR2modP(), C.getNegInvModWord())

func fromBig*[C: static Curve](dst: var Fp[C], src: BigInt) {.noInit.} =
  ## Convert a BigInt to its Montgomery form
  dst.mres.montyResidue(src, C.Mod.mres, C.getR2modP(), C.getNegInvModWord())

func toBig*(src: Fp): auto {.noInit.} =
  ## Convert a finite-field element to a BigInt in natral representation
  var r {.noInit.}: typeof(src.mres)
  r.redc(src.mres, Fp.C.Mod.mres, Fp.C.getNegInvModWord())
  return r

# ############################################################
#
#                Field arithmetic primitives
#
# ############################################################
#
# Note: the library currently implements generic routine for odd field modulus.
#       Routines for special field modulus form:
#       - Mersenne Prime (2^k - 1),
#       - Generalized Mersenne Prime (NIST Prime P256: 2^256 - 2^224 + 2^192 + 2^96 - 1)
#       - Pseudo-Mersenne Prime (2^m - k for example Curve25519: 2^255 - 19)
#       - Golden Primes (φ^2 - φ - 1 with φ = 2^k for example Ed448-Goldilocks: 2^448 - 2^224 - 1)
#       exist and can be implemented with compile-time specialization.

func setZero*(a: var Fp) =
  ## Set ``a`` to zero
  a.mres.setZero()

func setOne*(a: var Fp) =
  ## Set ``a`` to one
  # Note: we need 1 in Montgomery residue form
  a.mres = Fp.C.getMontyOne()

func `+=`*(a: var Fp, b: Fp) =
  ## In-place addition modulo p
  var overflowed = add(a.mres, b.mres)
  overflowed = overflowed or not csub(a.mres, Fp.C.Mod.mres, CtFalse) # a >= P
  discard csub(a.mres, Fp.C.Mod.mres, overflowed)

func `-=`*(a: var Fp, b: Fp) =
  ## In-place substraction modulo p
  let underflowed = sub(a.mres, b.mres)
  discard cadd(a.mres, Fp.C.Mod.mres, underflowed)

func double*(a: var Fp) =
  ## Double ``a`` modulo p
  var overflowed = double(a.mres)
  overflowed = overflowed or not csub(a.mres, Fp.C.Mod.mres, CtFalse) # a >= P
  discard csub(a.mres, Fp.C.Mod.mres, overflowed)

func sum*(r: var Fp, a, b: Fp) =
  ## Sum ``a`` and ``b`` into ``r`` module p
  ## r is initialized/overwritten
  var overflowed = r.mres.sum(a.mres, b.mres)
  overflowed = overflowed or not csub(r.mres, Fp.C.Mod.mres, CtFalse) # r >= P
  discard csub(r.mres, Fp.C.Mod.mres, overflowed)

func diff*(r: var Fp, a, b: Fp) =
  ## Substract `b` from `a` and store the result into `r`.
  ## `r` is initialized/overwritten
  var underflowed = r.mres.diff(a.mres, b.mres)
  discard cadd(r.mres, Fp.C.Mod.mres, underflowed)

func double*(r: var Fp, a: Fp) =
  ## Double ``a`` into ``r``
  ## `r` is initialized/overwritten
  var overflowed = r.mres.double(a.mres)
  overflowed = overflowed or not csub(r.mres, Fp.C.Mod.mres, CtFalse) # r >= P
  discard csub(r.mres, Fp.C.Mod.mres, overflowed)

func `+`*(a, b: Fp): Fp {.noInit.} =
  ## Addition modulo p
  result.sum(a, b)

func `-`*(a, b: Fp): Fp {.noInit.} =
  ## Substraction modulo p
  result.diff(a, b)

func prod*(r: var Fp, a, b: Fp) =
  ## Store the product of ``a`` by ``b`` modulo p into ``r``
  ## ``r`` is initialized / overwritten
  r.mres.montyMul(a.mres, b.mres, Fp.C.Mod.mres, Fp.C.getNegInvModWord())

func `*`*(a, b: Fp): Fp {.noInit.} =
  ## Multiplication modulo p
  ##
  ## It is recommended to assign with {.noInit.}
  ## as Fp elements are usually large and this
  ## routine will zero init internally the result.
  result.prod(a, b)

func `*=`*(a: var Fp, b: Fp) =
  ## Multiplication modulo p
  ##
  ## Implementation note:
  ## - This requires a temporary field element
  ##
  ## Cost
  ## Stack: 1 * ModulusBitSize
  var tmp{.noInit.}: Fp
  tmp.prod(a, b)
  a = tmp

func square*(a: Fp): Fp {.noInit.} =
  ## Squaring modulo p
  ##
  ## It is recommended to assign with {.noInit.}
  ## as Fp elements are usually large and this
  ## routine will zero init internally the result.
  result.mres.montySquare(a.mres, Fp.C.Mod.mres, Fp.C.getNegInvModWord())

func pow*(a: var Fp, exponent: BigInt) =
  ## Exponentiation modulo p
  ## ``a``: a field element to be exponentiated
  ## ``exponent``: a big integer
  const windowSize = 5 # TODO: find best window size for each curves
  a.mres.montyPow(
    exponent,
    Fp.C.Mod.mres, Fp.C.getMontyOne(),
    Fp.C.getNegInvModWord(), windowSize
  )

func powUnsafeExponent*(a: var Fp, exponent: BigInt) =
  ## Exponentiation modulo p
  ## ``a``: a field element to be exponentiated
  ## ``exponent``: a big integer
  ##
  ## Warning ⚠️ :
  ## This is an optimization for public exponent
  ## Otherwise bits of the exponent can be retrieved with:
  ## - memory access analysis
  ## - power analysis
  ## - timing analysis
  const windowSize = 5 # TODO: find best window size for each curves
  a.mres.montyPowUnsafeExponent(
    exponent,
    Fp.C.Mod.mres, Fp.C.getMontyOne(),
    Fp.C.getNegInvModWord(), windowSize
  )

func inv*(a: var Fp) =
  ## Inversion modulo p
  ## Warning ⚠️ :
  ##   - This assumes that `Fp` is a prime field
  const windowSize = 5 # TODO: find best window size for each curves
  a.mres.montyPowUnsafeExponent(
    Fp.C.getInvModExponent(),
    Fp.C.Mod.mres, Fp.C.getMontyOne(),
    Fp.C.getNegInvModWord(), windowSize
  )
