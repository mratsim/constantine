# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/macros,
  # Internal
  ../../platforms/abstractions,
  ./type_bigint,
  ./curves_declaration

export Curve

# ############################################################
#
#                 Field properties
#
# ############################################################

{.experimental: "dynamicBindSym".}

macro Mod*(C: static Curve): untyped =
  ## Get the Modulus associated to a curve
  result = bindSym($C & "_Modulus")

template getCurveBitwidth*(C: Curve): int =
  ## Returns the number of bits taken by the curve modulus
  CurveBitWidth[C]

template matchingBigInt*(C: static Curve): untyped =
  # Workaround: https://github.com/nim-lang/Nim/issues/16774
  BigInt[CurveBitWidth[C]]

template matchingLimbs2x*(C: Curve): untyped =
  const N2 = wordsRequired(getCurveBitwidth(C)) * 2 # TODO upstream, not precomputing N2 breaks semcheck
  array[N2, SecretWord] # TODO upstream, using Limbs[N2] breaks semcheck

func hasP3mod4_primeModulus*(C: static Curve): static bool =
  ## Returns true iff p ≡ 3 (mod 4)
  (BaseType(C.Mod.limbs[0]) and 3) == 3

func hasP5mod8_primeModulus*(C: static Curve): static bool =
  ## Returns true iff p ≡ 5 (mod 8)
  (BaseType(C.Mod.limbs[0]) and 7) == 5

func hasP9mod16_primeModulus*(C: static Curve): static bool =
  ## Returns true iff p ≡ 9 (mod 16)
  (BaseType(C.Mod.limbs[0]) and 15) == 9