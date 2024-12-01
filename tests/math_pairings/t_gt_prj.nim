# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.



import
  # Standard library
  std/[unittest, times, typetraits],
  # Internals
  constantine/platforms/abstractions,
  constantine/math/extension_fields,
  constantine/named/[algebras, zoo_pairings],
  constantine/math/arithmetic,
  constantine/math/io/io_extfields,
  constantine/math/pairings/[cyclotomic_subgroups, gt_prj, pairings_generic],
  # Test utilities
  helpers/prng_unsafe

# Random seed for reproducibility
var rng: RngState
# TODO: BN254_Snarks final exponentiation sometimes doesn't output in the cyclotomic subgroup?
#       but BN254_Nogami is correct.
# let seed = 1724963212
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "𝔾ₜ projective", " xoshiro512** seed: ", seed


const Fp6iters = 10
const BatchIters = 1
const BatchSize = 256

suite "𝔽p6 projective over 𝔽p2":
  test "Select check from Magma":
    proc test() =
      let a = Fp6[BLS12_381].fromHex(
        c0 = "0xF0B16BF504C2B2307C502BB86C77A1126434C91D66235C15AB0F48B8B6FDD52A4A9097084726CF0D3706FD59F940A04",
        c1 = "0x169993EAAB1B3176FFDC4D252F6C888B0BEF84010619D37980E375B284DC743609F852EBE6954CE5357E991DB3BC3FD",
        c2 = "0x568DE6F81D1F7DA5DCF43CA45C7F5050C0FD32C9AAF363DA40165B3FCB12F1FDE83EA16D78851778ECC211406024A34",
        c3 = "0xCB8E2532963E8BB106116CDFA4BE728FADDCC0C5288B3F460D97952E1664749FFFF8E41973FB399927E7C6CF6284BB9",
        c4 = "0x3CB3FA69F5CFC10CB0C6801E87DE92D4C367A9F81D2B9F8F1476DF61DCFF60BBAD411A3BF42EF4D4E2886481AD6AFF1",
        c5 = "0x129F8EA1E948439998186EEBECD42781325A6DBC76725E6D86E85210C0204EAFAC3DC9AF79DC78E32F5527E92BE117BB"
      )
      let b = Fp6[BLS12_381].fromHex(
        c0 = "0xC7CC4223D889342AD0C4950001C0020F5DAD7DCC53FBC0FC887E61F914E3EEFE8C869589AB23551216DCCA3857D0CA2",
        c1 = "0x107B8116E7E01BE14D1040FC3F9C1DF47CD56809B618F689BE69FEBF0C3539F9DD671AF1A28D2B1A87E7D84A6C0314FD",
        c2 = "0x171A9404C66EA77519FEA03FCC61A294030F60AC297F04F0444ECCB110727CAE817C98263F30D35DBA67768FCB38E80D",
        c3 = "0x97364150AEC48688DC696A118D34C516D53E49E472D291403B21F1E50FC80B161EC1093FAFDC53145B8AFC35C6D674E",
        c4 = "0x5D9C9762AD65C37344562BF962E71E8DBE7784A609DA2AE0C12BE80E038A18773D897B805A16DB6FE81BFBA2677B5E1",
        c5 = "0x159F912AC0025E99401D13E373507F38487277F3E96B72C4A6579DE18E4A9C48D49A0D03AF7386FF5551F0943052DEF7"
      )
      let r_expected = Fp6[BLS12_381].fromHex(
        c0 = "0xC65C4FF0FA3AC8563914A5C98C81223BC209CEEE42BE52DD5BAD8D250A57670D642F1F9F83276F835144A3A9D5F4FF8",
        c1 = "0x658DE5A1BDE715A5BF28EA2FBBFB9BF1E0248F9EF6651642A6E6FB9EE4F59EA413B6D5C672A0F2757E93B6E26D9320C",
        c2 = "0x166789746DBD8AB1A4ED5A519DCC31CF7F2EA10672D4901B68F8B2B2F48511AA0D6E0019D50CDCE53ADD46F6AAD61DA0",
        c3 = "0xC384B85063C2914FB2DBCBA15CA58D3EC20A5E071F04A6FEBC3617495AF40EDE733132374EEB52E8A693B0569208C19",
        c4 = "0x12B3F1E535B87E1AA568E93B98890649EDFB77E4F4C7B05570CD16B03BE80D55A9414F7FDA384023E996FFF2EAD0202D",
        c5 = "0x7EC259CCDEB57FAA2393EFFBFEB6A9107F0FB97DEAA3D602667CD5874D53DBE00EA6F30BAFFB1FCB38C4D11D2A8A29F"
      )
      let r4_expected = Fp6[BLS12_381].fromHex(
        c0 = "0x17960212050ECB7B432981BC1FD49BB78C0B28369D2A81F7EFBA90A84BE4E39F3A5FC7E92F75DBE11A5228EA757D9535",
        c1 = "0x196379686F79C5696FCA3A8BEEFEE6FC780923E7BD994590A9B9BEE7B93D67A904EDB5719CA83C9D5FA4EDB89B64C830",
        c2 = "0xB9AF0130A7676F7B2627223AD4DC0B7CF54A18AF0C3082F6E5052E8EE01643BD9B4006B40377395BD781BDAAB59767F",
        c3 = "0x16E01C29DF70BDB9A19B4B3213DDB6784C0B4BFCD43C170047DCB331600C0D937E204C8F2266D4BA6FA5EC15A48285B9",
        c4 = "0x16CDA3C063E22B35FF6C5581DB8CBF78EEFF4889EC149BD6F4D2B57F023E490E67AD3E0206390090325DFFCBAB412B5E",
        c5 = "0x5AF8488FE2D79503DC95448BC61FD6CBB4CA2DA8723E2C1326E62C0DCA400D3E4FDBCC43AAAC7F3143234474AA2DFD1"
      )

      var r, r4: Fp6[BLS12_381]
      r.prod(a, b)
      doAssert bool(r == r_expected)

      r4.prod(r, 4)
      doAssert bool(r4 == r4_expected)

      var r4prj: Fp6prj[BLS12_381]
      r4prj.prod_prj(a, b)
      r4 = Fp6[BLS12_381](r4prj)
      doAssert bool(r4 == r4_expected)

    test()

  test "Toom-Cook 𝔽p6mulprj(a, b) = 4ab":
    proc test(Name: static Algebra) =
      for i in 0 ..< Fp6iters:
        let a = rng.random_long01Seq(Fp6[Name])
        let b = rng.random_long01Seq(Fp6[Name])

        var r_classic {.noInit.}: Fp6[Name]
        var r_toomcook {.noInit.}: Fp6prj[Name]

        r_classic.prod(a, b)
        r_toomcook.prod_prj(a, b)

        r_classic *= 4
        let r_prj = Fp6[Name](r_toomcook)

        doAssert bool(r_classic == r_prj)

    test(BN254_Nogami)
    test(BN254_Snarks)
    test(BLS12_381)

  test "Toom-Cook 𝔽p6sqrprj(a, b) = 4a²":
    proc test(Name: static Algebra) =
      for i in 0 ..< Fp6iters:
        let a = rng.random_long01Seq(Fp6[Name])

        var r_classic {.noInit.}: Fp6[Name]
        var r_toomcook {.noInit.}: Fp6prj[Name]

        r_classic.square(a)
        r_toomcook.square_prj(a)

        r_classic *= 4
        let r_prj = Fp6[Name](r_toomcook)

        doAssert bool(r_classic == r_prj)

    test(BN254_Nogami)
    test(BN254_Snarks)
    test(BLS12_381)

