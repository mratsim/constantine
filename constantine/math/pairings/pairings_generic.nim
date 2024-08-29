# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/named/algebras,
  ./cyclotomic_subgroups,
  ./pairings_bn, ./pairings_bls12,
  constantine/math/extension_fields,
  constantine/named/zoo_pairings

func pairing*[Name: static Algebra](gt: var AnyFp12[Name], P, Q: auto) {.inline.} =
  when family(Name) == BarretoNaehrig:
    pairing_bn(gt, P, Q)
  elif family(Name) == BarretoLynnScott:
    pairing_bls12(gt, P, Q)
  else:
    {.error: "Pairing not implemented for " & $Name.}

func millerLoop*[Name: static Algebra](gt: var AnyFp12[Name], Q, P: auto, n: int) {.inline.} =
  when Name == BN254_Snarks:
    gt.millerLoopGenericBN(Q, P, n)
  else:
    gt.millerLoopAddchain(Q, P, n)

export finalExpEasy

func finalExpHard*[Name: static Algebra](gt: var AnyFp12[Name]) {.inline.} =
  when family(Name) == BarretoNaehrig:
    gt.finalExpHard_BN()
  elif family(Name) == BarretoLynnScott:
    gt.finalExpHard_BLS12()
  else:
    {.error: "Final Exponentiation not implemented for " & $Name.}

func finalExp*[Name: static Algebra](gt: var AnyFp12[Name]){.inline.} =
  gt.finalExpEasy()
  gt.finalExpHard()
