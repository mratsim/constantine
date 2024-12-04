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

import
  ./macro_curves_bindings,
  ./c_curve_decls,
  ./c_curve_decls_parallel
export c_curve_decls, c_curve_decls_parallel

type
  big253 = BigInt[253]
  big254 = BigInt[254]
  big255 = BigInt[255]
  big381 = BigInt[381]

collectBindings(cBindings_big):
  genBindingsBig(big253)
  genBindingsBig(big254)
  genBindingsBig(big255)
  genBindingsBig(big381)

# ----------------------------------------------------------

type
  bls12_381_fr = Fr[BLS12_381]
  bls12_381_fp = Fp[BLS12_381]
  bls12_381_fp2 = Fp2[BLS12_381]
  bls12_381_g1_aff = EC_ShortW_Aff[Fp[BLS12_381], G1]
  bls12_381_g1_jac = EC_ShortW_Jac[Fp[BLS12_381], G1]
  bls12_381_g1_prj = EC_ShortW_Prj[Fp[BLS12_381], G1]
  bls12_381_g2_aff = EC_ShortW_Aff[Fp2[BLS12_381], G2]
  bls12_381_g2_jac = EC_ShortW_Jac[Fp2[BLS12_381], G2]
  bls12_381_g2_prj = EC_ShortW_Prj[Fp2[BLS12_381], G2]

collectBindings(cBindings_bls12_381):
  genBindingsField(big255, bls12_381_fr)
  genBindingsField(big381, bls12_381_fp)
  genBindingsFieldSqrt(bls12_381_fp)
  genBindingsExtField(bls12_381_fp2)
  genBindingsExtFieldSqrt(bls12_381_fp2)
  genBindings_EC_ShortW_Affine(bls12_381_g1_aff, bls12_381_fp)
  genBindings_EC_ShortW_NonAffine(bls12_381_g1_jac, bls12_381_g1_aff, big255, bls12_381_fr)
  genBindings_EC_ShortW_NonAffine(bls12_381_g1_prj, bls12_381_g1_aff, big255, bls12_381_fr)
  genBindings_EC_ShortW_Affine(bls12_381_g2_aff, bls12_381_fp2)
  genBindings_EC_ShortW_NonAffine(bls12_381_g2_jac, bls12_381_g2_aff, big255, bls12_381_fr)
  genBindings_EC_ShortW_NonAffine(bls12_381_g2_prj, bls12_381_g2_aff, big255, bls12_381_fr)
  genBindings_EC_hash_to_curve(bls12_381_g1_aff, sswu, sha256, k = 128)
  genBindings_EC_hash_to_curve(bls12_381_g1_jac, sswu, sha256, k = 128)
  genBindings_EC_hash_to_curve(bls12_381_g1_prj, sswu, sha256, k = 128)
  genBindings_EC_hash_to_curve(bls12_381_g2_aff, sswu, sha256, k = 128)
  genBindings_EC_hash_to_curve(bls12_381_g2_jac, sswu, sha256, k = 128)
  genBindings_EC_hash_to_curve(bls12_381_g2_prj, sswu, sha256, k = 128)

collectBindings(cBindings_bls12_381_parallel):
  genParallelBindings_EC_ShortW_NonAffine(bls12_381_g1_jac, bls12_381_g1_aff, bls12_381_fr)
  genParallelBindings_EC_ShortW_NonAffine(bls12_381_g1_prj, bls12_381_g1_aff, bls12_381_fr)
# ----------------------------------------------------------

type
  bn254_snarks_fr = Fr[BN254_Snarks]
  bn254_snarks_fp = Fp[BN254_Snarks]
  bn254_snarks_fp2 = Fp2[BN254_Snarks]
  bn254_snarks_g1_aff = EC_ShortW_Aff[Fp[BN254_Snarks], G1]
  bn254_snarks_g1_jac = EC_ShortW_Jac[Fp[BN254_Snarks], G1]
  bn254_snarks_g1_prj = EC_ShortW_Prj[Fp[BN254_Snarks], G1]
  bn254_snarks_g2_aff = EC_ShortW_Aff[Fp2[BN254_Snarks], G2]
  bn254_snarks_g2_jac = EC_ShortW_Jac[Fp2[BN254_Snarks], G2]
  bn254_snarks_g2_prj = EC_ShortW_Prj[Fp2[BN254_Snarks], G2]

