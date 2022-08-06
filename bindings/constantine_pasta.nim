# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./gen_bindings, ./gen_header

type
  pallas_fr = Fr[Pallas]
  pallas_fp = Fp[Pallas]
  vesta_fr = Fr[Vesta]
  vesta_fp = Fp[Vesta]
  pallas_ec_aff = ECP_ShortW_Aff[Fp[Pallas], G1] 
  pallas_ec_jac = ECP_ShortW_Jac[Fp[Pallas], G1]
  pallas_ec_prj = ECP_ShortW_Prj[Fp[Pallas], G1]
  vesta_ec_aff = ECP_ShortW_Aff[Fp[Vesta], G1] 
  vesta_ec_jac = ECP_ShortW_Jac[Fp[Vesta], G1]
  vesta_ec_prj = ECP_ShortW_Prj[Fp[Vesta], G1]

collectBindings(cBindings):
  genBindingsField(pallas_fr)
  genBindingsField(pallas_fp)
  genBindingsFieldSqrt(pallas_fp)
  genBindingsField(vesta_fr)
  genBindingsField(vesta_fp)
  genBindingsFieldSqrt(vesta_fp)
  genBindings_EC_ShortW_Affine(pallas_ec_aff, pallas_fp)
  genBindings_EC_ShortW_NonAffine(pallas_ec_jac, pallas_ec_aff, pallas_fp)
  genBindings_EC_ShortW_NonAffine(pallas_ec_prj, pallas_ec_aff, pallas_fp)
  genBindings_EC_ShortW_Affine(vesta_ec_aff, pallas_fp)
  genBindings_EC_ShortW_NonAffine(vesta_ec_jac, vesta_ec_aff, vesta_fp)
  genBindings_EC_ShortW_NonAffine(vesta_ec_prj, vesta_ec_aff, vesta_fp)

# Write header
when isMainModule and defined(CttGenerateHeaders):
  import std/os
  
  proc main() =
    echo "Running bindings generation for " & getAppFilename().extractFilename()

    var header: string
    header = genBuiltinsTypes()
    header &= '\n'
    header &= genCttBaseTypedef()
    header &= '\n'
    header &= genWordsRequired()
    header &= '\n'
    header &= genField("pallas_fr", Pallas.getCurveOrderBitWidth())
    header &= '\n'
    header &= genField("pallas_fp", Pallas.getCurveBitWidth())
    header &= '\n'
    header &= genField("vesta_fr", Vesta.getCurveOrderBitWidth())
    header &= '\n'
    header &= genField("vesta_fp", Vesta.getCurveBitWidth())
    header &= '\n'
    header &= genEllipticCurvePoint("pallas_ec_aff", "x, y", "pallas_fp")
    header &= '\n'
    header &= genEllipticCurvePoint("pallas_ec_jac", "x, y, z", "pallas_fp")
    header &= '\n'
    header &= genEllipticCurvePoint("pallas_ec_prj", "x, y, z", "pallas_fp")
    header &= '\n'
    header &= genEllipticCurvePoint("vesta_ec_aff", "x, y", "vesta_fp")
    header &= '\n'
    header &= genEllipticCurvePoint("vesta_ec_jac", "x, y, z", "vesta_fp")
    header &= '\n'
    header &= genEllipticCurvePoint("vesta_ec_prj", "x, y, z", "vesta_fp")
    header &= '\n'
    header &= cBindings
    header &= '\n'
    header &= declNimMain("pasta")

    header = genCpp(header)
    header = genHeader("PASTA", header)
    header = genHeaderLicense() & header

    writeFile("constantine_pasta.h", header)


  main()