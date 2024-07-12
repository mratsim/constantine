# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[unittest, times, os, strutils],
  # 3rd party
  pkg/jsony,
  # Internals
  constantine/platforms/abstractions,
  constantine/named/algebras,
  constantine/math/extension_fields,
  constantine/math/io/[io_bigints, io_ec],
  constantine/math/ec_shortweierstrass,
  constantine/hash_to_curve/hash_to_curve,
  constantine/hashes

# Serialization
# --------------------------------------------------------------------------

type
  FieldDesc = object
    m: string
    p: string

  MapDesc = object
    name: string

  HashToCurveTest[EC: EC_ShortW_Aff] = object
    L: string
    Z: string
    ciphersuite: string
    curve: string
    dst: string
    expand: string
    field: FieldDesc
    hash: string
    k: string
    map: MapDesc
    randomOracle: bool
    vectors: seq[TestVector[EC]]

  TestVector*[EC: EC_ShortW_Aff] = object
    P: EC
    Q0, Q1: EC
    msg: string
    u: seq[string]

  EC_G1_hex = object
    x: string
    y: string

  Fp2_hex = string

  EC_G2_hex = object
    x: Fp2_hex
    y: Fp2_hex

const
  TestVectorsDir* =
    currentSourcePath.rsplit(DirSep, 1)[0] / "protocol_hash_to_curve"

proc parseHook*(src: string, pos: var int, value: var EC_ShortW_Aff) =
  # Note when nim-serialization was used:
  #   When EC_ShortW_Aff[Fp[Foo], G1]
  #   and EC_ShortW_Aff[Fp[Foo], G2]
  #   are generated in the same file (i.e. twists and base curve are both on Fp)
  #   this creates bad codegen, in the C code, the `value`parameter gets the wrong type
  #   TODO: upstream
  when EC_ShortW_Aff.F is Fp:
    var P: EC_G1_hex
    parseHook(src, pos, P)
    let ok = value.fromHex(P.x, P.y)
    doAssert ok, "\nDeserialization error on G1 for\n" &
      "  P.x: " & P.x & "\n" &
      "  P.y: " & P.x & "\n"
  elif EC_ShortW_Aff.F is Fp2:
    var P: EC_G2_hex
    parseHook(src, pos, P)
    let Px = P.x.split(',')
    let Py = P.y.split(',')

    let ok = value.fromHex(Px[0], Px[1], Py[0], Py[1])
    doAssert ok, "\nDeserialization error on G2 for\n" &
      "  P.x0: " & Px[0] & "\n" &
      "  P.x1: " & Px[1] & "\n" &
      "  P.y0: " & Py[0] & "\n" &
      "  P.y1: " & Py[1] & "\n"
  else:
    {.error: "Not Implemented".}

proc loadVectors(TestType: typedesc, filename: string): TestType =
  let content = readFile(TestVectorsDir/filename)
  result = content.fromJson(TestType)

# Testing
# ------------------------------------------------------------------------

proc run_hash_to_curve_test(
       EC: typedesc,
       spec_version: string,
       filename: string
     ) =

  when EC.G == G1:
    const G1_or_G2 = "G1"
  else:
    const G1_or_G2 = "G2"
  let vec = loadVectors(HashToCurveTest[EC_ShortW_Aff[EC.F, EC.G]], filename)

  let testSuiteDesc = "Hash to Curve " & $EC.getName() & " " & G1_or_G2 & " - official specs " & spec_version & " test vectors"

  suite testSuiteDesc & " [" & $WordBitWidth & "-bit words]":

    doAssert vec.hash == "sha256"
    doAssert vec.k == "0x80" # 128

    for i in 0 ..< vec.vectors.len:
      test "test " & $i & " - msg: \'" & vec.vectors[i].msg & "\'":
        var P{.noInit.}: EC
        sha256.hashToCurve(
          k = 128,
          output = P,
          augmentation = "",
          message = vec.vectors[i].msg,
          domainSepTag = vec.dst
        )

        var P_ref: EC
        P_ref.fromAffine(vec.vectors[i].P)

        doAssert: bool(P == P_ref)

proc run_hash_to_curve_svdw_test(
       EC: typedesc,
       spec_version: string,
       filename: string
     ) =

  when EC.G == G1:
    const G1_or_G2 = "G1"
  else:
    const G1_or_G2 = "G2"
  let vec = loadVectors(HashToCurveTest[EC_ShortW_Aff[EC.F, EC.G]], filename)

  let testSuiteDesc = "Hash to Curve " & $EC.getName() & " " & G1_or_G2 & " - official specs " & spec_version & " test vectors"

  suite testSuiteDesc & " [" & $WordBitWidth & "-bit words]":

    doAssert vec.hash == "sha256"
    doAssert vec.k == "0x80" # 128

    for i in 0 ..< vec.vectors.len:
      test "test " & $i & " - msg: \'" & vec.vectors[i].msg & "\'":
        var P{.noInit.}: EC
        sha256.hashToCurve_svdw(
          k = 128,
          output = P,
          augmentation = "",
          message = vec.vectors[i].msg,
          domainSepTag = vec.dst
        )

        var P_ref: EC
        P_ref.fromAffine(vec.vectors[i].P)

        doAssert: bool(P == P_ref)

echo "\n------------------------------------------------------\n"
echo "Hash-to-curve" & '\n'

# Hash-to-curve v8 to latest
# https://github.com/cfrg/draft-irtf-cfrg-hash-to-curve/blob/draft-irtf-cfrg-hash-to-curve-10/poc/vectors/BLS12381G2_XMD:SHA-256_SSWU_RO_.json
run_hash_to_curve_test(
  EC_ShortW_Prj[Fp[BLS12_381], G1],
  "v8",
  "tv_h2c_v8_BLS12_381_hash_to_G1_SHA256_SSWU_RO.json"
)

run_hash_to_curve_test(
  EC_ShortW_Prj[Fp2[BLS12_381], G2],
  "v8",
  "tv_h2c_v8_BLS12_381_hash_to_G2_SHA256_SSWU_RO.json"
)

# Hash-to-curve v7 (different domain separation tag)
# https://github.com/cfrg/draft-irtf-cfrg-hash-to-curve/blob/draft-irtf-cfrg-hash-to-curve-07/poc/vectors/BLS12381G2_XMD:SHA-256_SSWU_RO_.json
run_hash_to_curve_test(
  EC_ShortW_Prj[Fp[BLS12_381], G1],
  "v7",
  "tv_h2c_v7_BLS12_381_hash_to_G1_SHA256_SSWU_RO.json"
)

run_hash_to_curve_test(
  EC_ShortW_Prj[Fp2[BLS12_381], G2],
  "v7",
  "tv_h2c_v7_BLS12_381_hash_to_G2_SHA256_SSWU_RO.json"
)

# With the slower universal SVDW mapping instead of SSWU
run_hash_to_curve_svdw_test(
  EC_ShortW_Jac[Fp[BLS12_381], G1],
  "v7 (SVDW)",
  "tv_h2c_v7_BLS12_381_hash_to_G1_SHA256_SVDW_RO.json"
)

run_hash_to_curve_svdw_test(
  EC_ShortW_Jac[Fp2[BLS12_381], G2],
  "v7 (SVDW)",
  "tv_h2c_v7_BLS12_381_hash_to_G2_SHA256_SVDW_RO.json"
)