suite "Torus-based Cryptography for 𝔾ₜ, T₂(𝔽p6) compression":

  func random_gt(rng: var RngState, F: typedesc): F {.noInit.} =
    let r = rng.random_long01Seq(F)
    result = r
    result.finalExp()

    doAssert bool result.isInCyclotomicSubgroup(), block:
      $F.Name & ": input was not in the cyclotomic subgroup despite a final exponentiation:\n" &
      "    " & r.toHex(indent = 4)
    doAssert bool result.isInPairingSubgroup(), block:
      $F.Name & ": input was not in the pairing subgroup despite a final exponentiation:\n" &
      "    " & r.toHex(indent = 4)

  test "T₂(𝔽p6) <-> 𝔾ₜ":
    proc test(Name: static Algebra) =
      for i in 0 ..< Fp6iters:
        type MyFp12 = QuadraticExt[Fp6[Name]] # Even if we choose to Fp2 -> Fp4 -> Fp12
                                              # we want this test to pass
        let a = rng.random_gt(MyFp12)

        var r_taff: T2Aff[Fp6[Name]]
        var r_tprj: T2Prj[Fp6[Name]]
        r_taff.fromGT_vartime(a)
        r_tprj.fromGT_vartime(a)

        var a2, a3: MyFp12
        a2.fromTorus2_vartime(r_taff)
        a3.fromTorus2_vartime(r_tprj)

        doAssert bool a2 == a, block:
          "T₂(𝔽p6) <-> 𝔾ₜ: Failure for " & $Name & " with input:\n" &
          "    " & a.toHex(indent = 4)
        doAssert bool a3 == a, block:
          "T₂(𝔽p6) <-> 𝔾ₜ: Failure for " & $Name & " with input:\n" &
          "    " & a.toHex(indent = 4)

    test(BN254_Nogami)
    # test(BN254_Snarks)
    test(BLS12_381)

  # ====================================================================================

  test "T₂prj(𝔽p6) <- T₂aff(𝔽p6) * T₂aff(𝔽p6)":
    proc test(Name: static Algebra) =
      for i in 0 ..< Fp6iters:
        type MyFp12 = QuadraticExt[Fp6[Name]] # Even if we choose to Fp2 -> Fp4 -> Fp12
                                        # we want this test to pass
        let a = rng.random_gt(MyFp12)
        let b = rng.random_gt(MyFp12)

        var a_taff, b_taff: T2Aff[Fp6[Name]]
        var r_tprj: T2Prj[Fp6[Name]]
        a_taff.fromGT_vartime(a)
        b_taff.fromGT_vartime(b)
        r_tprj.affineProd_vartime(a_taff, b_taff)

        var r_gt: MyFp12
        r_gt.prod(a, b)

        var r: MyFp12
        r.fromTorus2_vartime(r_tprj)

        doAssert bool r == r_gt

    test(BN254_Nogami)
    # test(BN254_Snarks)
    test(BLS12_381)

  test "T₂prj(𝔽p6) <- T₂prj(𝔽p6) * T₂aff(𝔽p6)":
    proc test(Name: static Algebra) =
      for i in 0 ..< Fp6iters:
        type MyFp12 = QuadraticExt[Fp6[Name]] # Even if we choose to Fp2 -> Fp4 -> Fp12
                                        # we want this test to pass
        let a = rng.random_gt(MyFp12)
        let b = rng.random_gt(MyFp12)

        var b_taff: T2Aff[Fp6[Name]]
        var a_tprj, r_tprj: T2Prj[Fp6[Name]]
        a_tprj.fromGT_vartime(a)
        b_taff.fromGT_vartime(b)
        r_tprj.mixedProd_vartime(a_tprj, b_taff)

        var r_gt: MyFp12
        r_gt.prod(a, b)

        var r: MyFp12
        r.fromTorus2_vartime(r_tprj)

        doAssert bool r == r_gt

    test(BN254_Nogami)
    # test(BN254_Snarks)
    test(BLS12_381)

  test "T₂prj(𝔽p6) <- T₂prj(𝔽p6) * T₂aff(𝔽p6) - with aliasing":
    proc test(Name: static Algebra) =
      for i in 0 ..< Fp6iters:
        type MyFp12 = QuadraticExt[Fp6[Name]] # Even if we choose to Fp2 -> Fp4 -> Fp12
                                        # we want this test to pass
        let a = rng.random_gt(MyFp12)
        let b = rng.random_gt(MyFp12)

        var b_taff: T2Aff[Fp6[Name]]
        var a_tprj, r_tprj: T2Prj[Fp6[Name]]
        a_tprj.fromGT_vartime(a)
        b_taff.fromGT_vartime(b)
        r_tprj = a_tprj
        r_tprj.mixedProd_vartime(r_tprj, b_taff)

        var r_gt: MyFp12
        r_gt.prod(a, b)

        var r: MyFp12
        r.fromTorus2_vartime(r_tprj)

        doAssert bool r == r_gt

    test(BN254_Nogami)
    # test(BN254_Snarks)
    test(BLS12_381)

  test "T₂prj(𝔽p6) <- T₂prj(𝔽p6) * T₂prj(𝔽p6)":
    proc test(Name: static Algebra) =
      for i in 0 ..< Fp6iters:
        type MyFp12 = QuadraticExt[Fp6[Name]] # Even if we choose to Fp2 -> Fp4 -> Fp12
                                        # we want this test to pass
        let a = rng.random_gt(MyFp12)
        let b = rng.random_gt(MyFp12)

        var a_tprj, b_tprj, r_tprj: T2Prj[Fp6[Name]]
        a_tprj.fromGT_vartime(a)
        b_tprj.fromGT_vartime(b)
        r_tprj.prod(a_tprj, b_tprj)

        var r_gt: MyFp12
        r_gt.prod(a, b)

        var r: MyFp12
        r.fromTorus2_vartime(r_tprj)

        doAssert bool r == r_gt

    test(BN254_Nogami)
    # test(BN254_Snarks)
    test(BLS12_381)

  test "T₂prj(𝔽p6) <- T₂prj(𝔽p6) * T₂prj(𝔽p6) - with aliasing of lhs":
    proc test(Name: static Algebra) =
      for i in 0 ..< Fp6iters:
        type MyFp12 = QuadraticExt[Fp6[Name]] # Even if we choose to Fp2 -> Fp4 -> Fp12
                                        # we want this test to pass
        let a = rng.random_gt(MyFp12)
        let b = rng.random_gt(MyFp12)

        var a_tprj, b_tprj, r_tprj: T2Prj[Fp6[Name]]
        a_tprj.fromGT_vartime(a)
        b_tprj.fromGT_vartime(b)
        r_tprj = a_tprj
        r_tprj.prod(r_tprj, b_tprj)

        var r_gt: MyFp12
        r_gt.prod(a, b)

        var r: MyFp12
        r.fromTorus2_vartime(r_tprj)

        doAssert bool r == r_gt

    test(BN254_Nogami)
    # test(BN254_Snarks)
    test(BLS12_381)

  test "T₂prj(𝔽p6) <- T₂prj(𝔽p6) * T₂prj(𝔽p6) - with aliasing of rhs":
    proc test(Name: static Algebra) =
      for i in 0 ..< Fp6iters:
        type MyFp12 = QuadraticExt[Fp6[Name]] # Even if we choose to Fp2 -> Fp4 -> Fp12
                                        # we want this test to pass
        let a = rng.random_gt(MyFp12)
        let b = rng.random_gt(MyFp12)

        var a_tprj, b_tprj, r_tprj: T2Prj[Fp6[Name]]
        a_tprj.fromGT_vartime(a)
        b_tprj.fromGT_vartime(b)
        r_tprj = b_tprj
        r_tprj.prod(a_tprj, r_tprj)

        var r_gt: MyFp12
        r_gt.prod(a, b)

        var r: MyFp12
        r.fromTorus2_vartime(r_tprj)

        doAssert bool r == r_gt

    test(BN254_Nogami)
    # test(BN254_Snarks)
    test(BLS12_381)

  # ====================================================================================

  test "T₂prj(𝔽p6) <- T₂aff(𝔽p6)²":
    proc test(Name: static Algebra) =
      for i in 0 ..< Fp6iters:
        type MyFp12 = QuadraticExt[Fp6[Name]] # Even if we choose to Fp2 -> Fp4 -> Fp12
                                        # we want this test to pass
        let a = rng.random_gt(MyFp12)

        var a_taff: T2Aff[Fp6[Name]]
        var r_tprj: T2Prj[Fp6[Name]]
        a_taff.fromGT_vartime(a)
        r_tprj.affineSquare_vartime(a_taff)

        var r_gt: MyFp12
        r_gt.square(a)

        var r: MyFp12
        r.fromTorus2_vartime(r_tprj)

        doAssert bool r == r_gt

    test(BN254_Nogami)
    # test(BN254_Snarks)
    test(BLS12_381)

  test "T₂prj(𝔽p6) <- T₂prj(𝔽p6)²":
    proc test(Name: static Algebra) =
      for i in 0 ..< Fp6iters:
        type MyFp12 = QuadraticExt[Fp6[Name]] # Even if we choose to Fp2 -> Fp4 -> Fp12
                                        # we want this test to pass
        let a = rng.random_gt(MyFp12)

        var a_tprj, r_tprj: T2Prj[Fp6[Name]]
        a_tprj.fromGT_vartime(a)
        r_tprj.square(a_tprj)

        var r_gt: MyFp12
        r_gt.square(a)

        var r: MyFp12
        r.fromTorus2_vartime(r_tprj)

        doAssert bool r == r_gt

    test(BN254_Nogami)
    # test(BN254_Snarks)
    test(BLS12_381)

  # ====================================================================================

  test "Batch conversion: T₂(𝔽p6) <- 𝔾ₜ":
    proc test(Name: static Algebra) =
      for i in 0 ..< BatchIters:
        type F6 = Fp6[Name]
        type MyFp12 = QuadraticExt[F6] # Even if we choose to Fp2 -> Fp4 -> Fp12
                                              # we want this test to pass

        var aa = newSeq[MyFp12](BatchSize)
        for a in aa.mitems():
          a = rng.random_gt(MyFp12)

        var r_batch = newSeq[T2Aff[F6]](BatchSize)
        var r_expected = newSeq[T2Aff[F6]](BatchSize)

        for i in 0 ..< BatchSize:
          r_expected[i].fromGT_vartime(aa[i])

        r_batch.batchFromGT_vartime(aa)

        for i in 0 ..< BatchSize:
          doAssert bool(F6(r_batch[i]) == F6(r_expected[i])), block:
            "\niteration " & $i & ":\n" &
            "  found: " & F6(r_batch[i]).toHex(indent = 12) & "\n" &
            "  expected: " & F6(r_expected[i]).toHex(indent = 12) & "\n"

    test(BN254_Nogami)
    # test(BN254_Snarks)
    test(BLS12_381)

  test "Batch conversion: 𝔾ₜ <- T₂(𝔽p6)":
    proc test(Name: static Algebra) =
      for i in 0 ..< BatchIters:
        type F6 = Fp6[Name]
        type MyFp12 = QuadraticExt[F6] # Even if we choose to Fp2 -> Fp4 -> Fp12
                                              # we want this test to pass

        var aa = newSeq[MyFp12](BatchSize)
        for a in aa.mitems():
          a = rng.random_gt(MyFp12)

        var t2s = newSeq[T2Prj[F6]](BatchSize)

        for i in 0 ..< BatchSize:
          t2s[i].fromGT_vartime(aa[i])

        var aa_batch = newSeq[MyFp12](BatchSize)
        aa_batch.batchFromTorus2_vartime(t2s)

        for i in 0 ..< BatchSize:
          doAssert bool(aa[i] == aa_batch[i]), block:
            "\niteration " & $i & ":\n" &
            "  found: " & aa_batch[i].toHex(indent = 12) & "\n" &
            "  expected: " & aa[i].toHex(indent = 12) & "\n"

    test(BN254_Nogami)
    # test(BN254_Snarks)
    test(BLS12_381)
