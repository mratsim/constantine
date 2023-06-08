# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./gen_bindings, ./gen_header

type
  bls12381_fr = Fr[BLS12_381]
  bls12381_fp = Fp[BLS12_381]
  bls12381_fp2 = Fp2[BLS12_381]
  bls12381_ec_g1_aff = ECP_ShortW_Aff[Fp[BLS12_381], G1]
  bls12381_ec_g1_jac = ECP_ShortW_Jac[Fp[BLS12_381], G1]
  bls12381_ec_g1_prj = ECP_ShortW_Prj[Fp[BLS12_381], G1]
  bls12381_ec_g2_aff = ECP_ShortW_Aff[Fp2[BLS12_381], G2]
  bls12381_ec_g2_jac = ECP_ShortW_Jac[Fp2[BLS12_381], G2]
  bls12381_ec_g2_prj = ECP_ShortW_Prj[Fp2[BLS12_381], G2]

collectBindings(cBindings):
  genBindingsField(bls12381_fr)
  genBindingsField(bls12381_fp)
  genBindingsFieldSqrt(bls12381_fp)
  genBindingsExtField(bls12381_fp2)
  genBindingsExtFieldSqrt(bls12381_fp2)
  genBindings_EC_ShortW_Affine(bls12381_ec_g1_aff, bls12381_fp)
  genBindings_EC_ShortW_NonAffine(bls12381_ec_g1_jac, bls12381_ec_g1_aff, bls12381_fp)
  genBindings_EC_ShortW_NonAffine(bls12381_ec_g1_prj, bls12381_ec_g1_aff, bls12381_fp)
  genBindings_EC_ShortW_Affine(bls12381_ec_g2_aff, bls12381_fp2)
  genBindings_EC_ShortW_NonAffine(bls12381_ec_g2_jac, bls12381_ec_g2_aff, bls12381_fp2)
  genBindings_EC_ShortW_NonAffine(bls12381_ec_g2_prj, bls12381_ec_g2_aff, bls12381_fp2)

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
    header &= genField("bls12381_fr", BLS12_381.getCurveOrderBitWidth())
    header &= '\n'
    header &= genField("bls12381_fp", BLS12_381.getCurveBitWidth())
    header &= '\n'
    header &= genExtField("bls12381_fp2", 2, "bls12381_fp")
    header &= '\n'
    header &= genEllipticCurvePoint("bls12381_ec_g1_aff", "x, y", "bls12381_fp")
    header &= '\n'
    header &= genEllipticCurvePoint("bls12381_ec_g1_jac", "x, y, z", "bls12381_fp")
    header &= '\n'
    header &= genEllipticCurvePoint("bls12381_ec_g1_prj", "x, y, z", "bls12381_fp")
    header &= '\n'
    header &= genEllipticCurvePoint("bls12381_ec_g2_aff", "x, y", "bls12381_fp2")
    header &= '\n'
    header &= genEllipticCurvePoint("bls12381_ec_g2_jac", "x, y, z", "bls12381_fp2")
    header &= '\n'
    header &= genEllipticCurvePoint("bls12381_ec_g2_prj", "x, y, z", "bls12381_fp2")
    header &= '\n'
    header &= declNimMain("bls12381")
    header &= '\n'
    header &= cBindings
    header &= '\n'

    header = genCpp(header)
    header = genHeader("BLS12381", header)
    header = genHeaderLicense() & header

    writeFile(dir/"constantine_bls12_381.h", header)

  main()