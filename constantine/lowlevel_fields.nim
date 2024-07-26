# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
    ./platforms/abstractions,
    ./named/algebras,
    ./math/arithmetic,
    ./math/io/[io_bigints, io_fields]

# ############################################################
#
#            Low-level named Finite Fields API
#
# ############################################################

# Warning ⚠️:
#     The low-level APIs have no stability guarantee.
#     Use high-level protocols which are designed according to a stable specs
#     and with misuse resistance in mind.

{.push raises: [].} # No exceptions allowed in core cryptographic operations
{.push inline.}

# Base types
# ------------------------------------------------------------

export
  abstractions.SecretBool,
  abstractions.SecretWord,
  abstractions.BigInt,
  algebras.Algebra,
  algebras.getBigInt,
  algebras.bits,
  algebras.baseFieldModulus,
  algebras.scalarFieldModulus


# Scalar field Fr and Prime Field Fp
# ------------------------------------------------------------

export
  algebras.Fp,
  algebras.Fr,
  algebras.FF,

  # Workaround generic sandwich
  algebras.matchingBigInt,
  algebras.matchingOrderBigInt

func unmarshalBE*(dst: var FF, src: openarray[byte]): bool =
  ## Return true on success
  ## Return false if destination is too small compared to source
  var raw {.noInit.}: typeof dst.mres
  let ok = raw.unmarshal(src, bigEndian)
  if not ok:
    return false
  dst.fromBig(raw)
  return true

func marshalBE*(dst: var openarray[byte], src: FF): bool =
  ## Return true on success
  ## Return false if destination is too small compared to source
  var raw {.noInit.}: typeof src.mres
  raw.fromField(src)
  return dst.marshal(raw, bigEndian)

export arithmetic.fromBig
export arithmetic.fromField

export arithmetic.ccopy
export arithmetic.cswap

export arithmetic.`==`
export arithmetic.isZero
export arithmetic.isOne
export arithmetic.isMinusOne

export arithmetic.setZero
export arithmetic.setOne
export arithmetic.setMinusOne

export arithmetic.getZero
export arithmetic.getOne
export arithmetic.getMinusOne

export arithmetic.neg
export arithmetic.sum
export arithmetic.`+=`
export arithmetic.diff
export arithmetic.`-=`
export arithmetic.double

export arithmetic.prod
export arithmetic.`*=`
export arithmetic.square
export arithmetic.square_repeated
export arithmetic.sumprod

export arithmetic.csetZero
export arithmetic.csetOne
export arithmetic.cneg
export arithmetic.cadd
export arithmetic.csub

export arithmetic.div2
export arithmetic.inv
export arithmetic.inv_vartime

export arithmetic.isSquare
export arithmetic.invsqrt
export arithmetic.sqrt
export arithmetic.sqrt_invsqrt
export arithmetic.sqrt_invsqrt_if_square
export arithmetic.sqrt_if_square
export arithmetic.invsqrt_if_square
export arithmetic.sqrt_ratio_if_square

export arithmetic.pow
export arithmetic.pow_vartime

# Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
# tend to generate useless memory moves or have difficulties to minimize stack allocation
# and our types might be large (Fp12 ...)
# See: https://github.com/mratsim/constantine/issues/145
#
# They are intended for rapid prototyping, testing and debugging.
export arithmetic.`+`
export arithmetic.`-`
export arithmetic.`*`
export arithmetic.`^`
export arithmetic.`~^`
export arithmetic.toBig
