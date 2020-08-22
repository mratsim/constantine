# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard Library
  std/typetraits,
  # Internal
  ../primitives,
  ../config/[common, curves, type_bigint],
  ../arithmetic,
  ../io/io_bigints,
  ../towers,
  ./ec_weierstrass_affine,
  ./ec_weierstrass_projective,
  ./ec_endomorphism_params

# ############################################################
#
#             Endomorphism acceleration for
#                 Scalar Multiplication
#
# ############################################################
#
# This files implements endomorphism-acceleration of scalar multiplication
# using:
# - GLV endomorphism on G1 (Gallant-Lambert-Vanstone)
# - GLV and GLS endomorphisms on G2 (Galbraith-Lin-Scott)
# - NAF recoding (windowed Non-Adjacent-Form)


# Secret scalar + dynamic point
# ----------------------------------------------------------------
#
# This section targets the case where the scalar multiplication [k]P
# involves:
# - a secret scalar `k`, hence requiring constant-time operations
# - a dynamic `P`
#
# For example signing a message
#
# When P is known ahead of time (for example it's the generator)
# We can precompute the point decomposition with plain scalar multiplication
# and not require a fast endomorphism.
# (For example generating a public-key)

type
  Recoded[LengthInDigits: static int] = distinct array[LengthInDigits, byte]
  GLV_SAC[M, LengthInDigits: static int] = array[M, Recoded[LengthInDigits]]
    ## GLV-Based Sign-Aligned-Column representation
    ## see Faz-Hernandez, 2013
    ##
    ## (i) Length of every sub-scalar is fixed and given by
    ##     l = ⌈log2 r/m⌉ + 1 where r is the prime subgroup order
    ##     and m the number of dimensions of the GLV endomorphism
    ## (ii) Exactly one subscalar which should be odd
    ##      is expressed by a signed nonzero representation
    ##      with all digits ∈ {1, −1} represented at a lowlevel
    ##      by bit {0, 1} (0 bit -> positive 1 digit, 1 bit -> negative -1 digit)
    ## (iii) Other subscalars have digits  ∈ {0, 1, −1}
    ##       with 0 encoded as 0 and 1/-1 encoded as 1
    ##       and the sign taken from the sign subscalar (at position 0)
    ##
    ## Digit-Endianness is bigEndian

const
  BitSize   = 1
  Shift     = 1    # log2(2) - we can store 2 digits per byte
  ByteMask  = 1    # we need (mod 2) to access a packed bytearray
  DigitMask = 0b1  # Digits take 1-bit

proc `[]`(recoding: Recoded,
          digitIdx: int): uint8 {.inline.}=
  ## 0 <= digitIdx < LengthInDigits
  ## returns digit ∈ {0, 1}
  const len = Recoded.LengthInDigits
  assert digitIdx < len

  let slot = distinctBase(recoding)[
    len-1 - (digitIdx shr Shift)
  ]
  let recoded = slot shr (BitSize*(digitIdx and ByteMask)) and DigitMask
  return recoded

proc `[]=`(recoding: var Recoded,
           digitIdx: int, value: uint8) {.inline.}=
  ## 0 <= digitIdx < LengthInDigits
  ## returns digit ∈ {0, 1}
  ## This is write-once
  const len = Recoded.LengthInDigits
  assert digitIdx < Recoded.LengthInDigits

  let slot = distinctBase(recoding)[
    len-1 - (digitIdx shr Shift)
  ].addr

  let shifted = byte((value and DigitMask) shl (BitSize*(digitIdx and ByteMask)))
  slot[] = slot[] or shifted

