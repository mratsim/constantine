import ../../math/[arithmetic, extension_fields]
import ../../math/io/[io_bigints, io_fields, io_ec, io_extfields]
import ../../platforms/abstractions
import ../../named/[algebras, properties_fields, properties_curves]
import ../../math/elliptic/[ec_shortweierstrass_affine, ec_shortweierstrass_jacobian, ec_scalar_mul, ec_multi_scalar_mul, ec_scalar_mul_vartime]

## NOTE: These constructors for ...
proc toFp*[Name: static Algebra](x: seq[byte], isMont = true): Fp[Name] =
  let b = matchingBigInt(Name).unmarshal(x.toOpenArray(0, x.len - 1), littleEndian)
  if isMont:
    var bN: typeof(b)
    bN.fromMont(b, Fp[Name].getModulus(), Fp[Name].getNegInvModWord(), Fp[Name].getSpareBits())
    result.fromBig(bN)
  else:
    result.fromBig(b)

proc toFr*[Name: static Algebra](x: seq[byte], isMont = true, isDoubleMont = false): Fr[Name] =
  let b = matchingOrderBigInt(Name).unmarshal(x.toOpenArray(0, x.len - 1), littleEndian)
  if isMont:
    var bN: typeof(b)
    bN.fromMont(b, Fr[Name].getModulus(), Fr[Name].getNegInvModWord(), Fr[Name].getSpareBits())
    result.fromBig(bN)
  elif isDoubleMont:
    var bN: typeof(b)
    bN.fromMont(b, Fr[Name].getModulus(), Fr[Name].getNegInvModWord(), Fr[Name].getSpareBits())
    var bNN: typeof(b)
    bNN.fromMont(bN, Fr[Name].getModulus(), Fr[Name].getNegInvModWord(), Fr[Name].getSpareBits())
    result.fromBig(bNN)
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

## Currently not used
proc randomFieldElement*[Name: static Algebra](): Fp[Name] =
  ## random element in ~Fp[T]~
  let m = Fp[Name].getModulus()
  var b: matchingBigInt(Name)

  while b.isZero().bool or (b > m).bool:
    assert b.limbs.sysrand()
  result.fromBig(b)
