# Research into the paper

# - Efficient and Secure Algorithms for GLV-Based Scalar
#   Multiplication and their Implementation on GLV-GLS
#   Curves (Extended Version)
#   Armando Faz-Hernández, Patrick Longa, Ana H. Sánchez, 2013
#   https://eprint.iacr.org/2013/158.pdf

import constantine/math/endomorphisms/split_scalars {.all.},
       constantine/platforms/abstractions,
       constantine/math/io/io_bigints,
       constantine/math/arithmetic

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
      )
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
    let msb = u.log2_vartime() # No undefined, u != 0
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

  echo "Recoded bytesize: ", sizeof(kRecoded)
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
    let msb = u.log2_vartime() # No undefined, u != 0
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
echo "---------------------------------------------"

func buildLookupTable_m2w2(
      lut: var array[8, array[2, int]],
    ) =
  ## Build a lookup table for GLV with 2-dimensional decomposition
  ## and window of size 2

  # with [k0, k1] the mini-scalars with digits of size 2-bit
  #
  # 0 = 0b000 - encodes [0b01, 0b00] ≡ P0
  lut[0] = [1, 0]
  # 1 = 0b001 - encodes [0b01, 0b01] ≡ P0 - P1
  lut[1] = [1, -1]
  # 3 = 0b011 - encodes [0b01, 0b11] ≡ P0 + P1
  lut[3] = [1, 1]
  # 2 = 0b010 - encodes [0b01, 0b10] ≡ P0 + 2P1
  lut[2] = [1, 2]

  # 4 = 0b100 - encodes [0b00, 0b00] ≡ 3P0
  lut[4] = [3, 0]
  # 5 = 0b101 - encodes [0b00, 0b01] ≡ 3P0 + P1
  lut[5] = [3, 1]
  # 6 = 0b110 - encodes [0b00, 0b10] ≡ 3P0 + 2P1
  lut[6] = [3, 2]
  # 7 = 0b111 - encodes [0b00, 0b11] ≡ 3P0 + 3P1
  lut[7] = [3, 3]

proc mainFullMulWindowed() =
  const M = 2                # GLS-2 decomposition
  const miniBitwidth = 8     # Bitwidth of the miniscalars resulting from scalar decomposition
  const W = 2                # Window
  const L = computeEndoWindowRecodedLength(miniBitwidth, W)

  var k: MultiScalar[M, L]
  var kRecoded: GLV_SAC[M, L]

  k[0].fromUint(11)
  k[1].fromUint(14)

  kRecoded.nDimMultiScalarRecoding(k)

  echo "Recoded bytesize: ", sizeof(kRecoded)
  echo kRecoded.toString()

  var lut: array[8, array[range[P0..P1], int]]
  buildLookupTable_m2w2(lut)
  echo lut

  # Assumes k[0] is odd to simplify test
  # and having to conditional substract at the end
  assert bool k[0].isOdd()

  var Q: array[Endo, int]
  var isNeg: SecretBool

  let idx = kRecoded.w2TableIndex((L div 2)-1, isNeg)
  for p, coef in lut[int(idx)]:
    # Unneeeded by construction
    # let sign = if isNeg: -1 else: 1
    Q[p] = coef

  # Loop
  for i in countdown((L div 2)-2, 0):
    # Q = 4Q
    for val in Q.mitems: val *= 4
    echo "4Q:                    ", Q
    # Q = Q + sign_l-1 P[K_l-1]
    let idx = kRecoded.w2TableIndex(i, isNeg)
    for p, coef in lut[int(idx)]:
      let sign = (if bool isNeg: -1 else: 1)
      Q[p] += sign * coef
    echo "Q + sign_l-1 P[K_l-1]: ", Q

  echo Q

mainFullMulWindowed()