func nDimMultiScalarRecoding[M, L: static int](
    dst: var GLV_SAC[M, L],
    src: MultiScalar[M, L]
  ) =
  ## This recodes N scalar for GLV multi-scalar multiplication
  ## with side-channel resistance.
  ##
  ## Precondition src[0] is odd
  #
  # - Efficient and Secure Algorithms for GLV-Based Scalar
  #   Multiplication and their Implementation on GLV-GLS
  #   Curves (Extended Version)
  #   Armando Faz-Hernández, Patrick Longa, Ana H. Sánchez, 2013
  #   https://eprint.iacr.org/2013/158.pdf
  #
  # Algorithm 1 Protected Recoding Algorithm for the GLV-SAC Representation.
  # ------------------------------------------------------------------------
  #
  # We modify Algorithm 1 with the last paragraph optimization:
  # - instead of ternary coding -1, 0, 1 (for negative, 0, positive)
  # - we use 0, 1 for (0, sign of column)
  #   and in the sign column 0, 1 for (negative, positive)

  # assert src[0].isOdd - Only happen on implementation error, we don't want to leak a single bit

  var k = src # Keep the source multiscalar in registers
  template b: untyped {.dirty.} = dst

  b[0][L-1] = 0 # means negative column
  for i in 0 .. L-2:
    b[0][i] = 1 - k[0].bit(i+1).uint8
  for j in 1 .. M-1:
    for i in 0 .. L-1:
      let bji = k[j].bit0.uint8
      b[j][i] = bji
      k[j].div2()
      k[j] += SecretWord (bji and b[0][i])

func buildLookupTable[M: static int, F](
       P: ECP_SWei_Proj[F],
       endomorphisms: array[M-1, ECP_SWei_Proj[F]],
       lut: var array[1 shl (M-1), ECP_SWei_Proj[F]],
     ) =
  ## Build the lookup table from the base point P
  ## and the curve endomorphism
  #
  # Algorithm
  # Compute P[u] = P0 + u0 P1 +...+ um−2 Pm−1 for all 0≤u<2^m−1, where
  # u= (um−2,...,u0)_2.
  #
  # Traduction:
  #   for u in 0 ..< 2^(m-1)
  #     lut[u] = P0
  #     iterate on the bit representation of u
  #       if the bit is set, add the matching endomorphism to lut[u]
  #
  # Note: This is for variable/unknown point P
  #       when P is fixed at compile-time (for example is the generator point)
  #       alternative algorithms are more efficient.
  #
  # Implementation:
  #   We optimize the basic algorithm to reuse already computed table entries
  #   by noticing for example that:
  #   - 6 represented as 0b0110 requires P0 + P2 + P3
  #   - 2 represented as 0b0010 already required P0 + P2
  #   To find the already computed table entry, we can index
  #   the table with the current `u` with the MSB unset
  #   and add to it the endormorphism at the index matching the MSB position
  #
  #   This scheme ensures 1 addition per table entry instead of a number
  #   of addition dependent on `u` Hamming Weight
  #
  # TODO:
  # 1. Window method for M == 2
  # 2. Have P in affine coordinate and build the table with mixed addition
  #    assuming endomorphism φi(P) do not affect the Z coordinates
  #    (if table is big enough/inversion cost is amortized)
  # 3. Use Montgomery simultaneous inversion to have the table in
  #    affine coordinate so that we can use mixed addition in teh main loop
  lut[0] = P
  for u in 1'u32 ..< 1 shl (M-1):
    # The recoding allows usage of 2^(n-1) table instead of the usual 2^n with NAF
    let msb = u.log2() # No undefined, u != 0
    lut[u].sum(lut[u.clearBit(msb)], endomorphisms[msb])
    # } # highlight bug, ...

func tableIndex(glv: GLV_SAC, bit: int): SecretWord =
  ## Compose the secret table index from
  ## the GLV-SAC representation and the "bit" accessed
  # TODO:
  #   We are currently storing 2-bit for 0, 1, -1 in the GLV-SAC representation
  #   but since columns have all the same sign, determined by k0,
  #   we only need 0 and 1 dividing storage per 2
  staticFor i, 1, GLV_SAC.M:
    result = result or SecretWord((glv[i][bit] and 1) shl (i-1))

func secretLookup[T](dst: var T, table: openArray[T], index: SecretWord) =
  ## Load a table[index] into `dst`
  ## This is constant-time, whatever the `index`, its value is not leaked
  ## This is also protected against cache-timing attack by always scanning the whole table
  for i in 0 ..< table.len:
    let selector = SecretWord(i) == index
    dst.ccopy(table[i], selector)

