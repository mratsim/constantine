# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
    constantine/math/[ec_shortweierstrass],
    constantine/named/zoo_generators,
    constantine/named/algebras

func derivePubkey*[Pubkey, SecKey](pubkey: var Pubkey, seckey: SecKey) =
  ## Generates the public key associated with the input secret key.
  ##
  ## The secret key MUST be in range (0, curve order)
  ## 0 is INVALID
  const Group = Pubkey.G
  type Field = Pubkey.F
  const EC = Field.Name

  var pk {.noInit.}: EC_ShortW_Jac[Field, Group]
  pk.setGenerator()
  pk.scalarMul(seckey)
  pubkey.affine(pk)
