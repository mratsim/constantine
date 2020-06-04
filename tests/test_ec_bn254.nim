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
       id: int,
       EC: typedesc[ECP_SWei_Proj],
       Px, Py: string,
       scalar: string,
       Qx, Qy: string
     ) =

  test "test " & $id:
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

suite "BN254 implementation (and unsafe reference impl) vs SageMath":
  # Generated via sage sage/testgen_bn254_snarks.sage
  test(
    id = 1,
    EC = ECP_SWei_Proj[Fp[BN254_Snarks]],
    Px = "22d3af0f3ee310df7fc1a2a204369ac13eb4a48d969a27fcd2861506b2dc0cd7",
    Py = "1c994169687886ccd28dd587c29c307fb3cab55d796d73a5be0bbf9aab69912e",
    scalar = "e08a292f940cfb361cc82bc24ca564f51453708c9745a9cf8707b11c84bc448",
    Qx = "267c05cd49d681c5857124876748365313b9c285e783206f48513ce06d3df931",
    Qy = "2fa00719ce37465dbe7037f723ed5df08c76b9a27a4dd80d86c0ee5157349b96"
  )

  test(
    id = 2,
    EC = ECP_SWei_Proj[Fp[BN254_Snarks]],
    Px = "2724750abe620fce759b6f18729e40f891a514160d477811a44b222372cc4ea3",
    Py = "105cdcbe363921790a56bf2696e73642447c60b814827ca4dba86c814912c98a",
    scalar = "2f5c2960850eabadab1e5595ff0bf841206885653e7f2024248b281a86744790",
    Qx = "57d2dcbc665fb93fd5119bb982c29700d025423d60a42b5fe17210fd5a868fd",
    Qy = "2abad564ff78fbc266dfb77bdd110b22271136b33ce5049fb3ca05107787abc"
  )

  test(
    id = 3,
    EC = ECP_SWei_Proj[Fp[BN254_Snarks]],
    Px = "39bc19c41835082f86ca046b71875b051575072e4d6a4aeedac31eee34b07df",
    Py = "1fdbf42fc20421e1e775fd93ed1888d614f7e39067e7443f21b6a4817481c346",
    scalar = "29e140c33f706c0111443699b0b8396d8ead339a3d6f3c212b08749cf2a16f6b",
    Qx = "83895d1c7a2b15a5dfe9371983196591415182978e8ff0e83262e32d768c712",
    Qy = "2ed8b88e1cd08814ce1d1929d0e4bba6fb5897f915b3525cf12349256da95499"
  )

  test(
    id = 4,
    EC = ECP_SWei_Proj[Fp[BN254_Snarks]],
    Px = "157a3e1ff9dabccced9746e19855a9438098be6d734f07d1c069aa1bd05b8d87",
    Py = "1c96bf3e48bc1a6635d93d4f1302a0eba39bd907c5d861f2a9d0c714ee60f04d",
    scalar = "29b05bd55963e262e0fa458c76297fb5be3ec1421fdb1354789f68fdce81dc2c",
    Qx = "196aeca74447934eeaba0f2263177fcb7eb239985814f8ef2d7bf08677108c9",
    Qy = "1f5aa4c7df4a9855113c63d8fd55c512c7e919b8ae0352e280bdb1009299c3b2"
  )

  test(
    id = 5,
    EC = ECP_SWei_Proj[Fp[BN254_Snarks]],
    Px = "2f260967d4cd5d15f98c0a0a9d5abaae0c70d3b8d83e1e884586cd6ece395fe7",
    Py = "2a102c7aebdfaa999d5a99984148ada142f72f5d4158c10368a2e13dded886f6",
    scalar = "1796de74c1edac90d102e7c33f3fad94304eaff4a67a018cae678774d377f6cd",
    Qx = "28c73e276807863ecf4ae60b1353790f10f176ca8c55b3db774e33c569ef39d5",
    Qy = "c386e24828cead255ec7657698559b23a26fc9bd5db70a1fe20b48ecfbd6db9"
  )

  test(
    id = 6,
    EC = ECP_SWei_Proj[Fp[BN254_Snarks]],
    Px = "1b4ccef57f4411360a02b8228e4251896c9492ff93a69ba3720da0cd46a04e83",
    Py = "1fabcb215bd7c06ead2e6b0167497efc2cdd3dbacf69bcb0244142fd63c1e405",
    scalar = "116741cd19dac61c5e77877fc6fef40f363b164b501dfbdbc09e17ea51d6beb0",
    Qx = "192ca2e120b0f5296baf7cc47bfebbbc74748c8847bbdbe485bcb796de2622aa",
    Qy = "8bc6b1aa4532c727be8fd21a8176d55bc721c727af327f601f7a8dff655b0b9"
  )

  test(
    id = 7,
    EC = ECP_SWei_Proj[Fp[BN254_Snarks]],
    Px = "2807c88d6759280d6bd83a54d349a533d1a66dc32f72cab8114ab707f10e829b",
    Py = "dbf0d486aeed3d303880f324faa2605aa0219e35661bc88150470c7df1c0b61",
    scalar = "2a5976268563870739ced3e6efd8cf53887e8e4426803377095708509dd156ca",
    Qx = "2841f67de361436f64e582a134fe36ab7196334c758a07e732e1cf1ccb35a476",
    Qy = "21fb9b8311e53832044be5ff024f737aee474bc504c7c158fe760cc999da8612"
  )

  test(
    id = 8,
    EC = ECP_SWei_Proj[Fp[BN254_Snarks]],
    Px = "2754a174a33a55f2a31573767e9bf5381b47dca1cbebc8b68dd4df58b3f1cc2",
    Py = "f222f59c8893ad87c581dacb3f8b6e7c20e7a13bc5fb6e24262a3436d663b1",
    scalar = "25d596bf6caf4565fbfd22d81f9cef40c8f89b1e5939f20caa1b28056e0e4f58",
    Qx = "2b48dd3ace8e403c2905f00cdf13814f0dbecb0c0465e6455fe390cc9730f5a",
    Qy = "fe65f0cd4ae0d2e459daa4163f32deed1250b5c384eb5aeb933162a41793d25"
  )

  test(
    id = 9,
    EC = ECP_SWei_Proj[Fp[BN254_Snarks]],
    Px = "273bf6c679d8e880034590d16c007bbabc6c65ed870a263b5d1ce7375c18fd7",
    Py = "2904086cb9e33657999229b082558a74c19b2b619a0499afb2e21d804d8598ee",
    scalar = "67a499a389129f3902ba6140660c431a56811b53de01d043e924711bd341e53",
    Qx = "1d827e4569f17f068457ffc52f1c6ed7e2ec89b8b520efae48eff41827f79128",
    Qy = "be8c488bb9587bcb0faba916277974afe12511e54fbd749e27d3d7efd998713"
  )

  test(
    id = 10,
    EC = ECP_SWei_Proj[Fp[BN254_Snarks]],
    Px = "ec892c09a5f1c68c1bfec7780a1ebd279739383f2698eeefbba745b3e717fd5",
    Py = "23d273a1b9750fe1d4ebd4b7c25f4a8d7d94f6662c436305cca8ff2cdbd3f736",
    scalar = "d2f09ceaa2638b7ac3d7d4aa9eff7a12e93dc85db0f9676e5f19fb86d6273e9",
    Qx = "305d7692b141962a4a92038adfacc0d2691e5589ed097a1c661cc48c84e2b64e",
    Qy = "bafa230a0f5cc2fa3cf07fa46312cb724fc944b097890fa60f2cf42a1be7963"
  )
