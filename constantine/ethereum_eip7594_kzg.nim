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
  ./commitments_setups/ethereum_kzg_srs
  

export trusted_setup_load, trusted_setup_delete, TrustedSetupFormat, TrustedSetupStatus, EthereumKZGContext


####

const BLS_MODULUS= 1234
const BYTES_PER_FIELD_ELEMENT= 96
const RANDOM_CHALLENGE_KZG_CELL_BATCH_DOMAIN=asBytes"RCKZGCBATCH__V1_"
const FIELD_ELEMENTS_PER_BLOB=128
#Number of field elements in a cell
const FIELD_ELEMENTS_PER_CELL =64
#Number of field elements in a Reed-Solomon extended blob
const FIELD_ELEMENTS_PER_EXT_BLOB=2*FIELD_ELEMENTS_PER_BLOB
#The number of bytes in a cell
const BYTES_PER_CELL=FIELD_ELEMENTS_PER_CELL * BYTES_PER_FIELD_ELEMENT
#The number of cells in an extended blob
const CELLS_PER_EXT_BLOB=int(FIELD_ELEMENTS_PER_EXT_BLOB/FIELD_ELEMENTS_PER_CELL)


type 
  # A polynomial in coefficient form
  PolyCoeff = PolynomialCoef[FIELD_ELEMENTS_PER_EXT_BLOB,Fr[BLS12_381]]
  # The evaluation domain of a cell
  Coset* = distinct array[FIELD_ELEMENTS_PER_CELL,EC_ShortW_Aff[Fr[BLS12_381], G2]] 
  # The internal representation of a cell (the evaluations over its Coset)
  CosetEvals* = distinct array[FIELD_ELEMENTS_PER_CELL, EC_ShortW_Aff[Fr[BLS12_381], G2]]
  # The unit of blob data that can come with its own KZG proof
  Cell* = array[BYTES_PER_CELL, byte]
  # Validation: x < CELLS_PER_EXT_BLOB
  CellIndex* = uint64 





# from eip4844
func bytes_to_bls_field(dst: var Fr[BLS12_381], src: array[32, byte]): CttCodecScalarStatus =
  ## Convert untrusted bytes to a trusted and validated BLS scalar field element.
  ## This function does not accept inputs greater than the BLS modulus.
  var scalar {.noInit.}: Fr[BLS12_381].getBigInt()
  let status = scalar.deserialize_scalar(src)
  if status notin {cttCodecScalar_Success, cttCodecScalar_Zero}:
    return status
  dst.fromBig(scalar)
  return cttCodecScalar_Success

func bytes_to_bls_field(src: array[32, byte]) : Fr[BLS12_381] =
  ## Convert untrusted bytes to a trusted and validated BLS scalar field element.
  ## This function does not accept inputs greater than the BLS modulus.
  var result: Fr[BLS12_381]
  var scalar {.noInit.}: Fr[BLS12_381].getBigInt()
  discard scalar.deserialize_scalar(src)
  result.fromBig(scalar)


#
# Polynomial helper functions
#
func add_polynomial_coeff(a: PolyCoeff,b: PolyCoeff):PolyCoeff=
    # Sum the coefficient form polynomials ``a`` and ``b``.
  var
    longer: PolyCoeff
    shorter: PolyCoeff
  if len(a.coefs) >= len(b.coefs):
    longer = a
    shorter = b
  else:
    longer = b
    shorter = a

  for i in 0 ..< len(longer.coefs):
    result.coefs[i] = (longer.coefs[i] + (if i < len(shorter.coefs): shorter.coefs[i] else: 0)) mod BLS_MODULUS

func neg_polynomial_coeff(a: PolyCoeff): PolyCoeff=
    # Negative of coefficient form polynomial ``a``
    for i in 0..<len(a.coefs):
      result.coefs[i]=(BLS_MODULUS-a.coefs[i]) mod BLS_MODULUS

func multiply_polynomial_coeff(a: PolyCoeff, b: PolyCoeff):PolyCoeff=
  # Multiplies the coefficient form polynomials ``a`` and ``b``
  # assert len(a) + len(b) <= FIELD_ELEMENTS_PER_EXT_BLOB
  for i,coefA in a.coefs:
    for j,coefB in b.coefs:
      result.coefs[i+j] = (result.coefs[i+j]+coefA*coefB)mod BLS_MODULUS

