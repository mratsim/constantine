import std/[os, unittest, strutils],
       constantine/proof_systems/manual_groth16,
       constantine/named/algebras

#[
For information about the data files used in this test case, see
`examples/groth16_prover.org`.
]#

suite "Groth16 prover":
  test "Proving 3-factorization example":
    const T = BN254_Snarks
    # parse binary files
    let wtns = parseWtnsFile("./groth16_files/witness.wtns").toWtns[:T]()
    let zkey = parseZkeyFile("./groth16_files/three_fac_final.zkey").toZkey[:T]()
    let r1cs = parseR1csFile("./groth16_files/three_fac.r1cs").toR1CS()
    # construct mutable prover (to overwrite r, s)
    var ctx = Groth16Prover[T].init(zkey, wtns, r1cs)
    # definition of `r` and `s` values that produced expected proof
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
    # overwrite context's random values
    ctx.r = r
    ctx.s = s

    # expected values produced by SnarkJS with these `r`, `s` values
    # x/y coordinates of Fp point on G1 subgroup of EC, corresponding to `g^A_1`
    const ax = "5525629793372463776337933283524928112323589665400780041477380790923758613749"
    const ay = "21229177076048503863699135039723099340209138028149442778064006577287317302601"
    # x/y cooridnates of Fp2 point on G2 subgroup, corresponding to `g^B_2`
    const bxc0 = "10113559933709853115219982658131344715329670532374721861173670433756614595086"
    const bxc1 = "748111067660143353202076805159132563350177510079329482395824347599610874338"
    const byc0 = "14193926223452546125681093394065339196897041249946578591171606543100010486627"
    const byc1 = "871256420758854731396810855688710623510558493821614150596755347032202324148"
    # x/y coordinates of Fp point on G1 subgroup, corresponding to `g^C_1`
    const cx = "18517653609733492682442099361591955563405567929398531111532682405176646276349"
    const cy = "17315036348446251361273519572420522936369550153340386126725970444173389652255"

    proc toECG1(x, y: string): EC_ShortW_Aff[Fp[T], G1] {.noinit.} =
      let xF = Fp[T].fromDecimal(x)
      let yF = Fp[T].fromDecimal(y)
      result.x = xF
      result.y = yF

    proc toFp2(c0, c1: string): Fp2[T] {.noinit.} =
      let c0F = Fp[T].fromDecimal(c0)
      let c1F = Fp[T].fromDecimal(c1)
      result.c0 = c0F
      result.c1 = c1F

    proc toECG2(xc0, xc1, yc0, yc1: string): EC_ShortW_Aff[Fp2[T], G2] {.noinit.} =
      let xF2 = toFp2(xc0, xc1)
      let yF2 = toFp2(yc0, yc1)
      result.x = xF2
      result.y = yF2

    let aExp = toECG1(ax, ay)
    let bExp = toECG2(bxc0, bxc1, byc0, byc1)
    let cExp = toECG1(cx, cy)

    # call the proof and...
    let (A_p, B2_p, C_p) = ctx.prove()

    echo aExp.toDecimal()
    echo bExp.toDecimal()
    echo cExp.toDecimal()

    echo "\n==============================\n"
    echo "A_p#16 = ", A_p.toHex()
    echo "A_p#10 = ", A_p.toDecimal()
    echo "------------------------------"
    echo "B_p#16 = ", B2_p.toHex()
    echo "B_p#10 = ", B2_p.toDecimal()
    echo "------------------------------"
    echo "C_p#16 = ", C_p.toHex()
    echo "C_p#10 = ", C_p.toDecimal()

    check (A_p  == aExp.getJacobian).bool
    check (B2_p == bExp.getJacobian).bool
    ## XXX: C currently fails!
    check (C_p  == cExp.getJacobian).bool