func scalarMulGLV*[scalBits](
       P: var ECP_SWei_Proj,
       scalar: BigInt[scalBits]
     ) =
  ## Elliptic Curve Scalar Multiplication
  ##
  ##   P <- [k] P
  ##
  ## This is a scalar multiplication accelerated by an endomorphism
  ## via the GLV (Gallant-lambert-Vanstone) decomposition.
  const C = P.F.C # curve
  static: doAssert: scalBits == C.getCurveOrderBitwidth()
  when P.F is Fp:
    const M = 2

  # 1. Compute endomorphisms
  var endomorphisms: array[M-1, typeof(P)] # TODO: zero-init not required
  endomorphisms[0] = P
  endomorphisms[0].x *= C.getCubicRootOfUnity_mod_p()

  # 2. Decompose scalar into mini-scalars
  const L = (C.getCurveOrderBitwidth() + M - 1) div M + 1
  var miniScalars: array[M, BigInt[L]] # TODO: zero-init not required
  when C == BN254_Snarks:
    scalar.decomposeScalar_BN254_Snarks_G1(
      miniScalars
    )
  elif C == BLS12_381:
    scalar.decomposeScalar_BLS12_381_G1(
      miniScalars
    )
  else:
    {.error: "Unsupported curve for GLV acceleration".}

  # 3. TODO: handle negative mini-scalars
  #    Either negate the associated base and the scalar (in the `endomorphisms` array)
  #    Or use Algorithm 3 from Faz et al which can encode the sign
  #    in the GLV representation at the low low price of 1 bit

  # 4. Precompute lookup table
  var lut: array[1 shl (M-1), ECP_SWei_Proj] # TODO: zero-init not required
  buildLookupTable(P, endomorphisms, lut)
  # TODO: Montgomery simultaneous inversion (or other simultaneous inversion techniques)
  #       so that we use mixed addition formulas in the main loop

  # 5. Recode the miniscalars
  #    we need the base miniscalar (that encodes the sign)
  #    to be odd, and this in constant-time to protect the secret least-significant bit.
  let k0isOdd = miniScalars[0].isOdd()
  discard miniScalars[0].cadd(SecretWord(1), not k0isOdd)

  var recoded: GLV_SAC[2, L] # zero-init required
  recoded.nDimMultiScalarRecoding(miniScalars)

  # 6. Proceed to GLV accelerated scalar multiplication
  var Q: typeof(P) # TODO: zero-init not required
  Q.secretLookup(lut, recoded.tableIndex(L-1))

  for i in countdown(L-2, 0):
    Q.double()
    var tmp: typeof(Q) # TODO: zero-init not required
    tmp.secretLookup(lut, recoded.tableIndex(i))
    tmp.cneg(SecretBool recoded[0][i])
    Q += tmp

  # Now we need to correct if the sign miniscalar was not odd
  P.diff(Q, lut[0]) # Contains Q - P0
  P.ccopy(Q, k0isOdd)

# Sanity checks
# ----------------------------------------------------------------
# See page 7 of
#
# - Efficient and Secure Algorithms for GLV-Based Scalar
#   Multiplication and their Implementation on GLV-GLS
#   Curves (Extended Version)
#   Armando Faz-Hernández, Patrick Longa, Ana H. Sánchez, 2013
#   https://eprint.iacr.org/2013/158.pdf

