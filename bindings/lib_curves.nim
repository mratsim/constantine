# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                          Curves
#
# ############################################################

import ./c_curve_decls
export c_curve_decls

when not defined(CTT_MAKE_HEADERS):
  template collectBindings(cBindingsStr: untyped, body: typed): untyped =
    body
else:
  # We gate `c_typedefs` as it imports strutils
  # which uses the {.rtl.} pragma and might compile in Nim Runtime Library procs
  # that cannot be removed.
  #
  # We want to ensure its only used for header generation, not in deployment.
  import ./c_typedefs
  import std/[macros, strutils]

  macro collectBindings(cBindingsStr: untyped, body: typed): untyped =
    ## Collect function definitions from a generator template
    var cBindings: string
    for generator in body:
      generator.expectKind(nnkStmtList)
      for fnDef in generator:
        if fnDef.kind notin {nnkProcDef, nnkFuncDef}:
          continue

        cBindings &= "\n"
        # rettype name(pType0* pName0, pType1* pName1, ...);
        cBindings &= fnDef.params[0].toCrettype()
        cBindings &= ' '
        cBindings &= $fnDef.name
        cBindings &= '('
        for i in 1 ..< fnDef.params.len:
          if i != 1: cBindings &= ", "

          let paramDef = fnDef.params[i]
          paramDef.expectKind(nnkIdentDefs)
          let pType = paramDef[^2]
          # No default value
          paramDef[^1].expectKind(nnkEmpty)

          for j in 0 ..< paramDef.len - 2:
            if j != 0: cBindings &= ", "
            var name = $paramDef[j]
            cBindings &= toCparam(name.split('`')[0], pType)

        if fnDef.params[0].eqIdent"bool":
          cBindings &= ") __attribute__((warn_unused_result));"
        else:
          cBindings &= ");"


      result = newConstStmt(nnkPostfix.newTree(ident"*", cBindingsStr), newLit cBindings)


# ----------------------------------------------------------

type
  bls12_381_fr = Fr[BLS12_381]
  bls12_381_fp = Fp[BLS12_381]
  bls12_381_fp2 = Fp2[BLS12_381]
  bls12_381_ec_g1_aff = ECP_ShortW_Aff[Fp[BLS12_381], G1]
  bls12_381_ec_g1_jac = ECP_ShortW_Jac[Fp[BLS12_381], G1]
  bls12_381_ec_g1_prj = ECP_ShortW_Prj[Fp[BLS12_381], G1]
  bls12_381_ec_g2_aff = ECP_ShortW_Aff[Fp2[BLS12_381], G2]
  bls12_381_ec_g2_jac = ECP_ShortW_Jac[Fp2[BLS12_381], G2]
  bls12_381_ec_g2_prj = ECP_ShortW_Prj[Fp2[BLS12_381], G2]

collectBindings(cBindings_bls12_381):
  genBindingsField(bls12_381_fr)
  genBindingsField(bls12_381_fp)
  genBindingsFieldSqrt(bls12_381_fp)
  genBindingsExtField(bls12_381_fp2)
  genBindingsExtFieldSqrt(bls12_381_fp2)
  genBindings_EC_ShortW_Affine(bls12_381_ec_g1_aff, bls12_381_fp)
  genBindings_EC_ShortW_NonAffine(bls12_381_ec_g1_jac, bls12_381_ec_g1_aff, bls12_381_fp)
  genBindings_EC_ShortW_NonAffine(bls12_381_ec_g1_prj, bls12_381_ec_g1_aff, bls12_381_fp)
  genBindings_EC_ShortW_Affine(bls12_381_ec_g2_aff, bls12_381_fp2)
  genBindings_EC_ShortW_NonAffine(bls12_381_ec_g2_jac, bls12_381_ec_g2_aff, bls12_381_fp2)
  genBindings_EC_ShortW_NonAffine(bls12_381_ec_g2_prj, bls12_381_ec_g2_aff, bls12_381_fp2)

# ----------------------------------------------------------

