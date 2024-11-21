# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#            Generator for curve headers
#
# ############################################################

import std/[os, strformat, strutils, intsets]
import ./c_typedefs, ./lib_curves
import constantine/platforms/static_for

proc writeHeader_classicCurve(filepath: string, curve: string, modBits, orderBits: int, curve_decls: string) =
  var header = "\n"
  header &= genField(&"{curve}_fr", orderBits)
  header &= '\n'
  header &= genField(&"{curve}_fp", modBits)
  header &= '\n'
  header &= genEllipticCurvePoint(&"{curve}_ec_aff", "x, y", &"{curve}_fp")
  header &= '\n'
  header &= genEllipticCurvePoint(&"{curve}_ec_jac", "x, y, z", &"{curve}_fp")
  header &= '\n'
  header &= genEllipticCurvePoint(&"{curve}_ec_prj", "x, y, z", &"{curve}_fp")
  header &= '\n'
  header &= curve_decls
  header &= '\n'

  header = "#include \"constantine/curves/bigints.h\"\n\n" & genCpp(header)
  header = genHeaderGuardAndInclude(curve.toUpperASCII(), header)
  header = genHeaderLicense() & header

  writeFile(filepath, header)

proc writeHeader_pairingFriendly(filepath: string, curve: string, modBits, orderBits: int, curve_decls: string, g2_extfield: int) =
  let fpK = if g2_extfield == 1: "fp"
              else: "fp" & $g2_extfield

  var header = "\n"
  header &= genField(&"{curve}_fr", orderBits)
  header &= '\n'
  header &= genField(&"{curve}_fp", modBits)
  header &= '\n'
  header &= genExtField(&"{curve}_fp2", 2, &"{curve}_fp")
  header &= '\n'
  header &= genEllipticCurvePoint(&"{curve}_g1_aff", "x, y", &"{curve}_fp")
  header &= '\n'
  header &= genEllipticCurvePoint(&"{curve}_g1_jac", "x, y, z", &"{curve}_fp")
  header &= '\n'
  header &= genEllipticCurvePoint(&"{curve}_g1_prj", "x, y, z", &"{curve}_fp")
  header &= '\n'
  header &= genEllipticCurvePoint(&"{curve}_g2_aff", "x, y", &"{curve}_{fpK}")
  header &= '\n'
  header &= genEllipticCurvePoint(&"{curve}_g2_jac", "x, y, z", &"{curve}_{fpK}")
  header &= '\n'
  header &= genEllipticCurvePoint(&"{curve}_g2_prj", "x, y, z", &"{curve}_{fpK}")
  header &= '\n'
  header &= curve_decls
  header &= '\n'

  header = "#include \"constantine/curves/bigints.h\"\n\n" & genCpp(header)
  header = genHeaderGuardAndInclude(curve.toUpperASCII(), header)
  header = genHeaderLicense() & header

  writeFile(filepath, header)

proc writeHeader(dirPath: string, Name: static Algebra, curve_decls: string) =
  const modBits = Fp[Name].bits()
  const orderBits = Fr[Name].bits()
  let curve = ($Name).toLowerASCII()
  let relPath = dirPath/"constantine"/"curves"/curve & ".h"

  when Name.family() == NoFamily:
    relPath.writeHeader_classicCurve(curve, modBits, orderBits, curve_decls)
  else:
    const g2_extfield = Name.getEmbeddingDegree() div 6 # All pairing-friendly curves use a sextic twist
    relPath.writeHeader_pairingFriendly(curve, modBits, orderBits, curve_decls, g2_extfield)

  echo "Generated header: ", relPath

proc writeParallelHeader(dirPath: string, Name: static Algebra, curve_decls: string) =
  const modBits = Fp[Name].bits()
  const orderBits = Fr[Name].bits()
  let curve = ($Name).toLowerASCII()
  let relPath = dirPath/"constantine"/"curves"/curve & "_parallel.h"

  var includes: string
  includes &= "#include \"constantine/core/threadpool.h\""
  includes &= '\n'
  includes &= &"#include \"constantine/curves/bigints.h\""
  includes &= '\n'
  includes &= &"#include \"constantine/curves/{curve}.h\""
  includes &= '\n'

  var header: string
  header &= curve_decls
  header &= '\n'

  header = "\n" & genCpp(header)
  header = genHeaderGuardAndInclude(curve.toUpperASCII() & "_PARALLEL", includes & header)
  header = genHeaderLicense() & header

  writeFile(relPath, header)
  echo "Generated header: ", relPath

proc writeBigIntHeader(dirPath: string, bigSizes: IntSet, big_codecs: string) =
  let relPath = dirPath/"constantine"/"curves"/"bigints.h"

  var header = "\n"

  for size in bigSizes:
    header &= genBigInt(size)
    header &= '\n'

  header &= big_codecs
  header &= '\n'

  header = "\n" & genCpp(header)
  header = genHeaderGuardAndInclude("BIGINTS", header)
  header = genHeaderLicense() & header

  writeFile(relPath, header)
  echo "Generated header: ", relPath

proc writeCurveHeaders(dir: string) =
  static: doAssert defined(CTT_MAKE_HEADERS), " Pass '-d:CTT_MAKE_HEADERS' to the compiler so that curves declarations are collected."

  const curveMappings = {
    BLS12_381: cBindings_bls12_381,
    BN254_Snarks: cBindings_bn254_snarks,
    Pallas: cBindings_pallas,
    Vesta: cBindings_vesta,
    Banderwagon: cBindings_banderwagon
  }

  staticFor i, 0, curveMappings.len:
    writeHeader(dir, curveMappings[i][0], curveMappings[i][1])

proc writeCurveParallelHeaders(dir: string) =
  static: doAssert defined(CTT_MAKE_HEADERS), " Pass '-d:CTT_MAKE_HEADERS' to the compiler so that curves declarations are collected."

  const curveMappings = {
    BLS12_381: cBindings_bls12_381_parallel,
    BN254_Snarks: cBindings_bn254_snarks_parallel,
    Pallas: cBindings_pallas_parallel,
    Vesta: cBindings_vesta_parallel
  }

  var bigSizes = initIntSet()

  staticFor i, 0, curveMappings.len:
    writeParallelHeader(dir, curveMappings[i][0], curveMappings[i][1])
    bigSizes.incl(Fp[curveMappings[i][0]].bits())
    bigSizes.incl(Fr[curveMappings[i][0]].bits())

  dir.writeBigIntHeader(bigSizes, cBindings_big)

when isMainModule:
  proc main() {.inline.} =
    writeCurveHeaders("include")
    writeCurveParallelHeaders("include")
  main()
