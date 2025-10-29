import constantine/proof_systems/manual_groth16,
       constantine/named/algebras

const T = BN254_Snarks

let wtns = parseWtnsFile("./groth16_files/three_fac_js/witness.wtns").toWtns[:T]()
let zkey = parseZkeyFile("./groth16_files/three_fac_final.zkey").toZkey[:T]()
let r1cs = parseR1csFile("./groth16_files/three_fac.r1cs").toR1CS()

var ctx = Groth16Prover[T].init(zkey, wtns, r1cs)

const rSJ = @[
  byte 143,  55, 118,  73,  42, 115,  60,  77,
  95, 209,  41, 144, 250, 137, 138,  71,
  176, 242, 186, 232, 179,  30,  88, 255,
  198, 161, 182, 150, 220, 149,  33,  19
]
const sSJ = @[
  byte 213, 105, 105,  27, 129, 249, 139, 158,
  221,  68,  37, 163,  59,  71,  19, 108,
  60, 153, 183, 156,  25, 148,  37,   9,
  85, 205, 250, 246, 132, 142, 244,  36
]

# construct the random element `r` from snarkjs "secret" r
let r = toFr[BN254_Snarks](rSJ)
# and `s`
let s = toFr[BN254_Snarks](sSJ)

ctx.r = r
ctx.s = s

let (A_p, B2_p, C_p) = ctx.prove()

echo "\n==============================\n"
echo "A_p#16 = ", A_p.toHex()
echo "A_p#10 = ", A_p.toDecimal()
echo "------------------------------"
echo "B_p#16 = ", B2_p.toHex()
echo "B_p#10 = ", B2_p.toDecimal()
echo "------------------------------"
echo "C_p#16 = ", C_p.toHex()
echo "C_p#10 = ", C_p.toDecimal()
