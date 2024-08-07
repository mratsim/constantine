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
  constantine/platforms/abstractions,
  constantine/named/algebras,
  constantine/named/zoo_endomorphisms,
  constantine/math/arithmetic/bigints

{.push raises: [].} # No exceptions allowed in core cryptographic operations
{.push checks: off.} # No defects due to array bound checking or signed integer overflow allowed

# ############################################################
#
#         Splitting scalars for endomorphism acceleration
#
# ############################################################
#
# This files implements endomorphism-acceleration of scalar multiplication
# using:
# - GLV endomorphism on G1 (Gallant-Lambert-Vanstone)
# - GLV and GLS endomorphisms on G2 (Galbraith-Lin-Scott)

# Decomposition into scalars -> miniscalars
# ----------------------------------------------------------------------------------------

type
  MultiScalar[M, LengthInBits: static int] = array[M, BigInt[LengthInBits]]
    ## Decomposition of a secret scalar in multiple scalars

template decomposeEndoImpl[scalBits: static int](
       scalar: BigInt[scalBits],
       frBits: static int,
       Name: static Algebra,
       G: static Subgroup,
       copyMiniScalarsResult: untyped) =
  static: doAssert scalBits >= L, "Cannot decompose a scalar smaller than a mini-scalar or the decomposition coefficient"
  # Equal when no window or no negative handling, greater otherwise
  static: doAssert frBits >= scalBits
  static: doAssert L >= ceilDiv_vartime(frBits, M) + 1
  const w = frBits.wordsRequired()

  when M == 2:
    # inject works around alphas'gensym codegen in Nim v2.0.8 (not necessary in Nim v2.2.x) - https://github.com/nim-lang/Nim/pull/23801#issue-2393452970
    var alphas{.noInit, inject.}: (
      BigInt[frBits + babai(Name, G)[0][0].bits],
      BigInt[frBits + babai(Name, G)[1][0].bits]
    )
  elif M == 4:
    var alphas{.noInit, inject.}: (
      BigInt[frBits + babai(Name, G)[0][0].bits],
      BigInt[frBits + babai(Name, G)[1][0].bits],
      BigInt[frBits + babai(Name, G)[2][0].bits],
      BigInt[frBits + babai(Name, G)[3][0].bits]
    )
  else:
    {.error: "The decomposition degree " & $M & " is not configured".}

  staticFor i, 0, M:
    when bool babai(Name, G)[i][0].isZero():
      alphas[i].setZero()
    else:
      alphas[i].prod_high_words(babai(Name, G)[i][0], scalar, w)

  # We have k0 = s - 𝛼0 b00 - 𝛼1 b10 ... - 𝛼m bm0
  # and     kj = 0 - 𝛼j b0j - 𝛼1 b1j ... - 𝛼m bmj
  var
    k {.inject.}: array[M, BigInt[frBits]] # zero-init required, and inject for caller visibility
    # inject works around alphas'gensym codegen in Nim v2.0.8 (not necessary in Nim v2.2.x) - https://github.com/nim-lang/Nim/pull/23801#issue-2393452970
    alphaB {.noInit, inject.}: BigInt[frBits]
  k[0].copyTruncatedFrom(scalar)
  staticFor miniScalarIdx, 0, M:
    staticFor basisIdx, 0, M:
      when not bool lattice(Name, G)[basisIdx][miniScalarIdx][0].isZero():
        when bool lattice(Name, G)[basisIdx][miniScalarIdx][0].isOne():
          alphaB.copyTruncatedFrom(alphas[basisIdx])
        else:
          alphaB.prod(alphas[basisIdx], lattice(Name, G)[basisIdx][miniScalarIdx][0])

        when lattice(Name, G)[basisIdx][miniScalarIdx][1] xor babai(Name, G)[basisIdx][1]:
          k[miniScalarIdx] += alphaB
        else:
          k[miniScalarIdx] -= alphaB

    copyMiniScalarsResult

