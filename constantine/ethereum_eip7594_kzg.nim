import 
  std/typetraits,

  constantine/named/algebras,
  ./math/io/[io_bigints, io_fields],
  ./math/[ec_shortweierstrass, arithmetic, extension_fields],
  ./math/arithmetic/limbs_montgomery,
  ./math/polynomials/polynomials,
  ./math/arithmetic/bigints,
  ./commitments/kzg,
  ./hashes,
  ./platforms/[abstractions, allocs],
  ./serialization/[codecs_status_codes, codecs_bls12_381, endians],
  ./ethereum_eip4844_kzg
  
const RANDOM_CHALLENGE_KZG_CELL_BATCH_DOMAIN=asBytes"RCKZGCBATCH__V1_"
const FIELD_ELEMENTS_PER_BLOB=128
const FIELD_ELEMENTS_PER_CELL=64
const BYTES_PER_FIELD_ELEMENT=64

# Derived
# ------------------------------------------------------------
const BYTES_PER_CELL= FIELD_ELEMENTS_PER_CELL*BYTES_PER_FIELD_ELEMENT
const FIELD_ELEMENTS_PER_EXT_BLOB=2*FIELD_ELEMENTS_PER_BLOB

# The number of cells in an extended blob
const CELLS_PER_EXT_BLOB=int(FIELD_ELEMENTS_PER_EXT_BLOB/FIELD_ELEMENTS_PER_CELL)


type 
  # A polynomial in coefficient form
  PolyCoeff = PolynomialCoef[FIELD_ELEMENTS_PER_EXT_BLOB,Fr[BLS12_381]]
  # The evaluation domain of a cell
  Coset* = array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]] 
  # The internal representation of a cell (the evaluations over its Coset)
  CosetEvals* = array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]]
  # The unit of blob data that can come with its own KZG proof
  Cell* = array[BYTES_PER_CELL, byte]
  # Validation: x < CELLS_PER_EXT_BLOB
  CellIndex* = uint64 

# from eip4844, import
# bytes_to_bls_field
# bls_field_to_bytes

func cell_to_coset_evals(evals:var CosetEvals,cell: Cell): CttCodecEccStatus=
  # Convert an untrusted ``Cell`` into a trusted ``CosetEvals``
  var temp: Fr[BLS12_381]
  let view = cast[array[FIELD_ELEMENTS_PER_CELL, array[32, byte]]](cell.unsafeAddr)
  for i in 0..<FIELD_ELEMENTS_PER_CELL:
    let status = bytes_to_bls_field(temp,view[i])
    if status notin {cttCodecScalar_Success, cttCodecScalar_Zero}:
      return cttCodecEcc_PointNotOnCurve
    evals[i]=temp
  return cttCodecEcc_Success



func coset_evals_to_cell(dst: var Cell,coset_evals: CosetEvals): CttCodecEccStatus=
    # Convert a trusted ``CosetEval`` into an untrusted ``Cell``.
    let temp = allocHeapAligned(array[FIELD_ELEMENTS_PER_CELL, array[32,byte]], 64)
    for i in 0..<FIELD_ELEMENTS_PER_CELL:
      temp[i].fromDigest(cosetEvals[i])
 
    dst= cast[Cell](temp.unsafeAddr)

    return  cttCodecEcc_Success


# to do
func compute_kzg_proof_multi_impl(dst:var (KZGProof, CosetEvals),poly_coeff: PolyCoeff,zs: Coset)=
    # Compute a KZG multi-evaluation proof for a set of `k` points.

    # This is done by committing to the following quotient polynomial:
    #     Q(X) = f(X) - I(X) / Z(X)
    # Where:
    #     - I(X) is the degree `k-1` polynomial that agrees with f(x) at all `k` points
    #     - Z(X) is the degree `k` polynomial that evaluates to zero on all `k` points

    # We further note that since the degree of I(X) is less than the degree of Z(X),
    # the computation can be simplified in monomial form to Q(X) = f(X) / Z(X)
    

    # For all points, compute the evaluation of those points

    for i in z:
      ys[i]=evaluate_polynomialcoeff(polynomial_coeff, z[i])

    # Compute Z(X)
    denominator_poly = vanishing_polynomialcoeff(zs)

    # Compute the quotient polynomial directly in monomial form
    quotient_polynomial = divide_polynomialcoeff(polynomial_coeff, denominator_poly)

    return KZGProof(g1_lincomb(KZG_SETUP_G1_MONOMIAL[:len(quotient_polynomial)], quotient_polynomial)), ys


# to do
func coset_for_cell(var dst: Coset,cell_index: CellIndex)=
    # Get the coset for a given ``cell_index``.
    # Precisely, consider the group of roots of unity of order FIELD_ELEMENTS_PER_CELL * CELLS_PER_EXT_BLOB.
    # Let G = {1, g, g^2, ...} denote its subgroup of order FIELD_ELEMENTS_PER_CELL.
    # Then, the coset is defined as h * G = {h, hg, hg^2, ...}.
    # This function, returns the coset.
  static:
    doAssert cell_index < CELLS_PER_EXT_BLOB
    # confirm if in load_ckzg4844 this is already pre-computed
    (roots_of_unity_brp.computeRootsOfUnity(FIELD_ELEMENTS_PER_EXT_BLOB)).bit_reversal_permutation()
    return Coset(roots_of_unity_brp[FIELD_ELEMENTS_PER_CELL * cell_index:FIELD_ELEMENTS_PER_CELL * (cell_index + 1)])

#to do
func compute_cells_and_kzg_proofs_polynomialcoeff(dst: var (array[CELLS_PER_EXT_BLOB, Cell],array[CELLS_PER_EXT_BLOB,KZGProof]), poly_coeff: PolyCoeff)=
    # Helper function which computes cells/proofs for a polynomial in coefficient form.
    var 
      coset: array[CELLS_PER_EXT_BLOB, Coset]
      cells: array[CELLS_PER_EXT_BLOB, Cell]
      proofs:  array[CELLS_PER_EXT_BLOB,KZGProof]

    for i in range(CELLS_PER_EXT_BLOB):
        coset[i].coset_for_cell(CellIndex(i))
        var ys:auto
        (ys,proofs[i]).compute_kzg_proof_multi_impl(polynomial_coeff, coset[i])
        cells[i].coset_evals_to_cell(ys)
        proofs[i]=proof

    dst=(cells, proofs)
    return 

#to do
# public api method
func compute_cells_and_kzg_proofs(dst: var (array[CELLS_PER_EXT_BLOB,Cell],array[CELLS_PER_EXT_BLOB,KZGProof]), blob: Blob) =
    # Compute all the cell proofs for an extended blob. This is an inefficient O(n^2) algorithm,
    # for performant implementation the FK20 algorithm that runs in O(n log n) should be used instead.
    assert len(blob) == BYTES_PER_BLOB
    
    let poly = allocHeapAligned(PolynomialEval[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381].getBigInt()], 64)
    poly.blob_to_bigint_polynomial(blob)
    poly_coeff.polynomial_eval_to_coeff(poly)
    dst.compute_cells_and_kzg_proofs_polynomialcoeff(poly_coeff)
    return 
