# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/abstractions,
  constantine/named/algebras,
  constantine/named/zoo_endomorphisms,
  constantine/named/zoo_generators,
  constantine/math/io/io_fields,
  constantine/math/arithmetic,
  constantine/math/extension_fields,
  constantine/math/io/io_bigints,
  constantine/math/endomorphisms/split_scalars,
  ./ec_shortweierstrass_affine,
  ./ec_shortweierstrass_projective,
  ./ec_shortweierstrass_jacobian,
  ./ec_twistededwards_affine,
  ./ec_twistededwards_projective,
  ./ec_shortweierstrass_batch_ops,
  ./ec_twistededwards_batch_ops

{.push raises: [].} # No exceptions allowed in core cryptographic operations
{.push checks: off.} # No defects due to array bound checking or signed integer overflow allowed

# ############################################################
#                                                            #
#                   Scalar Multiplication                    #
#                                                            #
# ############################################################
#
# Scalar multiplication is a key algorithm for cryptographic protocols:
# - it is slow,
# - it is performance critical as it is used to generate signatures and authenticate messages
# - it is a high-value target as the "scalar" is very often the user secret key
#
# A safe scalar multiplication MUST:
# - Use no branching (to prevent timing and simple power analysis attacks)
# - Always do the same memory accesses (in particular for table lookups) (to prevent cache-timing attacks)
# - Not expose the bitlength of the exponent (use the curve order bitlength instead)
#
# Constantine does not make an extra effort to defend against the smart-cards
# and embedded device attacks:
# - Differential Power-Analysis which may allow for example retrieving bit content depending on the cost of writing 0 or 1
#   (Address-bit DPA by Itoh, Izu and Takenaka)
# - Electro-Magnetic which can be used in a similar way to power analysis but based on EM waves
# - Fault Attacks which can be used by actively introducing faults (via a laser for example) in an algorithm
#
# The current security efforts are focused on preventing attacks
# that are effective remotely including through the network,
# a colocated VM or a malicious process on your phone.
#
# - Survey for Performance & Security Problems of Passive Side-channel Attacks     Countermeasures in ECC\
#   Rodrigo Abarúa, Claudio Valencia, and Julio López, 2019\
#   https://eprint.iacr.org/2019/010
#
# - State-of-the-art of secure ECC implementations:a survey on known side-channel attacks and countermeasures\
#   Junfeng Fan,XuGuo, Elke De Mulder, Patrick Schaumont, Bart Preneel and Ingrid Verbauwhede, 2010
#   https://www.esat.kuleuven.be/cosic/publications/article-1461.pdf

# Generic implementation
# --------------------------------------------------------------------------------------

template checkScalarMulScratchspaceLen(len: int) =
  ## CHeck that there is a minimum of scratchspace to hold the temporaries
  debug:
    assert len >= 2, "[ctt] Internal error: the scratchspace for scalar multiplication should be equal or greater than 2"

func getWindowLen(bufLen: int): uint =
  ## Compute the maximum window size that fits in the scratchspace buffer
  checkScalarMulScratchspaceLen(bufLen)
  result = 5
  while (1 shl result) + 1 > bufLen:
    dec result

func scalarMulPrologue[EC](
       P: var EC,
       scratchspace: var openarray[EC]
     ): uint =
  ## Setup the scratchspace then set P to infinity
  ## Returns the fixed-window size for scalar mul with window optimization
  result = scratchspace.len.getWindowLen()
  # Precompute window content, special case for window = 1
  # (i.e scratchspace has only space for 2 temporaries)
  # The content scratchspace[2+k] is set at [k]P
  # with scratchspace[0] untouched
  if result == 1:
    scratchspace[1] = P
  else:
    scratchspace[2] = P
    for k in 2 ..< 1 shl result:
      scratchspace[k+1].sum(scratchspace[k], P)

  # Set a to infinity
  P.setNeutral()