collectBindings(cBindings_bn254_snarks):
  genBindingsField(big254, bn254_snarks_fr)
  genBindingsField(big254, bn254_snarks_fp)
  genBindingsFieldSqrt(bn254_snarks_fp)
  genBindingsExtField(bn254_snarks_fp2)
  genBindingsExtFieldSqrt(bn254_snarks_fp2)
  genBindings_EC_ShortW_Affine(bn254_snarks_g1_aff, bn254_snarks_fp)
  genBindings_EC_ShortW_NonAffine(bn254_snarks_g1_jac, bn254_snarks_g1_aff, big254, bn254_snarks_fr)
  genBindings_EC_ShortW_NonAffine(bn254_snarks_g1_prj, bn254_snarks_g1_aff, big254, bn254_snarks_fr)
  genBindings_EC_ShortW_Affine(bn254_snarks_g2_aff, bn254_snarks_fp2)
  genBindings_EC_ShortW_NonAffine(bn254_snarks_g2_jac, bn254_snarks_g2_aff, big254, bn254_snarks_fr)
  genBindings_EC_ShortW_NonAffine(bn254_snarks_g2_prj, bn254_snarks_g2_aff, big254, bn254_snarks_fr)
  genBindings_EC_hash_to_curve(bn254_snarks_g1_aff, svdw, sha256, k = 128)
  genBindings_EC_hash_to_curve(bn254_snarks_g1_jac, svdw, sha256, k = 128)
  genBindings_EC_hash_to_curve(bn254_snarks_g1_prj, svdw, sha256, k = 128)
  genBindings_EC_hash_to_curve(bn254_snarks_g2_aff, svdw, sha256, k = 128)
  genBindings_EC_hash_to_curve(bn254_snarks_g2_jac, svdw, sha256, k = 128)
  genBindings_EC_hash_to_curve(bn254_snarks_g2_prj, svdw, sha256, k = 128)

collectBindings(cBindings_bn254_snarks_parallel):
  genParallelBindings_EC_ShortW_NonAffine(bn254_snarks_g1_jac, bn254_snarks_g1_aff, bn254_snarks_fr)
  genParallelBindings_EC_ShortW_NonAffine(bn254_snarks_g1_prj, bn254_snarks_g1_aff, bn254_snarks_fr)

# ----------------------------------------------------------

type
  pallas_fr = Fr[Pallas]
  pallas_fp = Fp[Pallas]
  pallas_ec_aff = EC_ShortW_Aff[Fp[Pallas], G1]
  pallas_ec_jac = EC_ShortW_Jac[Fp[Pallas], G1]
  pallas_ec_prj = EC_ShortW_Prj[Fp[Pallas], G1]

collectBindings(cBindings_pallas):
  genBindingsField(big255, pallas_fr)
  genBindingsField(big255, pallas_fp)
  genBindingsFieldSqrt(pallas_fp)
  genBindings_EC_ShortW_Affine(pallas_ec_aff, pallas_fp)
  genBindings_EC_ShortW_NonAffine(pallas_ec_jac, pallas_ec_aff, big255, pallas_fr)
  genBindings_EC_ShortW_NonAffine(pallas_ec_prj, pallas_ec_aff, big255, pallas_fr)

collectBindings(cBindings_pallas_parallel):
  genParallelBindings_EC_ShortW_NonAffine(pallas_ec_jac, pallas_ec_aff, pallas_fr)
  genParallelBindings_EC_ShortW_NonAffine(pallas_ec_prj, pallas_ec_aff, pallas_fr)

type
  vesta_fr = Fr[Vesta]
  vesta_fp = Fp[Vesta]
  vesta_ec_aff = EC_ShortW_Aff[Fp[Vesta], G1]
  vesta_ec_jac = EC_ShortW_Jac[Fp[Vesta], G1]
  vesta_ec_prj = EC_ShortW_Prj[Fp[Vesta], G1]

collectBindings(cBindings_vesta):
  genBindingsField(big255, vesta_fr)
  genBindingsField(big255, vesta_fp)
  genBindingsFieldSqrt(vesta_fp)
  genBindings_EC_ShortW_Affine(vesta_ec_aff, vesta_fp)
  genBindings_EC_ShortW_NonAffine(vesta_ec_jac, vesta_ec_aff, big255, vesta_fr)
  genBindings_EC_ShortW_NonAffine(vesta_ec_prj, vesta_ec_aff, big255, vesta_fr)

collectBindings(cBindings_vesta_parallel):
  genParallelBindings_EC_ShortW_NonAffine(vesta_ec_jac, vesta_ec_aff, vesta_fr)
  genParallelBindings_EC_ShortW_NonAffine(vesta_ec_prj, vesta_ec_aff, vesta_fr)

# ----------------------------------------------------------

type 
  banderwagon_fr = Fr[Banderwagon]
  banderwagon_fp = Fp[Banderwagon]
  banderwagon_twedw_aff = EC_TwEdw_Aff[Fp[Banderwagon]]
  banderwagon_twedw_prj = EC_TwEdw_Prj[Fp[Banderwagon]]

collectBindings(cBindings_banderwagon):
  genBindingsField(big253, banderwagon_fr)
  genBindingsField(big255, banderwagon_fp)
  genBindingsFieldSqrt(banderwagon_fp)
  genBindings_EC_TwEdw_Affine(banderwagon_twedw_aff, banderwagon_fp)
  genBindings_EC_TwEdw_Projective(banderwagon_twedw_prj, banderwagon_twedw_aff, big253, banderwagon_fr)