when isMainModule:
  import ../io/io_bigints

  proc toString(glvSac: GLV_SAC): string =
    for j in 0 ..< glvSac.M:
      result.add "k" & $j & ": ["
      for i in countdown(glvSac.LengthInDigits-1, 0):
        result.add " " & (block:
          case glvSac[j][i]
          of 0: "0"
          of 1: "1"
          else:
            raise newException(ValueError, "Unexpected encoded value: " & $glvSac[j][i])
        ) # " # Unbreak VSCode highlighting bug
      result.add " ]\n"


  iterator bits(u: SomeInteger): tuple[bitIndex: int32, bitValue: uint8] =
    ## bit iterator, starts from the least significant bit
    var u = u
    var idx = 0'i32
    while u != 0:
      yield (idx, uint8(u and 1))
      u = u shr 1
      inc idx

  func buildLookupTable_naive[M: static int](
         P: string,
         endomorphisms: array[M-1, string],
         lut: var array[1 shl (M-1), string],
       ) =
    ## Checking the LUT by building strings of endomorphisms additions
    ## This naively translates the lookup table algorithm
    ## Compute P[u] = P0 + u0 P1 +...+ um−2 Pm−1 for all 0≤u<2m−1, where
    ## u= (um−2,...,u0)_2.
    ## The number of additions done per entries is equal to the
    ## iteration variable `u` Hamming Weight
    for u in 0 ..< 1 shl (M-1):
      lut[u] = P
    for u in 0 ..< 1 shl (M-1):
      for idx, bit in bits(u):
        if bit == 1:
          lut[u] &= " + " & endomorphisms[idx]

  func buildLookupTable_reuse[M: static int](
         P: string,
         endomorphisms: array[M-1, string],
         lut: var array[1 shl (M-1), string],
       ) =
    ## Checking the LUT by building strings of endomorphisms additions
    ## This reuses previous table entries so that only one addition is done
    ## per new entries
    lut[0] = P
    for u in 1'u32 ..< 1 shl (M-1):
      let msb = u.log2() # No undefined, u != 0
      lut[u] = lut[u.clearBit(msb)] & " + " & endomorphisms[msb]

  proc main_lut() =
    const M = 4              # GLS-4 decomposition
    const miniBitwidth = 4   # Bitwidth of the miniscalars resulting from scalar decomposition

    var k: MultiScalar[M, miniBitwidth]
    var kRecoded: GLV_SAC[M, miniBitwidth]

    k[0].fromUint(11)
    k[1].fromUint(6)
    k[2].fromuint(14)
    k[3].fromUint(3)

    kRecoded.nDimMultiScalarRecoding(k)

    echo kRecoded.toString()

    var lut: array[1 shl (M-1), string]
    let
      P = "P0"
      endomorphisms = ["P1", "P2", "P3"]

    buildLookupTable_naive(P, endomorphisms, lut)
    echo lut
    doAssert lut[0] == "P0"
    doAssert lut[1] == "P0 + P1"
    doAssert lut[2] == "P0 + P2"
    doAssert lut[3] == "P0 + P1 + P2"
    doAssert lut[4] == "P0 + P3"
    doAssert lut[5] == "P0 + P1 + P3"
    doAssert lut[6] == "P0 + P2 + P3"
    doAssert lut[7] == "P0 + P1 + P2 + P3"

    var lut_reuse: array[1 shl (M-1), string]
    buildLookupTable_reuse(P, endomorphisms, lut_reuse)
    echo lut_reuse
    doAssert lut == lut_reuse

  main_lut()
  echo "---------------------------------------------"

  proc main_decomp() =
    const M = 2
    const scalBits = BN254_Snarks.getCurveOrderBitwidth()
    const miniBits = (scalBits+M-1) div M
    const L = miniBits + 1

    block:
      let scalar = BigInt[scalBits].fromHex(
        "0x24a0b87203c7a8def0018c95d7fab106373aebf920265c696f0ae08f8229b3f3"
      )

      var decomp: MultiScalar[M, L]
      decomposeScalar_BN254_Snarks_G1(scalar, decomp)

      doAssert: bool(decomp[0] == BigInt[L].fromHex"14928105460c820ccc9a25d0d953dbfe")
      doAssert: bool(decomp[1] == BigInt[L].fromHex"13a2f911eb48a578844b901de6f41660")

    block:
      let scalar = BigInt[scalBits].fromHex(
        "24554fa6d0c06f6dc51c551dea8b058cd737fc8d83f7692fcebdd1842b3092c4"
      )

      var decomp: MultiScalar[M, L]
      decomposeScalar_BN254_Snarks_G1(scalar, decomp)

      doAssert: bool(decomp[0] == BigInt[L].fromHex"28cf7429c3ff8f7e82fc419e90cc3a2")
      doAssert: bool(decomp[1] == BigInt[L].fromHex"457efc201bdb3d2e6087df36430a6db6")

    block:
      let scalar = BigInt[scalBits].fromHex(
        "288c20b297b9808f4e56aeb70eabf269e75d055567ff4e05fe5fb709881e6717"
      )

      var decomp: MultiScalar[M, L]
      decomposeScalar_BN254_Snarks_G1(scalar, decomp)

      doAssert: bool(decomp[0] == BigInt[L].fromHex"4da8c411566c77e00c902eb542aaa66b")
      doAssert: bool(decomp[1] == BigInt[L].fromHex"5aa8f2f15afc3217f06677702bd4e41a")


  main_decomp()

  echo "---------------------------------------------"

  # This tests the multiplication against the Table 1
  # of the paper

  # Coef       Decimal    Binary        GLV-SAC recoded
  # | k0 |     | 11 |   | 0 1 0 1 1 |   | 1 -1 1 -1 1 |
  # | k1 |  =  |  6 | = | 0 0 1 1 0 | = | 1 -1 0 -1 0 |
  # | k2 |     | 14 |   | 0 1 1 1 0 |   | 1  0 0 -1 0 |
  # | k3 |     |  3 |   | 0 0 0 1 1 |   | 0  0 1 -1 1 |

  #   i                |         3               2             1             0
  # -------------------+----------------------------------------------------------------------
  #  2Q                |   2P0+2P1+2P2    2P0+2P1+4P2    6P0+4P1+8P2+2P3  10P0+6P1+14P2+2P3
  # Q + sign_i T[ki]   |    P0+P1+2P2   3P0+2P1+4P2+P3   5P0+3P1+7P2+P3   11P0+6P1+14P2+3P3

  type Endo = enum
    P0
    P1
    P2
    P3

  func buildLookupTable_reuse[M: static int](
         P: Endo,
         endomorphisms: array[M-1, Endo],
         lut: var array[1 shl (M-1), set[Endo]],
       ) =
    ## Checking the LUT by building strings of endomorphisms additions
    ## This reuses previous table entries so that only one addition is done
    ## per new entries
    lut[0].incl P
    for u in 1'u32 ..< 1 shl (M-1):
      let msb = u.log2() # No undefined, u != 0
      lut[u] = lut[u.clearBit(msb)] + {endomorphisms[msb]}


  proc mainFullMul() =
    const M = 4                # GLS-4 decomposition
    const miniBitwidth = 4     # Bitwidth of the miniscalars resulting from scalar decomposition
    const L = miniBitwidth + 1 # Bitwidth of the recoded scalars

    var k: MultiScalar[M, L]
    var kRecoded: GLV_SAC[M, L]

    k[0].fromUint(11)
    k[1].fromUint(6)
    k[2].fromuint(14)
    k[3].fromUint(3)

    kRecoded.nDimMultiScalarRecoding(k)

    echo kRecoded.toString()

    var lut: array[1 shl (M-1), set[Endo]]
    let
      P = P0
      endomorphisms = [P1, P2, P3]

    buildLookupTable_reuse(P, endomorphisms, lut)
    echo lut

    var Q: array[Endo, int]

    # Multiplication
    assert bool k[0].isOdd()
    # Q = sign_l-1 P[K_l-1]
    let idx = kRecoded.tableIndex(L-1)
    for p in lut[int(idx)]:
      Q[p] = if kRecoded[0][L-1] == 0: 1 else: -1
    # Loop
    for i in countdown(L-2, 0):
      # Q = 2Q
      for val in Q.mitems: val *= 2
      echo "2Q:                    ", Q
      # Q = Q + sign_l-1 P[K_l-1]
      let idx = kRecoded.tableIndex(i)
      for p in lut[int(idx)]:
        Q[p] += (if kRecoded[0][i] == 0: 1 else: -1)
      echo "Q + sign_l-1 P[K_l-1]: ", Q

    echo Q

  mainFullMul()
