# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./abstractions,
  ../named/config_fields_and_curves

# TODO: Keep internal and use bigint(Fp[Foo]) and bigint(Fr[Foo])

template matchingBigInt*(C: static Curve): untyped =
  ## BigInt type necessary to store the prime field Fp
  # Workaround: https://github.com/nim-lang/Nim/issues/16774
  BigInt[CurveBitWidth[C]]

template matchingOrderBigInt*(C: static Curve): untyped =
  ## BigInt type necessary to store the scalar field Fr
  # Workaround: https://github.com/nim-lang/Nim/issues/16774
  BigInt[CurveOrderBitWidth[C]]

type
  Fp*[C: static Curve] = object
    ## All operations on a Fp field are modulo P
    ## P being the prime modulus of the Curve C
    ## Internally, data is stored in Montgomery n-residue form
    ## with the magic constant chosen for convenient division (a power of 2 depending on P bitsize)
    # TODO, pseudo mersenne primes like 2²⁵⁵-19 have very fast modular reduction
    #       and don't need Montgomery representation
    mres*: matchingBigInt(C)

  Fr*[C: static Curve] = object
    ## All operations on a field are modulo `r`
    ## `r` being the prime curve order or subgroup order
    ## Internally, data is stored in Montgomery n-residue form
    ## with the magic constant chosen for convenient division (a power of 2 depending on P bitsize)
    mres*: matchingOrderBigInt(C)

  FF*[C: static Curve] = Fp[C] or Fr[C]

debug:
  # Those MUST not be enabled in production to avoiding the compiler auto-conversion and printing SecretWord by mistake, for example in crash logs.

  func `$`*[C: static Curve](a: Fp[C]): string =
    result = "Fp[" & $C
    result.add "]("
    result.add $a.mres
    result.add ')'

  func `$`*[C: static Curve](a: Fr[C]): string =
    result = "Fr[" & $C
    result.add "]("
    result.add $a.mres
    result.add ')'