type
  bn254_snarks_fr = Fr[BN254_Snarks]
  bn254_snarks_fp = Fp[BN254_Snarks]
  bn254_snarks_fp2 = Fp2[BN254_Snarks]
  bn254_snarks_ec_g1_aff = ECP_ShortW_Aff[Fp[BN254_Snarks], G1]
  bn254_snarks_ec_g1_jac = ECP_ShortW_Jac[Fp[BN254_Snarks], G1]
  bn254_snarks_ec_g1_prj = ECP_ShortW_Prj[Fp[BN254_Snarks], G1]
  bn254_snarks_ec_g2_aff = ECP_ShortW_Aff[Fp2[BN254_Snarks], G2]
  bn254_snarks_ec_g2_jac = ECP_ShortW_Jac[Fp2[BN254_Snarks], G2]
  bn254_snarks_ec_g2_prj = ECP_ShortW_Prj[Fp2[BN254_Snarks], G2]

collectBindings(cBindings_bn254_snarks):
  genBindingsField(bn254_snarks_fr)
  genBindingsField(bn254_snarks_fp)
  genBindingsFieldSqrt(bn254_snarks_fp)
  genBindingsExtField(bn254_snarks_fp2)
  genBindingsExtFieldSqrt(bn254_snarks_fp2)
  genBindings_EC_ShortW_Affine(bn254_snarks_ec_g1_aff, bn254_snarks_fp)
  genBindings_EC_ShortW_NonAffine(bn254_snarks_ec_g1_jac, bn254_snarks_ec_g1_aff, bn254_snarks_fp)
  genBindings_EC_ShortW_NonAffine(bn254_snarks_ec_g1_prj, bn254_snarks_ec_g1_aff, bn254_snarks_fp)
  genBindings_EC_ShortW_Affine(bn254_snarks_ec_g2_aff, bn254_snarks_fp2)
  genBindings_EC_ShortW_NonAffine(bn254_snarks_ec_g2_jac, bn254_snarks_ec_g2_aff, bn254_snarks_fp2)
  genBindings_EC_ShortW_NonAffine(bn254_snarks_ec_g2_prj, bn254_snarks_ec_g2_aff, bn254_snarks_fp2)

# ----------------------------------------------------------

type
  pallas_fr = Fr[Pallas]
  pallas_fp = Fp[Pallas]
  pallas_ec_aff = ECP_ShortW_Aff[Fp[Pallas], G1]
  pallas_ec_jac = ECP_ShortW_Jac[Fp[Pallas], G1]
  pallas_ec_prj = ECP_ShortW_Prj[Fp[Pallas], G1]

collectBindings(cBindings_pallas):
  genBindingsField(pallas_fr)
  genBindingsField(pallas_fp)
  genBindingsFieldSqrt(pallas_fp)
  genBindings_EC_ShortW_Affine(pallas_ec_aff, pallas_fp)
  genBindings_EC_ShortW_NonAffine(pallas_ec_jac, pallas_ec_aff, pallas_fp)
  genBindings_EC_ShortW_NonAffine(pallas_ec_prj, pallas_ec_aff, pallas_fp)

type
  vesta_fr = Fr[Vesta]
  vesta_fp = Fp[Vesta]
  vesta_ec_aff = ECP_ShortW_Aff[Fp[Vesta], G1]
  vesta_ec_jac = ECP_ShortW_Jac[Fp[Vesta], G1]
  vesta_ec_prj = ECP_ShortW_Prj[Fp[Vesta], G1]

collectBindings(cBindings_vesta):
  genBindingsField(vesta_fr)
  genBindingsField(vesta_fp)
  genBindingsFieldSqrt(vesta_fp)
  genBindings_EC_ShortW_Affine(vesta_ec_aff, vesta_fp)
  genBindings_EC_ShortW_NonAffine(vesta_ec_jac, vesta_ec_aff, vesta_fp)
  genBindings_EC_ShortW_NonAffine(vesta_ec_prj, vesta_ec_aff, vesta_fp)

# ----------------------------------------------------------
