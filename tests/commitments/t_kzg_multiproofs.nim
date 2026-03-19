# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/named/algebras,
  constantine/math/[ec_shortweierstrass, extension_fields],
  constantine/math/polynomials/[polynomials, fft],
  constantine/math/arithmetic/finite_fields,
  constantine/commitments/kzg_multiproofs,
  constantine/commitments/kzg,
  constantine/math/io/io_fields,
  ./trusted_setup_generator

from trusted_setup_generator import
  EC_G1_Aff, EC_G1_Jac, EC_G2_Aff

type FK20TauExt[N, L, CDS: static int, Name: static Algebra] = array[L, array[CDS, EC_ShortW_Jac[Fp[Name], G1]]]

func pow*(omegaMax: Fr[BLS12_381], domainPos: uint32): Fr[BLS12_381] =
  var exp: Fr[BLS12_381]
  exp.fromUint(uint64(domainPos))
  result = omegaMax
  result.pow(exp)

func computeYsAtCoset*[L: static int](
       ys: var array[L, Fr[BLS12_381]],
       poly: PolynomialCoef,
       x, lthRoot: Fr[BLS12_381]) =
  ## Compute polynomial evaluations at coset x * omega^j for j in [0, L)
  ## where omega is the L-th root of unity (lthRoot)
  var omegaPow: Fr[BLS12_381]
  omegaPow.setOne()
  for i in 0 ..< L:
    var z: Fr[BLS12_381]
    z.prod(x, omegaPow)
    evalPolyAt(ys[i], poly, z)
    var nextOmega: Fr[BLS12_381]
    nextOmega.prod(omegaPow, lthRoot)
    omegaPow = nextOmega

proc testFK20SingleProofs() =
  ## Test FK20 single-proof DA matching c-kzg's fk_single test
  echo "Testing FK20 single proofs (c-kzg fk_single pattern)..."

  const N = 16
  const CDS = 32  # 2*N for DA extension
  const maxWidth = CDS  # For single proof, maxWidth = CDS
  const L = 1
  const tauHex = "0xa473319528c8b6ea4d08cc531800000000000000000000000000000000000000"

  let setup = gen_setup(N, L, maxWidth, tauHex)

  var tauExtFftArray: array[L, array[CDS, EC_G1_Jac]]
  getTauExtFftArray(tauExtFftArray, setup.powers_of_tau_G1, setup.circulantDomain.rootsOfUnity[1])

  var fk20Proofs: array[CDS, EC_G1_Aff]
  kzg_coset_prove(tauExtFftArray, setup.circulantDomain, fk20Proofs, setup.poly)

  # Compute commitment using pre-generated BigInt polynomial
  var commitmentAff: EC_ShortW_Aff[Fp[BLS12_381], G1]
  kzg_commit(setup.powers_of_tau_G1, commitmentAff, setup.polyBig)

  # Verify each proof using kzg_verify (single proof case)
  var verified = 0
  for i in 0 ..< CDS:
    let z = setup.circulantDomain.rootsOfUnity[i]
    var y: Fr[BLS12_381]
    evalPolyAt(y, setup.poly, z)

    let ok = kzg_verify(
      commitmentAff, z.toBig(), y.toBig(),
      fk20Proofs[i], setup.powers_of_tau_G2.coefs[1])

    if ok:
      inc verified
    else:
      echo "  FAILED at i=", i

  echo "  Verified ", verified, "/", CDS, " proofs"
  doAssert verified == CDS, "Not all FK20 proofs verified"
  echo "✓ FK20 single proofs test PASSED"

