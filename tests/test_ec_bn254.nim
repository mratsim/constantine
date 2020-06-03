# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  unittest, times,
  # Internals
  ../constantine/config/[common, curves],
  ../constantine/arithmetic,
  ../constantine/io/[io_bigints, io_ec],
  ../constantine/elliptic/[ec_weierstrass_projective],
  # Test utilities
  ./support/ec_reference_scalar_mult

proc test(
       EC: typedesc[ECP_SWei_Proj],
       Px, Py: string,
       scalar: string,
       Qx, Qy: string
     ) =

  var P: EC
  let pOK = P.fromHex(Px, Py)
  doAssert pOK

  var Q: EC
  let qOK = Q.fromHex(Qx, Qy)

  let exponent = EC.F.C.matchingBigInt.fromHex(scalar)
  var exponentCanonical: array[(exponent.bits+7) div 8, byte]
  exponentCanonical.exportRawUint(exponent, bigEndian)

  var
    impl = P
    reference = P
    scratchSpace: array[1 shl 4, EC]

  impl.scalarMul(exponentCanonical, scratchSpace)
  reference.unsafe_ECmul_double_add(exponentCanonical)

  doAssert: bool(Q == reference)
  doAssert: bool(Q == impl)

suite "BN254 vs SageMath":
  test "test 1":
    test(
      EC = ECP_SWei_Proj[Fp[BN254_Snarks]],
      Px = "22d3af0f3ee310df7fc1a2a204369ac13eb4a48d969a27fcd2861506b2dc0cd7",
      Py = "1c994169687886ccd28dd587c29c307fb3cab55d796d73a5be0bbf9aab69912e",
      scalar = "e08a292f940cfb361cc82bc24ca564f51453708c9745a9cf8707b11c84bc448",
      Qx = "267c05cd49d681c5857124876748365313b9c285e783206f48513ce06d3df931",
      Qy = "2fa00719ce37465dbe7037f723ed5df08c76b9a27a4dd80d86c0ee5157349b96"
    )
