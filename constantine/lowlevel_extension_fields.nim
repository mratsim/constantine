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
    ./math/endomorphisms/frobenius,
    ./math/extension_fields,
    ./math/io/io_extfields

# ############################################################
#
#            Low-level named math objects API
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
  algebras.Algebra,
  algebras.getBigInt

export
  algebras.Fp,
  algebras.Fr,
  algebras.FF

# Extension fields
# ------------------------------------------------------------

export
  extension_fields.Fp2,
  # TODO: deal with Fp2->Fp6 vs Fp3->Fp6 and Fp2->Fp6->Fp12 vs Fp2->Fp4->Fp12
  # extension_fields.Fp4,
  # extension_fields.Fp6,
  extension_fields.Fp12

# Generic sandwich - https://github.com/nim-lang/Nim/issues/11225
export extension_fields.c0, extension_fields.`c0=`
export extension_fields.c1, extension_fields.`c1=`
export extension_fields.c2, extension_fields.`c2=`

export extension_fields.setZero
export extension_fields.setOne
export extension_fields.setMinusOne

export extension_fields.`==`
export extension_fields.isZero
export extension_fields.isOne
export extension_fields.isMinusOne

export extension_fields.ccopy

export extension_fields.neg
export extension_fields.`+=`
export extension_fields.`-=`
export extension_fields.double
export extension_fields.div2
export extension_fields.sum
export extension_fields.diff
export extension_fields.conj
export extension_fields.conjneg

export extension_fields.csetZero
export extension_fields.csetOne
export extension_fields.cneg
export extension_fields.csub
export extension_fields.cadd

export extension_fields.`*=`
export extension_fields.prod
export extension_fields.square
export extension_fields.inv

export extension_fields.isSquare
export extension_fields.sqrt_if_square
export extension_fields.sqrt

export frobenius.frobenius_map