func divide_polynomial_coeff(a:PolyCoeff,b:PolyCoeff):PolyCoeff=

  #Long polynomial division for two coefficient form polynomials ``a`` and ``b``
  var aCopy = a  # Make a copy since `a` is passed by reference
  var apos = len(a.coefs) - 1
  var bpos = len(b.coefs) - 1
  var diff = apos - bpos

  while diff>=0:
    var quot :Fr[BLS12_381] = div(a.coefs[apos], b.coefs[bpos]) #from deneb
    result.coefs[diff] = quot
    for i in countdown(bpos, 0):
      aCopy.coefs[diff+i]=(a.coefs[diff+i]-b.coefs[i]*quot+BLS_MODULUS)mod BLS_MODULUS
    apos -= 1
    diff -= 1

  for i in 0 ..< len(result.coefs):
    result.coefs[i] = result.coefs[i] mod BLS_MODULUS

  return result


## Lagrange interpolation: Finds the lowest degree polynomial that takes the value `ys[i]` at `xs[i]` for all i.
## Outputs a coefficient form polynomial. Leading coefficients may be zero.
func interpolate_polynomial_coeff(xs: Sequence[Fr[BLS12_381]], ys: Sequence[Fr[BLS12_381]]):PolynomialCoeff=
  assert len(xs) == len(ys)
  
  var r: PolynomialCoeff

  for i in 0 ..< len(xs):
    var temp: array[FIELD_ELEMENTS_PER_EXT_BLOB, Fr[BLS12_381]] = [ys[i]]
    var summand:PolyCoeff= temp & [0 | FIELD_ELEMENTS_PER_EXT_BLOB-1]
    for j in 0 ..< len(ys):
      if j != i:
        let weightAdjustment = bls_modular_inverse(int(xs[i]) - int(xs[j]))
        summand = multiply_polynomial_coeff(
          summand, [(BLS_MODULUS-int(weightAdjustment)*int(xs[j]))mod BLS_MODULUS,weightAdjustment]
        )
    r=add_polynomial_coeff(r, summand)

  return r



## useful for detecting if memory cleanup us necessary , and check the status of the execution of the function 
template checkReturn(evalExpr: CttCodecScalarStatus): untyped {.dirty.} =
  # Translate codec status code to KZG status code
  # Beware of resource cleanup like heap allocation, this can early exit the caller.
  block:
    let status = evalExpr # Ensure single evaluation
    case status
    of cttCodecScalar_Success:                          discard
    of cttCodecScalar_Zero:                             discard
    of cttCodecScalar_ScalarLargerThanCurveOrder:       return cttEthKzg_ScalarLargerThanCurveOrder

template checkReturn(evalExpr: CttCodecEccStatus): untyped {.dirty.} =
  # Translate codec status code to KZG status code
  # Beware of resource cleanup like heap allocation, this can early exit the caller.
  block:
    let status = evalExpr # Ensure single evaluation
    case status
    of cttCodecEcc_Success:                             discard
    of cttCodecEcc_InvalidEncoding:                     return cttEthKzg_EccInvalidEncoding
    of cttCodecEcc_CoordinateGreaterThanOrEqualModulus: return cttEthKzg_EccCoordinateGreaterThanOrEqualModulus
    of cttCodecEcc_PointNotOnCurve:                     return cttEthKzg_EccPointNotOnCurve
    of cttCodecEcc_PointNotInSubgroup:                  return cttEthKzg_EccPointNotInSubGroup
    of cttCodecEcc_PointAtInfinity:                     discard

template check(Section: untyped, evalExpr: CttCodecScalarStatus): untyped {.dirty.} =
  # Translate codec status code to KZG status code
  # Exit current code block
  block:
    let status = evalExpr # Ensure single evaluation
    case status
    of cttCodecScalar_Success:                          discard
    of cttCodecScalar_Zero:                             discard
    of cttCodecScalar_ScalarLargerThanCurveOrder:       result = cttEthKzg_ScalarLargerThanCurveOrder; break Section

template check(Section: untyped, evalExpr: CttCodecEccStatus): untyped {.dirty.} =
  # Translate codec status code to KZG status code
  # Exit current code block
  block:
    let status = evalExpr # Ensure single evaluation
    case status
    of cttCodecEcc_Success:                             discard
    of cttCodecEcc_InvalidEncoding:                     result = cttEthKzg_EccInvalidEncoding; break Section
    of cttCodecEcc_CoordinateGreaterThanOrEqualModulus: result = cttEthKzg_EccCoordinateGreaterThanOrEqualModulus; break Section
    of cttCodecEcc_PointNotOnCurve:                     result = cttEthKzg_EccPointNotOnCurve; break Section
    of cttCodecEcc_PointNotInSubgroup:                  result = cttEthKzg_EccPointNotInSubGroup; break Section
    of cttCodecEcc_PointAtInfinity:                     discard