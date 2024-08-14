import ../math/[arithmetic, extension_fields],
       ../math/io/[io_bigints, io_fields, io_ec, io_extfields],
       ../platforms/abstractions,
       ../named/[algebras, properties_fields, properties_curves],
       ../math/elliptic/[ec_shortweierstrass_affine, ec_shortweierstrass_jacobian, ec_scalar_mul, ec_multi_scalar_mul, ec_scalar_mul_vartime]

## Helper constructors for Fp / Fr elements used in Groth16 binary file parsers.
proc toFp*[Name: static Algebra](x: seq[byte], isMont = true): Fp[Name] =
  let b = matchingBigInt(Name).unmarshal(x.toOpenArray(0, x.len - 1), littleEndian)
  if isMont:
    var bN: typeof(b)
    bN.fromMont(b, Fp[Name].getModulus(), Fp[Name].getNegInvModWord(), Fp[Name].getSpareBits())
    result.fromBig(bN)
  else:
    result.fromBig(b)

proc toFr*[Name: static Algebra](x: seq[byte], isMont = true): Fr[Name] =
  let b = matchingOrderBigInt(Name).unmarshal(x.toOpenArray(0, x.len - 1), littleEndian)
  if isMont:
    var bN: typeof(b)
    bN.fromMont(b, Fr[Name].getModulus(), Fr[Name].getNegInvModWord(), Fr[Name].getSpareBits())
    result.fromBig(bN)
  else:
    result.fromBig(b)

proc toEcG1*[Name: static Algebra](s: seq[byte]): EC_ShortW_Aff[Fp[Name], G1] =
  let x = toFp[Name](s[0 .. 31])
  let y = toFp[Name](s[32 .. ^1])
  result.x = x
  result.y = y
  echo result.toHex()
  if not bool(result.isNeutral()):
    doAssert isOnCurve(result.x, result.y, G1).bool, "Input point is not on curve!"

proc toFp2*[Name: static Algebra](x: seq[byte]): Fp2[Name] =
  let c0 = toFp[Name](x[0 .. 31])
  let c1 = toFp[Name](x[32 .. 63])
  result.c0 = c0
  result.c1 = c1

proc toEcG2*[Name: static Algebra](s: seq[byte]): EC_ShortW_Aff[Fp2[Name], G2] =
  let x = toFp2[Name](s[0 .. 63])
  let y = toFp2[Name](s[64 .. ^1])
  result.x = x
  result.y = y
  if not bool(result.isNeutral()):
    doAssert isOnCurve(result.x, result.y, G2).bool, "Input point is not on curve!"

proc asEC*[Name: static Algebra](pts: seq[seq[byte]], _: typedesc[Fp[Name]]): seq[EC_ShortW_Aff[Fp[Name], G1]] =
  result = newSeq[EC_ShortW_Aff[Fp[Name], G1]](pts.len)
  for i, el in pts:
    result[i] = toEcG1[Name](el)

proc asEC2*[Name: static Algebra](pts: seq[seq[byte]], _: typedesc[Fp2[Name]]): seq[EC_ShortW_Aff[Fp2[Name], G2]] =
  result = newSeq[EC_ShortW_Aff[Fp2[Name], G2]](pts.len)
  for i, el in pts:
    result[i] = toEcG2[Name](el)

proc randomFieldElement*[Name: static Algebra](_: typedesc[Fr[Name]]): Fr[Name] =
  ## random element in ~Fr[Name]~
  let m = Fr[Name].getModulus()
  var b: matchingOrderBigInt(Name)

  while b.isZero().bool or (b > m).bool: ## XXX: or just truncate?
    assert b.limbs.sysrand()
  result.fromBig(b)