func decomposeEndo*[M, scalBits, L: static int](
       miniScalars: var MultiScalar[M, L],
       negatePoints: var array[M, SecretBool],
       scalar: BigInt[scalBits],
       frBits: static int,
       Name: static Algebra,
       G: static Subgroup) =
  ## Decompose a secret scalar into M mini-scalars
  ## using a curve endomorphism(s) characteristics.
  ##
  ## A scalar decomposition might lead to negative miniscalar(s).
  ## For proper handling it requires either:
  ## 1. Negating it and then negating the corresponding curve point P
  ## 2. Adding an extra bit to the recoding, which will do the right thing™
  ##
  ## For implementation solution 1 is faster:
  ##   - Double + Add is about 5000~8000 cycles on 6 64-bits limbs (BLS12-381)
  ##   - Conditional negate is about 10 cycles per Fp, on G2 projective we have 3 (coords) * 2 (Fp2) * 10 (cycles) ~= 60 cycles
  ##     We need to test the mini scalar, which is 65 bits so 2 Fp so about 2 cycles
  ##     and negate it as well.
  ##
  ## This implements solution 1.
  decomposeEndoImpl(scalar, frBits, Name, G):
    # Negative miniscalars are turned positive
    # Caller should negate the corresponding Elliptic Curve points
    let isNeg = k[miniScalarIdx].isMsbSet()
    negatePoints[miniScalarIdx] = isNeg
    k[miniScalarIdx].cneg(isNeg)
    miniScalars[miniScalarIdx].copyTruncatedFrom(k[miniScalarIdx])

func decomposeEndo*[M, scalBits, L: static int](
       miniScalars: var MultiScalar[M, L],
       scalar: BigInt[scalBits],
       frBits: static int,
       Name: static Algebra,
       G: static Subgroup) =
  ## Decompose a secret scalar into M mini-scalars
  ## using a curve endomorphism(s) characteristics.
  ##
  ## A scalar decomposition might lead to negative miniscalar(s).
  ## For proper handling it requires either:
  ## 1. Negating it and then negating the corresponding curve point P
  ## 2. Adding an extra bit to the recoding, which will do the right thing™
  ##
  ## For implementation solution 1 is faster:
  ##   - Double + Add is about 5000~8000 cycles on 6 64-bits limbs (BLS12-381)
  ##   - Conditional negate is about 10 cycles per Fp, on G2 projective we have 3 (coords) * 2 (Fp2) * 10 (cycles) ~= 60 cycles
  ##     We need to test the mini scalar, which is 65 bits so 2 Fp so about 2 cycles
  ##     and negate it as well.
  ##
  ## However, when dealing with scalars that do not use the full bitwidth
  ## the extra bit avoids potential underflows.
  ## Also for partitioned GLV-SAC (with 8-way decomposition) it is necessary.
  ##
  ## This implements solution 2.
  decomposeEndoImpl(scalar, frBits, Name, G):
    miniScalars[miniScalarIdx].copyTruncatedFrom(k[miniScalarIdx])

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
  Recoded[LengthInDigits: static int] = distinct array[LengthInDigits.ceilDiv_vartime(8), byte]
  GLV_SAC*[M, LengthInDigits: static int] = array[M, Recoded[LengthInDigits]]
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
  Shift     = 3                    # log2(sizeof(byte) * 8) - Find the word to read/write
  WordMask  = sizeof(byte) * 8 - 1 #                        - In the word, shift to the offset to read/write
  DigitMask = 1 shl BitSize - 1    # Digits take 1-bit      - Once at location, isolate bits to read/write

proc `[]`(recoding: Recoded,
          digitIdx: int): uint8 {.inline.}=
  ## 0 <= digitIdx < LengthInDigits
  ## returns digit ∈ {0, 1}
  const len = Recoded.LengthInDigits
  # assert digitIdx * BitSize < len

  let slot = distinctBase(recoding)[
    (len-1 - digitIdx) shr Shift
  ]
  let recoded = slot shr (BitSize*(digitIdx and WordMask)) and DigitMask
  return recoded

