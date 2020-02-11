# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internal
  ./private/curves_config_parser

# ############################################################
#
#           Configuration of finite fields
#
# ############################################################

# Finite fields are preconfigured in this file
# To workaround the following limitation https://github.com/nim-lang/Nim/issues/11142
# i.e. an object can be parametrized by a compiletime bigint
# we instead have the fields, curve points and Montgomery objects
# be parametrized over an enum.

# Note, in the past the convention was to name a curve by its conjectured security level.
# as this might change with advances in research, the new convention is
# to name curves according to the length of the prime bit length.
# i.e. the BN254 was previously named BN128.

# Generates:
# - type Curve = enum
# - const CurveBitSize: array[Curve, int]
# - proc Mod(curve: static Curve): auto
#   which returns the field modulus of the curve
# - proc MontyMagic(curve: static Curve): static Word =
#   which returns the Montgomery magic constant
#   associated with the curve modulus
when not defined(testingCurves):
  declareCurves:
    # Barreto-Naehrig curve, Prime 254 bit, 128-bit security, https://eprint.iacr.org/2013/879.pdf
    # Usage: Zero-Knowledge Proofs / zkSNARKs in ZCash and Ethereum 1
    #        https://eips.ethereum.org/EIPS/eip-196
    curve BN254:
      bitsize: 254
      modulus: "0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47"
      # Equation: Y^2 = X^3 + 3
else:
  # Fake curve for testing field arithmetic
  declareCurves:
    curve Fake101:
      bitsize: 101
      modulus: "0x65" # 101 in hex
