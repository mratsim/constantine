# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/[importutils, unittest],
  constantine/ethereum_ecdsa_signatures,
  constantine/math/arithmetic/finite_fields,
  constantine/math/ec_shortweierstrass,
  constantine/math/io/io_fields,
  constantine/named/algebras

suite "ECDSA public key recovery":
  test "Recovery rejects a non-point x without field wrapping":
    privateAccess(Signature)
    let signature = Signature(
      r: Fr[Secp256k1].fromHex(
        "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140"),
      s: Fr[Secp256k1].fromHex("01"))
    const message = "Constantine"

    var R {.noinit.}: EC_ShortW_Aff[Fp[Secp256k1], G1]
    check not bool(R.trySetFromCoordX(Fp[Secp256k1].fromBig(signature.r.toBig())))

    for evenY in [true, false]:
      var recovered {.noinit.}: PublicKey
      recovered.recoverPubkey(message, signature, evenY)
      check recovered.pubkey_is_zero()