proc testFK20MultiProofs*(L: static int) =
  ## Test FK20 multi-proof with L > 1 (EIP-7594 pattern)
  ## Uses c-kzg convention: domain of order 2*N for proof gen, bit-reversed proofs/ys
  ## Constraint: N == L * (CDS/2), so for given L we need appropriate N and CDS
  echo "Testing FK20 multi-proofs (L = ", L, ")..."

  when L == 2:
    const N = 16
    const CDS = 16
    const maxWidth = 32
  when L == 4:
    const N = 32
    const CDS = 16
    const maxWidth = 64
  const tauHex = "0xa473319528c8b6ea4d08cc531800000000000000000000000000000000000000"

  let setup = gen_setup(N, L, maxWidth, tauHex)

  var tauExtFftArray: array[L, array[CDS, EC_G1_Jac]]
  getTauExtFftArray(tauExtFftArray, setup.powers_of_tau_G1, setup.circulantDomain.rootsOfUnity[1])

  var fk20Proofs: array[CDS, EC_G1_Aff]
  kzg_coset_prove(
    tauExtFftArray, setup.circulantDomain, fk20Proofs, setup.poly)

  fk20Proofs.bit_reversal_permutation()

  var commitmentAff: EC_ShortW_Aff[Fp[BLS12_381], G1]
  kzg_commit(setup.powers_of_tau_G1, commitmentAff, setup.polyBig)

  let lthRoot = setup.circulantDomain.rootsOfUnity[1] ~^ uint64(CDS div L)

  const chunkCount = N div L  # 8
  const numProofs = 2 * chunkCount  # 16
  const nBits = 4  # log2(16) = 4 (for bit-reversing position)
  var verified = 0
  for pos in 0'u32 ..< numProofs:
    let domainPos = reverseBits(pos, nBits)
    let x = setup.omegaMax ~^ domainPos

    var ys: array[L, Fr[BLS12_381]]
    computeYsAtCoset(ys, setup.poly, x, lthRoot)

    var powers_of_tau_cell: PolynomialCoef[L, EC_G1_Aff]
    for j in 0 ..< L:
      powers_of_tau_cell.coefs[j] = setup.powers_of_tau_G1.coefs[j]

    let ok = kzg_coset_verify[static(L), BLS12_381](
      commitmentAff, fk20Proofs[pos], x, ys,
      powers_of_tau_cell, setup.powers_of_tau_G2.coefs, lthRoot,
      N)

    if ok:
      inc verified
    else:
      echo "  FAILED at pos=", pos

  echo "  Verified ", verified, "/", numProofs, " proofs"
  doAssert verified == numProofs, "Not all FK20 multi-proofs verified"
  echo "✓ FK20 multi-proofs test PASSED"

proc computeQuotientPolyCoef[N: static int, Field](
       quotient: var PolynomialCoef[N, Field],
       poly: PolynomialCoef[N, Field],
       z: Field) =
  ## Compute quotient polynomial q(X) = (p(X) - p(z)) / (X - z) using synthetic division.
  ## Works with coefficient form polynomials.
  var p_z: Field
  evalPolyAt(p_z, poly, z)

  # Synthetic division (Horner's method)
  # q[n-2] = p[n-1]
  # q[i-1] = p[i] + z * q[i] for i from n-2 down to 0
  quotient.coefs[N-2] = poly.coefs[N-1]
  for i in countdown(N-2, 1):
    quotient.coefs[i-1].prod(poly.coefs[i], z)
    quotient.coefs[i-1].sum(quotient.coefs[i-1], poly.coefs[i])

  # Handle the constant term adjustment for (p(X) - p(z))
  # The remainder should be p(z), so we need to subtract it
  # But since we're dividing (p(X) - p(z)), the division is exact
  # and the quotient coefficients are computed correctly above

  # Zero out the last coefficient (degree reduces by 1)
  quotient.coefs[N-1].setZero()