func scalarMulDoubling[EC](
       P: var EC,
       exponent: openArray[byte],
       tmp: var EC,
       window: uint,
       acc, acc_len: var uint,
       e: var int
     ): tuple[k, bits: uint] {.inline.} =
  ## Doubling steps of doubling and add for scalar multiplication
  ## Get the next k bits in range [1, window)
  ## and double k times
  ## Returns the number of doubling done and the corresponding bits.
  ##
  ## Updates iteration variables and accumulators
  #
  # ⚠️: Extreme care should be used to not leak
  #    the exponent bits nor its real bitlength
  #    i.e. if the exponent is zero but encoded in a
  #    256-bit integer, only "256" should leak
  #    as for most applications like ECDSA or BLS signature schemes
  #    the scalar is the user secret key.

  # Get the next bits
  # acc/acc_len must be uint to avoid Nim runtime checks leaking bits
  # e is public
  var k = window
  if acc_len < window:
    if e < exponent.len:
      acc = (acc shl 8) or exponent[e].uint
      inc e
      acc_len += 8
    else: # Drained all exponent bits
      k = acc_len

  let bits = (acc shr (acc_len - k)) and ((1'u shl k) - 1)
  acc_len -= k

  # We have k bits and can do k doublings
  for i in 0 ..< k:
    tmp.double(P)
    P = tmp

  return (k, bits)

func scalarMulGeneric[EC](
       P: var EC,
       scalar: openArray[byte],
       scratchspace: var openArray[EC]
     ) =
  ## Elliptic Curve Scalar Multiplication
  ##
  ##   P <- [k] P
  ##
  ## This uses fixed-window optimization if possible
  ## `scratchspace` MUST be of size 2 .. 2^4
  ##
  ## This is suitable to use with secret `scalar`, in particular
  ## to derive a public key from a private key or
  ## to sign a message.
  ##
  ## Particular care has been given to defend against the following side-channel attacks:
  ## - timing attacks: all exponents of the same length
  ##   will take the same time including
  ##   a "zero" exponent of length 256-bit
  ## - cache-timing attacks: Constantine does use a precomputed table
  ##   but when extracting a value from the table
  ##   the whole table is always accessed with the same pattern
  ##   preventing malicious attacks through CPU cache delay analysis.
  ## - simple power-analysis and electromagnetic attacks: Constantine always do the same
  ##   double and add sequences and those cannot be analyzed to distinguish
  ##   the exponent 0 and 1.
  ##
  ## I.e. As far as the author know, Constantine implements all countermeasures to the known
  ##      **remote** attacks on ECC implementations.
  ##
  ## Disclaimer:
  ##   Constantine is provided as-is without any guarantees.
  ##   Use at your own risks.
  ##   Thorough evaluation of your threat model, the security of any cryptographic library you are considering,
  ##   and the secrets you put in jeopardy is strongly advised before putting data at risk.
  ##   The author would like to remind users that the best code can only mitigate
  ##   but not protect against human failures which are the weakest links and largest
  ##   backdoors to secrets exploited today.
  ##
  ## Constantine is resistant to
  ## - Fault Injection attacks: Constantine does not have branches that could
  ##   be used to skip some additions and reveal which were dummy and which were real.
  ##   Dummy operations are like the double-and-add-always timing attack countermeasure.
  ##
  ##
  ## Constantine DOES NOT defend against Address-Bit Differential Power Analysis attacks by default,
  ## which allow differentiating between writing a 0 or a 1 to a memory cell.
  ## This is a threat for smart-cards and embedded devices (for example to handle authentication to a cable or satellite service)
  ## Constantine can be extended to use randomized projective coordinates to foil this attack.

  let window = scalarMulPrologue(P, scratchspace)

  # We process bits with from most to least significant.
  # At each loop iteration with have acc_len bits in acc.
  # To maintain constant-time the number of iterations
  # or the number of operations or memory accesses should be the same
  # regardless of acc & acc_len
  var
    acc, acc_len: uint
    e = 0
  while acc_len > 0 or e < scalar.len:
    let (k, bits) = scalarMulDoubling(
      P, scalar, scratchspace[0],
      window, acc, acc_len, e
    )

    # Window lookup: we set scratchspace[1] to the lookup value
    # If the window length is 1 it's already set.
    if window > 1:
      # otherwise we need a constant-time lookup
      # in particular we need the same memory accesses, we can't
      # just index the openarray with the bits to avoid cache attacks.
      for i in 1 ..< 1 shl k:
        let ctl = SecretWord(i) == SecretWord(bits)
        scratchspace[1].ccopy(scratchspace[1+i], ctl)

    # Multiply with the looked-up value
    # we need to keep the product only ig the exponent bits are not all zeroes
    scratchspace[0].sum(P, scratchspace[1])
    P.ccopy(scratchspace[0], SecretWord(bits).isNonZero())

func scalarMulGeneric*[EC](P: var EC, scalar: BigInt, window: static int = 5) =
  ## Elliptic Curve Scalar Multiplication
  ##
  ##   P <- [k] P
  ##
  ## This scalar multiplication can handle edge cases:
  ## - When a cofactor is not cleared
  ## - Multiplying by a number beyond curve order.
  ##
  ## A window size will reserve 2^window of scratch space to accelerate
  ## the scalar multiplication.
  var
    scratchSpace: array[1 shl window, EC]
    scalarCanonicalBE: array[scalar.bits.ceilDiv_vartime(8), byte] # canonical big endian representation
  scalarCanonicalBE.marshal(scalar, bigEndian)                     # Export is constant-time
  P.scalarMulGeneric(scalarCanonicalBE, scratchSpace)

# Endomorphism accelerated
# --------------------------------------------------------------------------------------

func buildEndoLookupTable[M: static int, EC, ECaff](
       P: EC,
       endomorphisms: array[M-1, EC],
       lut: var array[1 shl (M-1), ECaff]) =
  ## Build the lookup table from the base point P
  ## and the curve endomorphism
  ##
  ## Note:
  ##   The destination parameter is last so that the compiler can infer the value of M
  ##   It fails with 1 shl (M-1)

  # Step 1. Create the lookup-table in alternative coordinates
  var tab {.noInit.}: array[1 shl (M-1), EC]
  buildEndoLookupTable(
    P, endomorphisms,
    tab,
    groupLawAdd = sum
  )

  # Step 2. Convert to affine coordinates to benefit from mixed-addition
  lut.batchAffine(tab)

func scalarMulEndo*[scalBits; EC](
       P: var EC,
       scalar: BigInt[scalBits]) {.meter.} =
  ## Elliptic Curve Scalar Multiplication
  ##
  ##   P <- [k] P
  ##
  ## This is a scalar multiplication accelerated by an endomorphism
  ## - via the GLV (Gallant-lambert-Vanstone) decomposition on G1
  ## - via the GLS (Galbraith-Lin-Scott) decomposition on G2
  ##
  ## Requires:
  ## - Cofactor to be cleared
  ## - 0 <= scalar < curve order
  static: doAssert scalBits <= EC.getScalarField().bits(), block:
      "Do not use endomorphism to multiply beyond the curve order:\n" &
      "  scalar: " & $scalBits & "-bit\n" &
      "  order:  " & $EC.getScalarField().bits() & "-bit\n"

  # 1. Compute endomorphisms
  const M = when P.F is Fp:  2
            elif P.F is Fp2: 4
            else: {.error: "Unconfigured".}
  const G = when EC isnot EC_ShortW_Aff|EC_ShortW_Jac|EC_ShortW_Prj: G1
            else: EC.G

  var endos {.noInit.}: array[M-1, EC]
  endos.computeEndomorphisms(P)

  # 2. Decompose scalar into mini-scalars
  const L = EC.getScalarField().bits().computeEndoRecodedLength(M)
  var miniScalars {.noInit.}: array[M, BigInt[L]]
  var negatePoints {.noInit.}: array[M, SecretBool]
  miniScalars.decomposeEndo(negatePoints, scalar, EC.getScalarField().bits(), EC.getName(), G)

  # 3. Handle negative mini-scalars
  # A scalar decomposition might lead to negative miniscalar.
  # For proper handling it requires either:
  # 1. Negating it and then negating the corresponding curve point P
  # 2. Adding an extra bit to L for the recoding, which will do the right thing™
  block:
    P.cneg(negatePoints[0])
    staticFor i, 1, M:
      endos[i-1].cneg(negatePoints[i])

  # 4. Precompute lookup table
  var lut {.noInit.}: array[1 shl (M-1), affine(EC)]
  buildEndoLookupTable(P, endos, lut)

  # 5. Recode the miniscalars
  #    we need the base miniscalar (that encodes the sign)
  #    to be odd, and this in constant-time to protect the secret least-significant bit.
  let k0isOdd = miniScalars[0].isOdd()
  discard miniScalars[0].cadd(One, not k0isOdd)

  var recoded: GLV_SAC[M, L] # zero-init required
  recoded.nDimMultiScalarRecoding(miniScalars)

  # 6. Proceed to GLV accelerated scalar multiplication
  var Q {.noInit.}: EC
  var tmp {.noInit.}: affine(EC)
  tmp.secretLookup(lut, recoded.getRecodedIndex(L-1))
  Q.fromAffine(tmp)

  for i in countdown(L-2, 0):
    Q.double()
    tmp.secretLookup(lut, recoded.getRecodedIndex(i))
    tmp.cneg(recoded.getRecodedNegate(i))
    Q += tmp

  # Now we need to correct if the sign miniscalar was not odd
  P.diff(Q, P)
  P.ccopy(Q, k0isOdd)

# Endomorphism accelerated with window of size 2
# --------------------------------------------------------------------------------------

func buildEndoLookupTable_m2w2[EC, ECaff](
       lut: var array[8, ECaff],
       P0, P1: EC) =
  ## Build a lookup table for GLV with 2-dimensional decomposition
  ## and window of size 2
  # Step 1. Create the lookup-table in alternative coordinates
  var tab {.noInit.}: array[8, EC]
  tab.buildEndoLookupTable_m2w2(
    P0, P1,
    groupLawAdd = sum,
    groupLawSub = diff,
    groupLawDouble = double,
  )

  # Step 2. Convert to affine coordinates to benefit from mixed-addition
  lut.batchAffine(tab)

type SecpGeneratorPoint = EC_ShortW_Aff[Fp[Secp256k1], G1]

template secpGeneratorPoint(xHex, yHex: static string): SecpGeneratorPoint =
  SecpGeneratorPoint(x: Fp[Secp256k1].fromHex(xHex),
                     y: Fp[Secp256k1].fromHex(yHex))

# Affine tables for 3G + jφ(G), G + jφ(G), and G - φ(G), in GLV lookup order.
# The second row uses -φ(G). Coordinates are canonical secp256k1 field values.
const secp256k1GeneratorEndoTables = [
  [
    secpGeneratorPoint("0xf9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9", "0x388f7b0f632de8140fe337e62a37f3566500a99934c2231b6cb9fd7584b8e672"),
    secpGeneratorPoint("0x213ac9c75608233a9b7752aa91dc05355faf26913c5ce5b580610a0b6dcdcc9b", "0xe2f2b16e9b1b736e2ef0ed95c84cadf3d2a4daa70efe4b15974e0dce288c3b8a"),
    secpGeneratorPoint("0xb02af490073a228415c2b14a2f855393598c74f1f606a271a93d4f3eaf845cc8", "0xe69615e07a2ff39d9cf3701ed52814ec0275d8192bcbbd9915e366df3c3c40b6"),
    secpGeneratorPoint("0xdf6edf03731f9b4b8dcd8dcf2a28fa2f8af1e022c6dc8e1cf7f0728c77206b2f", "0xc77084f09cd217ebf01cc819d5c80ca99aff5666cb3ddce4934602897b4715bd"),
    secpGeneratorPoint("0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798", "0x483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8"),
    secpGeneratorPoint("0xfedacd78d93f2b0cb477bc17fb29266d4a06ae626d1aa9d48a8024c287137285", "0x21789ac4e8872c808816bfc96d426a90a2be64e49dacf635af8cf042fc8f98dd"),
    secpGeneratorPoint("0x6d605c2bd9fc9d34ac5d3940e1b11f25d0f8017b397734388b112d8d3791fe29", "0x21789ac4e8872c808816bfc96d426a90a2be64e49dacf635af8cf042fc8f98dd"),
    secpGeneratorPoint("0xbcace2e99da01887ab0102b696902325872844067f15e98da7bba04400b88fcb", "0xb7c52588d95c3b9aa25b0403f1eef75702e84bb7597aabe663b82f6f04ef2777")
  ],
  [
    secpGeneratorPoint("0xf9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9", "0x388f7b0f632de8140fe337e62a37f3566500a99934c2231b6cb9fd7584b8e672"),
    secpGeneratorPoint("0xf6bf841c27c5a68c1ac9927af99fc3e258e3aacb1adcf82d9425a1404ed19ddf", "0x36c941f5d2a46748edb341051dadcb852fea01131a18c8e150fbaa4eaae310d6"),
    secpGeneratorPoint("0x39b93bfc41f56e0f95533676e1f910af8fd42ee4efacc8a84ba91ea267e799b1", "0xbe9e7f2bf8cef14ec28b71dea10f3741ef960ea76d3d9bbf67b7fb053424e59d"),
    secpGeneratorPoint("0x318a7543dd88172b221ce1d84017add3815bfbb2b600bafd12087b1f81ff80c6", "0xd8000dd576b44e1a0d863149aef180a81bb7267876959ecf174ad1c49d72fa3e"),
    secpGeneratorPoint("0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798", "0x483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8"),
    secpGeneratorPoint("0xbcace2e99da01887ab0102b696902325872844067f15e98da7bba04400b88fcb", "0xb7c52588d95c3b9aa25b0403f1eef75702e84bb7597aabe663b82f6f04ef2777"),
    secpGeneratorPoint("0x06f9d996f44d56b0e438c54e4fc8aee0f461dda51b58f67f3e51b2cd75919a7e", "0x1d0d4e9164e48c91d10f126a37b3520c2d5b2558f101b4ea68b1f230d773c0a5"),
    secpGeneratorPoint("0xfedacd78d93f2b0cb477bc17fb29266d4a06ae626d1aa9d48a8024c287137285", "0x21789ac4e8872c808816bfc96d426a90a2be64e49dacf635af8cf042fc8f98dd")
  ]
]

func scalarMulGLV_m2w2*[scalBits; EC](P0: var EC, scalar: BigInt[scalBits],
                                     generator: static bool = false) {.meter.} =
  ## Elliptic Curve Scalar Multiplication
  ##
  ##   P <- [k] P
  ##
  ## This is a scalar multiplication accelerated by an endomorphism
  ## via the GLV (Gallant-lambert-Vanstone) decomposition.
  ##
  ## For 2-dimensional decomposition with window 2
  ##
  ## Requires:
  ## - Cofactor to be cleared
  ## - 0 <= scalar < curve order
  static: doAssert scalBits <= EC.getScalarField().bits(), block:
      "Do not use endomorphism to multiply beyond the curve order:\n" &
      "  scalar: " & $scalBits & "-bit\n" &
      "  order:  " & $EC.getScalarField().bits() & "-bit\n"

  const G = when EC isnot EC_ShortW_Aff|EC_ShortW_Jac|EC_ShortW_Prj: G1
            else: EC.G

  # 1. Compute endomorphisms
  var P1 {.noInit.}: EC
  P1.computeEndomorphism(P0)

  # 2. Decompose scalar into mini-scalars
  const L = computeEndoWindowRecodedLength(EC.getScalarField().bits(), window = 2)
  var miniScalars {.noInit.}: array[2, BigInt[L]]
  var negatePoints {.noInit.}: array[2, SecretBool]
  miniScalars.decomposeEndo(negatePoints, scalar, EC.getScalarField().bits(), EC.getName(), G)

  # 3. Handle negative mini-scalars
  #    Either negate the associated base and the scalar (in the `endomorphisms` array)
  #    Or use Algorithm 3 from Faz et al which can encode the sign
  #    in the GLV representation at the low low price of 1 bit
  var lut {.noInit.}: array[8, affine(EC)]
  when generator:
    static: doAssert EC is EC_ShortW_Jac[Fp[Secp256k1], G1]
    # Negating both points negates every entry. Select the opposite sign for
    # the endomorphism point first, then negate the selected table if needed.
    for i in 0 ..< lut.len:
      lut[i] = secp256k1GeneratorEndoTables[0][i]
      lut[i].ccopy(secp256k1GeneratorEndoTables[1][i],
                   negatePoints[0] xor negatePoints[1])
      lut[i].cneg(negatePoints[0])
    P0.cneg(negatePoints[0])
  else:
    P0.cneg(negatePoints[0])
    P1.cneg(negatePoints[1])
    lut.buildEndoLookupTable_m2w2(P0, P1)

  # 5. Recode the miniscalars
  #    we need the base miniscalar (that encodes the sign)
  #    to be odd, and this in constant-time to protect the secret least-significant bit.
  let k0isOdd = miniScalars[0].isOdd()
  discard miniScalars[0].cadd(One, not k0isOdd)

  var recoded: GLV_SAC[2, L] # zero-init required
  recoded.nDimMultiScalarRecoding(miniScalars)

  # 6. Proceed to GLV accelerated scalar multiplication
  var Q {.noInit.}: EC
  var tmp {.noInit.}: affine(EC)
  var isNeg: SecretBool

  tmp.secretLookup(lut, recoded.getRecodedIndexW2((L div 2) - 1, isNeg))
  Q.fromAffine(tmp)

  for i in countdown((L div 2) - 2, 0):
    Q.double()
    Q.double()
    tmp.secretLookup(lut, recoded.getRecodedIndexW2(i, isNeg))
    tmp.cneg(isNeg)
    Q += tmp

  # Now we need to correct if the sign miniscalar was not odd
  P0.diff(Q, P0)
  P0.ccopy(Q, k0isOdd)

# ############################################################
#
#                 Public API
#
# ############################################################

func scalarMul*[EC](P: var EC, scalar: BigInt) {.inline, meter.} =
  ## Elliptic Curve Scalar Multiplication
  ##
  ##   P <- [k] P
  ##
  ## This use endomorphism acceleration by default if available
  ## Endomorphism acceleration requires:
  ## - Cofactor to be cleared
  ## - 0 <= scalar < curve order
  ## Those will be assumed to maintain constant-time property
  when EC.getName().hasEndomorphismAcceleration() and
       BigInt.bits >= EndomorphismThreshold:
    when EC.F is Fp:
      P.scalarMulGLV_m2w2(scalar)
    elif EC.F is Fp2:
      P.scalarMulEndo(scalar)
    else: # Curves defined on Fp^m with m > 2
      {.error: "Unreachable".}
  else:
    scalarMulGeneric(P, scalar)

func scalarMulGenerator*[Name: static Algebra](P: var EC_ShortW_Jac[Fp[Name], G1],
                                               scalar: Fr[Name]) {.inline.} =
  ## Multiply the curve generator, using precomputed GLV tables for secp256k1.
  const G = Name.getGenerator("G1")
  when Name == Secp256k1:
    P.fromAffine(G)
    P.scalarMulGLV_m2w2(scalar.toBig(), generator = true)
  else:
    P.scalarMul(scalar, G)

func scalarMul*[EC](P: var EC, scalar: Fr) {.inline.} =
  ## Elliptic Curve Scalar Multiplication
  ##
  ##   P <- [k] P
  ##
  ## This use endomorphism acceleration by default if available
  ## Endomorphism acceleration requires:
  ## - Cofactor to be cleared
  ## - 0 <= scalar < curve order
  ## Those will be assumed to maintain constant-time property
  P.scalarMul(scalar.toBig())

func scalarMul*[EC](R: var EC, scalar: Fr or BigInt, P: EC) {.inline.} =
  ## Elliptic Curve Scalar Multiplication
  ##
  ##   R <- [k] P
  ##
  ## This use endomorphism acceleration by default if available
  ## Endomorphism acceleration requires:
  ## - Cofactor to be cleared
  ## - 0 <= scalar < curve order
  ## Those will be assumed to maintain constant-time property
  R = P
  R.scalarMul(scalar)

func scalarMul*[EC; Ecaff: not EC](R: var EC, scalar: Fr or BigInt, P: ECaff) {.inline.} =
  ## Elliptic Curve Scalar Multiplication
  ##
  ##   R <- [k] P
  ##
  ## This use endomorphism acceleration by default if available
  ## Endomorphism acceleration requires:
  ## - Cofactor to be cleared
  ## - 0 <= scalar < curve order
  ## Those will be assumed to maintain constant-time property
  R.fromAffine(P)
  R.scalarMul(scalar)

# ############################################################
#
#                 Out-of-Place functions
#
# ############################################################
#
# Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
# tend to generate useless memory moves or have difficulties to minimize stack allocation
# and our types might be large (Fp12 ...)
# See: https://github.com/mratsim/constantine/issues/145

func `*`*[EC: EC_ShortW_Jac or EC_ShortW_Prj or EC_TwEdw_Prj](
      scalar: Fr or BigInt, P: EC): EC {.noInit, inline.} =
  ## Elliptic Curve Scalar Multiplication
  ##
  ##   R <- [k] P
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.scalarMul(scalar, P)

func `*`*[F, G](
      scalar: Fr or BigInt,
      P: EC_ShortW_Aff[F, G],
      T: typedesc[EC_ShortW_Jac[F, G] or EC_ShortW_Prj[F, G]]
      ): T {.noInit, inline.} =
  ## Elliptic Curve Scalar Multiplication
  ##
  ##   R <- [k] P
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.scalarMul(scalar, P)

func `*`*[F, G](
      scalar: Fr or BigInt,
      P: EC_ShortW_Aff[F, G]
      ): EC_ShortW_Jac[F, G] {.noInit, inline.} =
  ## Elliptic Curve Scalar Multiplication
  ##
  ##   R <- [k] P
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.scalarMul(scalar, P)
