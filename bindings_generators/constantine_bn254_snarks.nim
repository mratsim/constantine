# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./gen_bindings, ./gen_header

type
  bn254snarks_fr = Fr[BN254_Snarks]
  bn254snarks_fp = Fp[BN254_Snarks]
  bn254snarks_fp2 = Fp2[BN254_Snarks]
  bn254snarks_ec_g1_aff = ECP_ShortW_Aff[Fp[BN254_Snarks], G1]
  bn254snarks_ec_g1_jac = ECP_ShortW_Jac[Fp[BN254_Snarks], G1]
  bn254snarks_ec_g1_prj = ECP_ShortW_Prj[Fp[BN254_Snarks], G1]
  bn254snarks_ec_g2_aff = ECP_ShortW_Aff[Fp2[BN254_Snarks], G2]
  bn254snarks_ec_g2_jac = ECP_ShortW_Jac[Fp2[BN254_Snarks], G2]
  bn254snarks_ec_g2_prj = ECP_ShortW_Prj[Fp2[BN254_Snarks], G2]

collectBindings(cBindings):
  genBindingsField(bn254snarks_fr)
  genBindingsField(bn254snarks_fp)
  genBindingsFieldSqrt(bn254snarks_fp)
  genBindingsExtField(bn254snarks_fp2)
  genBindingsExtFieldSqrt(bn254snarks_fp2)
  genBindings_EC_ShortW_Affine(bn254snarks_ec_g1_aff, bn254snarks_fp)
  genBindings_EC_ShortW_NonAffine(bn254snarks_ec_g1_jac, bn254snarks_ec_g1_aff, bn254snarks_fp)
  genBindings_EC_ShortW_NonAffine(bn254snarks_ec_g1_prj, bn254snarks_ec_g1_aff, bn254snarks_fp)
  genBindings_EC_ShortW_Affine(bn254snarks_ec_g2_aff, bn254snarks_fp2)
  genBindings_EC_ShortW_NonAffine(bn254snarks_ec_g2_jac, bn254snarks_ec_g2_aff, bn254snarks_fp2)
  genBindings_EC_ShortW_NonAffine(bn254snarks_ec_g2_prj, bn254snarks_ec_g2_aff, bn254snarks_fp2)

# Write header
when isMainModule and defined(CTT_GENERATE_HEADERS):
  import std/[os, strformat]

  proc main() =
    # echo "Running bindings generation for " & getAppFilename().extractFilename()

    var dir = "."
    if paramCount() == 1:
      dir = paramStr(1)
    elif paramCount() > 1:
      let exeName = getAppFilename().extractFilename()
      echo &"Usage: {exeName} <optional directory to save header to>"
      echo "Found more than one parameter"
      quit 1

    var header: string
    header = genBuiltinsTypes()
    header &= '\n'
    header &= genCttBaseTypedef()
    header &= '\n'
    header &= genWordsRequired()
    header &= '\n'
    header &= genField("bn254snarks_fr", BN254_Snarks.getCurveOrderBitWidth())
    header &= '\n'
    header &= genField("bn254snarks_fp", BN254_Snarks.getCurveBitWidth())
    header &= '\n'
    header &= genExtField("bn254snarks_fp2", 2, "bn254snarks_fp")
    header &= '\n'
    header &= genEllipticCurvePoint("bn254snarks_ec_g1_aff", "x, y", "bn254snarks_fp")
    header &= '\n'
    header &= genEllipticCurvePoint("bn254snarks_ec_g1_jac", "x, y, z", "bn254snarks_fp")
    header &= '\n'
    header &= genEllipticCurvePoint("bn254snarks_ec_g1_prj", "x, y, z", "bn254snarks_fp")
    header &= '\n'
    header &= genEllipticCurvePoint("bn254snarks_ec_g2_aff", "x, y", "bn254snarks_fp2")
    header &= '\n'
    header &= genEllipticCurvePoint("bn254snarks_ec_g2_jac", "x, y, z", "bn254snarks_fp2")
    header &= '\n'
    header &= genEllipticCurvePoint("bn254snarks_ec_g2_prj", "x, y, z", "bn254snarks_fp2")
    header &= '\n'
    header &= declNimMain("bn254snarks")
    header &= '\n'
    header &= cBindings
    header &= '\n'

    header = genCpp(header)
    header = genHeader("BN@%$SNARKS", header)
    header = genHeaderLicense() & header

    writeFile(dir/"constantine_bn254_snarks.h", header)

  main()