# https://github.com/mratsim/constantine/issues/345

import constantine/math/arithmetic
import constantine/math/io/io_fields
import constantine/math/io/io_bigints
import constantine/named/algebras
import constantine/math/extension_fields/towers
import constantine/math/elliptic/ec_shortweierstrass_affine
import constantine/math/elliptic/ec_shortweierstrass_projective
import constantine/math/elliptic/ec_scalar_mul
import constantine/math/elliptic/ec_scalar_mul_vartime

#-------------------------------------------------------------------------------

type B  = BigInt[254]
type F  = Fp[BN254Snarks]
type F2 = QuadraticExt[F]
type G  = EC_ShortW_Prj[F2, G2]

#-------------------------------------------------------------------------------

# size of the scalar field
let r : B =    fromHex( B ,"0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001" )

let expo : B = fromHex( B, "0x7b17fcc286b01af79176aa7da3a8615020eacda89a90e4ff5d0a085483f0448" )

let expoA_fr = fromHex( Fr[BN254Snarks],"0x1234567890123456789001234567890" )
var expoB_fr = fromHex( Fr[BN254Snarks],"0x7b17fcc286b01af79176aa7da3a8615020eacda89a90e4ff5d0a085483f0448" )
expoB_fr -= expoA_fr

let expoA = expoA_fr.toBig()
let expoB = expoB_fr.toBig()

# debugEcho "expo:" , expo.toHex()

let zeroF : F = fromHex( F, "0x00" )
let oneF  : F = fromHex( F, "0x01" )

#-------------------------------------------------------------------------------

# standard generator of G2

let gen2_xi : F = fromHex( F, "0x1adcd0ed10df9cb87040f46655e3808f98aa68a570acf5b0bde23fab1f149701" )
let gen2_xu : F = fromHex( F, "0x09e847e9f05a6082c3cd2a1d0a3a82e6fbfbe620f7f31269fa15d21c1c13b23b" )
let gen2_yi : F = fromHex( F, "0x056c01168a5319461f7ca7aa19d4fcfd1c7cdf52dbfc4cbee6f915250b7f6fc8" )
let gen2_yu : F = fromHex( F, "0x0efe500a2d02dd77f5f401329f30895df553b878fc3c0dadaaa86456a623235c" )

let gen2_x : F2 = F2( coords: [gen2_xi, gen2_xu] )
let gen2_y : F2 = F2( coords: [gen2_yi, gen2_yu] )
let gen2_z : F2 = F2( coords: [oneF   , zeroF  ] )

let gen2 : G = G( x: gen2_x, y: gen2_y, z: gen2_z )

#-------------------------------------------------------------------------------

template echo(intercept: untyped) =
  # This intercepts system.echo
  # Delete this template to debug intermediate steps
  discard

proc printF( x: F ) =
  echo(" = " & x.toDecimal)

proc printF2( z: F2) =
  echo("   1 ~> " & z.coords[0].toDecimal )
  echo("   u ~> " & z.coords[1].toDecimal )


proc printG( pt: G ) =
  var aff : EC_ShortW_Aff[F2, G2];
  aff.affine(pt)
  echo(" affine x coord: ");  printF2( aff.x )
  echo(" affine y coord: ");  printF2( aff.y )

#-------------------------------------------------------------------------------

template test(scalarProc: untyped) =
  proc `test _ scalarProc`() =
    var p : G
    var q : G

    echo("")
    echo("sanity check: g2^r should be infinity")
    p = gen2
    p.scalarProc(r)
    printG(p)

    echo("")
    echo("LHS = g2^expo")
    p = gen2
    p.scalarProc(expo)
    printG(p)
    let lhs : G = p

    echo("")
    echo("RHS = g2^expoA * g2^expoB, where expo = expoA + expoB")
    p = gen2
    q = gen2
    p.scalarProc(expoA)
    q.scalarProc(expoB)
    p += q
    printG(p)
    let rhs : G = p

    echo("")
    echo("reference from SageMath")
    echo("  sage x coord:")
    echo("    1 -> 17216390949661727229956939928583223226083668728437958793715435751523027888005 ")
    echo("    u -> 3082945034329785101034278215941854680789766318859358488904629243958221738137 ")
    echo("  sage y coord:")
    echo("    1 -> 20108673238932196920264801702661201943173809015346082727725783869161803474440 ")
    echo("    u -> 10405477402946058176045590740070709500904395284580129777629727895349459816649 ")

    echo("")
    echo("LHS - RHS = ")
    p =  lhs
    p -= rhs
    printG(p)

    doAssert p.isNeutral().bool()

  `test _ scalarProc`()

system.echo "issue #345 - scalarMul"
test(scalarMul)
system.echo "issue #345 - scalarMul_vartime"
test(scalarMul_vartime)

system.echo "SUCCESS - issue #345"

#-------------------------------------------------------------------------------

#[

SageMath code

# BN128 elliptic curve
p  = 21888242871839275222246405745257275088696311157297823662689037894645226208583
r  = 21888242871839275222246405745257275088548364400416034343698204186575808495617
h  = 1
Fp = GF(p)
Fr = GF(r)
A  = Fp(0)
B  = Fp(3)
E  = EllipticCurve(Fp,[Name,B])
gx = Fp(1)
gy = Fp(2)
gen = E(gx,gy)  # subgroup generator
print("scalar field check: ", gen.additive_order() == r )
print("cofactor check:     ", E.cardinality() == r*h )

# extension field
R.<x>   = Fp[]
Fp2.<u> = Fp.extension(x^2+1)

# twisted curve
B_twist = Fp2(19485874751759354771024239261021720505790618469301721065564631296452457478373 + 266929791119991161246907387137283842545076965332900288569378510910307636690*u )
E2 = EllipticCurve(Fp2,[0,B_twist])
size_E2     = E2.cardinality();
cofactor_E2 = size_E2 / r;

gen2_xi = Fp( 0x1adcd0ed10df9cb87040f46655e3808f98aa68a570acf5b0bde23fab1f149701 )
gen2_xu = Fp( 0x09e847e9f05a6082c3cd2a1d0a3a82e6fbfbe620f7f31269fa15d21c1c13b23b )
gen2_yi = Fp( 0x056c01168a5319461f7ca7aa19d4fcfd1c7cdf52dbfc4cbee6f915250b7f6fc8 )
gen2_yu = Fp( 0x0efe500a2d02dd77f5f401329f30895df553b878fc3c0dadaaa86456a623235c )

gen2_x = gen2_xi + u * gen2_xu
gen2_y = gen2_yi + u * gen2_yu

gen2 = E2(gen2_x, gen2_y)

print("g2^r: ", gen2*r )

expo = 0x7b17fcc286b01af79176aa7da3a8615020eacda89a90e4ff5d0a085483f0448

print("g2^expo: ")
print(gen2*expo)

]#

#-------------------------------------------------------------------------------
