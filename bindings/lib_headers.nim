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

import std/[os, strformat, strutils]
import ./c_typedefs, ./lib_curves

proc writeHeader_classicCurve(filepath: string, curve: string, modBits, orderBits: int, curve_decls: string) =
  var header: string
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

  header = genCpp(header)
  header = genHeaderGuardAndInclude(curve.toUpperASCII(), header)
  header = genHeaderLicense() & header

  writeFile(filepath, header)

proc writeHeader_pairingFriendly(filepath: string, curve: string, modBits, orderBits: int, curve_decls: string, g2_extfield: int) =
  let fpK = if g2_extfield == 1: "fp"
              else: "fp" & $g2_extfield

  var header: string
  header &= genField(&"{curve}_fr", orderBits)
  header &= '\n'
  header &= genField(&"{curve}_fp", modBits)
  header &= '\n'
  header &= genExtField(&"{curve}_fp2", 2, &"{curve}_fp")
  header &= '\n'
  header &= genEllipticCurvePoint(&"{curve}_ec_g1_aff", "x, y", &"{curve}_fp")
  header &= '\n'
  header &= genEllipticCurvePoint(&"{curve}_ec_g1_jac", "x, y, z", &"{curve}_fp")
  header &= '\n'
  header &= genEllipticCurvePoint(&"{curve}_ec_g1_prj", "x, y, z", &"{curve}_fp")
  header &= '\n'
  header &= genEllipticCurvePoint(&"{curve}_ec_g2_aff", "x, y", &"{curve}_{fpK}")
  header &= '\n'
  header &= genEllipticCurvePoint(&"{curve}_ec_g2_jac", "x, y, z", &"{curve}_{fpK}")
  header &= '\n'
  header &= genEllipticCurvePoint(&"{curve}_ec_g2_prj", "x, y, z", &"{curve}_{fpK}")
  header &= '\n'
  header &= curve_decls
  header &= '\n'

  header = genCpp(header)
  header = genHeaderGuardAndInclude(curve.toUpperASCII(), header)
  header = genHeaderLicense() & header

  writeFile(filepath, header)

proc writeHeader(dirPath: string, C: static Curve, curve_decls: string) =
  const modBits = C.getCurveBitWidth()
  const orderBits = C.getCurveOrderBitWidth()
  let curve = ($C).toLowerASCII()
  let relPath = dirPath/"constantine"/"curves"/curve & ".h"

  when C.family() == NoFamily:
    relPath.writeHeader_classicCurve(curve, modBits, orderBits, curve_decls)
  else:
    const g2_extfield = C.getEmbeddingDegree() div 6 # All pairing-friendly curves use a sextic twist
    relPath.writeHeader_pairingFriendly(curve, modBits, orderBits, curve_decls, g2_extfield)

  echo "Generated header: ", relPath

proc writeCurveHeaders(dir: string) =
  static: doAssert defined(CTT_MAKE_HEADERS), " Pass '-d:CTT_MAKE_HEADERS' to the compiler so that curves declarations are collected."

  writeHeader(dir, BLS12_381, cBindings_bls12_381)
  writeHeader(dir, BN254_Snarks, cBindings_bn254_snarks)
  writeHeader(dir, Pallas, cBindings_pallas)
  writeHeader(dir, Vesta, cBindings_vesta)

when isMainModule:
  proc main() {.inline.} =
    writeCurveHeaders("include")

  main()