proc `[]=`(recoding: var Recoded,
           digitIdx: int, value: uint8) {.inline.}=
  ## 0 <= digitIdx < LengthInDigits
  ## returns digit ∈ {0, 1}
  ## This is write-once, requires zero-init
  ## This works in BigEndian mode
  const len = Recoded.LengthInDigits
  # assert digitIdx * BitSize < Recoded.LengthInDigits

  let slot = distinctBase(recoding)[
    (len-1 - digitIdx) shr Shift
  ].addr

  let shifted = byte((value and DigitMask) shl (BitSize*(digitIdx and WordMask)))
  slot[] = slot[] or shifted

func nDimMultiScalarRecoding*[M, L: static int](
    dst: var GLV_SAC[M, L],
    src: MultiScalar[M, L]) =
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
  # We modify Algorithm 1 with the last paragraph optimization suggestions:
  # - instead of ternary coding -1, 0, 1 (for negative, 0, positive)
  # - we use 0, 1 for (0, sign of column)
  #   and in the sign column 0, 1 for (positive, negative)

  # assert src[0].isOdd - Only happen on implementation error, we don't want to leak a single bit

  var k = src # Keep the source multiscalar in registers
  template b: untyped {.dirty.} = dst

  b[0][L-1] = 0 # means positive column
  for i in 0 .. L-2:
    b[0][i] = 1 - k[0].bit(i+1).uint8
  for j in 1 .. M-1:
    for i in 0 .. L-1:
      let bji = k[j].bit0.uint8
      b[j][i] = bji
      k[j].div2()
      k[j] += SecretWord (bji and b[0][i])

template buildEndoLookupTable*[M: static int, Group](
       P: Group,
       endomorphisms: array[M-1, Group],
       lut: var array[1 shl (M-1), Group],
       groupLawAdd: untyped) =
  ## Build the lookup table from the base element P
  ## and the group endomorphism
  ##
  ## Note:
  ##   The destination parameter is last so that the compiler can infer the value of M
  ##   It fails with 1 shl (M-1)
  #
  # Assuming elliptic curves
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
  #   and add to it the endomorphism at the index matching the MSB position
  #
  #   This scheme ensures 1 addition per table entry instead of a number
  #   of addition dependent on `u` Hamming Weight

  # Create the lookup-table in alternative coordinates
  lut[0] = P
  for u in 1'u32 ..< 1 shl (M-1):
    # The recoding allows usage of 2^(n-1) table instead of the usual 2^n with NAF
    let msb = u.log2_vartime() # No undefined, u != 0
    lut[u].groupLawAdd(lut[u.clearBit(msb)], endomorphisms[msb])

func getRecodedIndex*(glv: GLV_SAC, bit: int): SecretWord {.inline.} =
  ## Compose the secret table index from
  ## the GLV-SAC representation and the "bit" accessed
  staticFor i, 1, GLV_SAC.M:
    result = result or SecretWord((glv[i][bit] and 1) shl (i-1))

func getRecodedNegate*(glv: GLV_SAC, bit: int): SecretBool {.inline.} =
  SecretBool glv[0][bit]

func computeEndoRecodedLength*(bits, decomposition_dimension: int): int =
  bits.ceilDiv_vartime(decomposition_dimension) + 1

# Windowed GLV
# ----------------------------------------------------------------
# Config
# - 2 dimensional decomposition
# - Window of size 2
# -> precomputation 2^((2*2)-1) = 8

# Encoding explanation:
# - Coding is in big endian
#   digits are grouped 2-by-2
# - k0 column has the following sign and encoding
#   - `paper` -> `impl` is `value`
#   with ternary encoding from the paper and 𝟙 denoting -1
#   -  0t1𝟙   ->  0b01  is   1
#   -  0t11   ->  0b00  is   3
#   -  0t𝟙1   ->  0b10  is  -1
#   -  0t𝟙𝟙   ->  0b11  is  -3
# - if k0 == 1 (0t1𝟙 - 0b01) or -1 (0b10 - 0t0𝟙):
#   then kn is encoded with
#     (signed opposite 2-complement)
#   -  0t00   ->  0b00  is  0
#   -  0t0𝟙   ->  0b01  is -1
#   -  0t10   ->  0b10  is  2
#   -  0t1𝟙   ->  0b11  is  1
#   if k0 == 3 (0b00) or -3 (0b11):
#   then kn is encoded with
#     (unsigned integer)
#   -  0t00   ->  0b00  is  0
#   -  0t01   ->  0b01  is  1
#   -  0t10   ->  0b10  is  2
#   -  0t11   ->  0b11  is  3