proc testNonOptimizedCosetProofs*(L: static int) =
  ## Test the non-optimized (schoolbook) KZG coset proof function
  ## and verify it produces the same results as FK20
  echo "Testing non-optimized KZG coset proofs (L = ", L, ")..."

  when L == 2:
    const N = 16
    const CDS = 16
    const maxWidth = 32
  when L == 4:
    const N = 32
    const CDS = 16
    const maxWidth = 64
  const tauHex = "0xa473319528c8b6ea4d08cc531800000000000000000000000000000000000000"

  let setup = gen_setup(N, L, maxWidth, tauHex)

  var tauExtFftArray: array[L, array[CDS, EC_ShortW_Jac[Fp[BLS12_381], G1]]]
  getTauExtFftArray(tauExtFftArray, setup.powers_of_tau_G1, setup.circulantDomain.rootsOfUnity[1])

  var fk20Proofs: array[CDS, EC_ShortW_Aff[Fp[BLS12_381], G1]]
  kzg_coset_prove(
    tauExtFftArray, setup.circulantDomain, fk20Proofs, setup.poly)

  fk20Proofs.bit_reversal_permutation()

  var commitmentAff: EC_ShortW_Aff[Fp[BLS12_381], G1]
  kzg_commit(setup.powers_of_tau_G1, commitmentAff, setup.polyBig)

  let lthRoot = setup.circulantDomain.rootsOfUnity[1] ~^ uint64(CDS div L)

  const chunkCount = N div L
  const numProofs = 2 * chunkCount
  const nBits = 4

  var matching = 0
  var naiveVerified = 0
  var fk20Verified = 0
  for pos in 0'u32 ..< numProofs:
    let domainPos = reverseBits(pos, nBits)
    let x = setup.omegaMax ~^ domainPos

    var fk20Proof: EC_ShortW_Aff[Fp[BLS12_381], G1]
    fk20Proof = fk20Proofs[pos]

    var nonOptProof: EC_ShortW_Aff[Fp[BLS12_381], G1]
    var ys: array[L, Fr[BLS12_381]]
    kzg_coset_prove_naive(
      nonOptProof, ys, setup.poly, x, lthRoot, setup.powers_of_tau_G1)

    if (fk20Proof == nonOptProof).bool:
      inc matching
    else:
      echo "  MISMATCH at pos=", pos

    var powers_of_tau_cell: PolynomialCoef[L, EC_ShortW_Aff[Fp[BLS12_381], G1]]
    for j in 0 ..< L:
      powers_of_tau_cell.coefs[j] = setup.powers_of_tau_G1.coefs[j]

    let okNaive = kzg_coset_verify[static(L), BLS12_381](
      commitmentAff, nonOptProof, x, ys,
      powers_of_tau_cell, setup.powers_of_tau_G2.coefs, lthRoot,
      N)
    if okNaive:
      inc naiveVerified

    let okFK20 = kzg_coset_verify[static(L), BLS12_381](
      commitmentAff, fk20Proof, x, ys,
      powers_of_tau_cell, setup.powers_of_tau_G2.coefs, lthRoot,
      N)
    if okFK20:
      inc fk20Verified

  echo "  Matching FK20 proofs: ", matching, "/", numProofs
  echo "  Naive verified: ", naiveVerified, "/", numProofs
  echo "  FK20 verified: ", fk20Verified, "/", numProofs
  doAssert matching == numProofs, "Non-optimized proofs don't match FK20"
  doAssert naiveVerified == numProofs, "Naive proofs don't verify"
  doAssert fk20Verified == numProofs, "FK20 proofs don't verify"
  echo "✓ Non-optimized KZG coset proofs test PASSED"

when isMainModule:
  echo "========================================"
  echo "    KZG Multi-Proof Tests"
  echo "========================================\n"

  echo "Single proof per coset ... "
  testFK20SingleProofs()

  echo "---------------------------"

  echo "Multiple proofs per coset (L=2) ... "
  testFK20MultiProofs(2)

  echo "---------------------------"

  echo "Multiple proofs per coset (L=4) ... "
  testFK20MultiProofs(4)

  echo "---------------------------"

  echo "Non-optimized coset proofs (L=2) ... "
  testNonOptimizedCosetProofs(2)

  echo "---------------------------"

  echo "Non-optimized coset proofs (L=4) ... "
  testNonOptimizedCosetProofs(4)

  echo "\n========================================"
  echo "    All KZG multiproofs tests PASSED ✓"
  echo "========================================"