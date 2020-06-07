# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./common,
  ./curves_declaration

type
  Fp*[C: static Curve] = object
    ## All operations on a field are modulo P
    ## P being the prime modulus of the Curve C
    ## Internally, data is stored in Montgomery n-residue form
    ## with the magic constant chosen for convenient division (a power of 2 depending on P bitsize)
    mres*: matchingBigInt(C)

debug:
  func `$`*[C: static Curve](a: Fp[C]): string =
    result = "Fp[" & $C
    result.add "]("
    result.add $a.mres
    result.add ')'