template buildEndoLookupTable_m2w2*[Group](
       lut: var array[8, Group],
       P0, P1: Group,
       groupLawAdd, groupLawSub, groupLawDouble: untyped) =
  ## Build a lookup table for GLV with 2-dimensional decomposition
  ## and window of size 2

  # Create the lookup-table in alternative coordinates
  # with [k0, k1] the mini-scalars with digits of size 2-bit
  #
  # 4 = 0b100 - encodes [0b01, 0b00] ≡ P0
  lut[4] = P0
  # 5 = 0b101 - encodes [0b01, 0b01] ≡ P0 - P1
  lut[5].groupLawSub(lut[4], P1)
  # 7 = 0b111 - encodes [0b01, 0b11] ≡ P0 + P1
  lut[7].groupLawAdd(lut[4], P1)
  # 6 = 0b110 - encodes [0b01, 0b10] ≡ P0 + 2P1
  lut[6].groupLawAdd(lut[7], P1)

  # 0 = 0b000 - encodes [0b00, 0b00] ≡ 3P0
  lut[0].groupLawDouble(lut[4])
  lut[0].groupLawAdd(lut[0], lut[4])
  # 1 = 0b001 - encodes [0b00, 0b01] ≡ 3P0 + P1
  lut[1].groupLawAdd(lut[0], P1)
  # 2 = 0b010 - encodes [0b00, 0b10] ≡ 3P0 + 2P1
  lut[2].groupLawAdd(lut[1], P1)
  # 3 = 0b011 - encodes [0b00, 0b11] ≡ 3P0 + 3P1
  lut[3].groupLawAdd(lut[2], P1)

func w2Get(recoding: Recoded,
          digitIdx: int): uint8 {.inline.}=
  ## Window Get for window of size 2
  ## 0 <= digitIdx < LengthInDigits
  ## returns digit ∈ {0, 1}

  const
    wBitSize   = 2
    wWordMask  = sizeof(byte) * 8 div 2 - 1 #                            - In the word, shift to the offset to read/write
    wDigitMask = 1 shl wBitSize - 1         # Digits take 1-bit          - Once at location, isolate bits to read/write

  const len = Recoded.LengthInDigits
  # assert digitIdx * wBitSize < len, "digitIdx: " & $digitIdx & ", window: " & $wBitsize & ", len: " & $len

  let slot = distinctBase(recoding)[
    (len-1 - 2*digitIdx) shr Shift
  ]
  let recoded = slot shr (wBitSize*(digitIdx and wWordMask)) and wDigitMask
  return recoded

func getRecodedIndexW2*(glv: GLV_SAC, bit2: int, isNeg: var SecretBool): SecretWord {.inline.} =
  ## Compose the secret table index from
  ## the windowed of size 2 GLV-SAC representation and the "bit" accessed

  let k0 = glv[0].w2Get(bit2)
  let k1 = glv[1].w2Get(bit2)

  # assert k0 < 4 and k1 < 4

  isNeg = SecretBool(k0 shr 1)
  let parity = (k0 shr 1) xor (k0 and 1)
  result = SecretWord((parity shl 2) or k1)

func computeEndoWindowRecodedLength*(bitWidth, window: int): int =
  # Strangely in the paper this doesn't depend
  # "m", the GLV decomposition dimension.
  # lw = ⌈log2 r/w⌉+1 (optionally a second "+1" to handle negative mini scalars)
  let lw = bitWidth.ceilDiv_vartime(window) + 1
  result = (lw mod window) + lw
