# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard Library
  typetraits,
  # Internal
  ../primitives,
  ../config/[common, curves],
  ../arithmetic,
  ../towers,
  ./ec_weierstrass_affine,
  ./ec_weierstrass_projective

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
    ##      with all digits ∈ {1, −1}
    ## (iii) Other subscalars have digits  ∈ {0, 1, −1}
    ##
    ## We pack the representation, using 2 bits per digit:
    ##  0 = 0b00
    ##  1 = 0b01
    ## -1 = 0b11
    ##
    ## This means that GLV_SAC uses twice the size of a canonical integer
    ##
    ## Digit-Endianness is bigEndian

  MultiScalar[M, LengthInBits: static int] = array[M, BigInt[LengthInBits]]
    ## Decomposition of a secret scalar in multiple scalars

const
  BitSize   = 2
  Shift     = 2    # log2(4) - we can store 4 digit per byte
  ByteMask  = 3    # we need (mod 4) to access a packed bytearray
  DigitMask = 0b11 # Digits take 2-bit

# template signExtend_2bit(recoded: byte): int8 =
#   ## We need to extend:
#   ## - 0b00 to 0b0000_0000 ( 0)
#   ## - 0b01 to 0b0000_0001 ( 1)
#   ## - 0b11 to 0b1111_1111 (-1)
#   ##
#   ## This can be done by shifting left to have
#   ## - 0b00 to 0b0000_0000
#   ## - 0b01 to 0b0100_0000
#   ## - 0b11 to 0b1100_0000
#   ##
#   ## And then an arithmetic right shift (SAR)
#   ##
#   ## However there is no builtin SAR
#   ## we can get it in C by right-shifting
#   ## with the main compilers/platforms
#   ## (GCC, Clang, MSVC, ...)
#   ## but this is implementation defined behavior
#   ## Nim `ashr` uses C signed right shifting
#   ##
#   ## We could check the compiler to ensure we only use
#   ## well documented behaviors: https://gcc.gnu.org/onlinedocs/gcc/Integers-implementation.html#Integers-implementation
#   ## but if we can avoid that altogether in a crypto library
#   ##
#   ## Instead we use signed bitfield which are automatically sign-extended
#   ## in a portable way as sign extension is automatic for builtin types

type
  SignExtender = object
    ## Uses C builtin types sign extension to sign extend 2-bit to 8-bit
    ## in a portable way as sign extension is automatic for builtin types
    ## http://graphics.stanford.edu/~seander/bithacks.html#FixedSignExtend
    digit {.bitsize:2.}: int8


proc `[]`(recoding: Recoded,
          digitIdx: int): int8 {.inline.}=
  ## 0 <= digitIdx < LengthInDigits
  ## returns digit ∈ {0, 1, −1}
  const len = Recoded.LengthInDigits
  assert digitIdx < len

  let slot = distinctBase(recoding)[
    len-1 - (digitIdx shr Shift)
  ]
  let recoded = slot shr (BitSize*(digitIdx and ByteMask)) and DigitMask
  var signExtender: SignExtender
  # Hack with C assignment that return values
  {.emit: [result, " = ", signExtender, ".digit = ", recoded, ";"].}
  # " # Fix highlighting bug in VScode


proc `[]=`(recoding: var Recoded,
           digitIdx: int, value: int8) {.inline.}=
  ## 0 <= digitIdx < LengthInDigits
  ## returns digit ∈ {0, 1, −1}
  ## This is write-once
  const len = Recoded.LengthInDigits
  assert digitIdx < Recoded.LengthInDigits

  let slot = distinctBase(recoding)[
    len-1 - (digitIdx shr Shift)
  ].addr

  let shifted = byte((value and DigitMask) shl (BitSize*(digitIdx and ByteMask)))
  slot[] = slot[] or shifted


func nDimMultiScalarRecoding[M, LengthInBits, LengthInDigits: static int](
    dst: var GLV_SAC[M, LengthInDigits],
    src: MultiScalar[M, LengthInBits]
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
  # Input: m l-bit positive integers kj = (kj_l−1, ..., kj_0)_2 for
  # 0 ≤ j < m, an odd “sign-aligner” kJ ∈ {kj}^m, where
  # l = ⌈log2 r/m⌉ + 1, m is the GLV dimension and r is
  # the prime subgroup order.
  # Output: (bj_l−1 , ..., bj_0)GLV-SAC for 0 ≤ j < m, where
  # bJ_i ∈ {1, −1}, and bj_i ∈ {0, bJ_i} for 0 ≤ j < m with
  # j != J.
  # ------------------------------------------------------------------------
  #
  # 1: bJ_l-1 = 1
  # 2: for i = 0 to (l − 2) do
  # 3:   bJ_i = 2kJ_i+1 - 1
  # 4: for j = 0 to (m − 1), j != J do
  # 5:   for i = 0 to (l − 1) do
  # 6:     bj_i = bJ_i kj_0
  # 7:     kj = ⌊kj/2⌋ − ⌊bj_i/2⌋
  # 8: return (bj_l−1 , . . . , bj_0)_GLV-SAC for 0 ≤ j < m.
  #
  # - Guide to Pairing-based Cryptography
  #   Chapter 6: Scalar Multiplication and Exponentiation in Pairing Groups
  #   Joppe Bos, Craig Costello, Michael Naehrig
  #
  # We choose kJ = k0
  #
  # Implementation strategy and points of attention
  # - The subscalars kj must support extracting the least significant bit
  # - The subscalars kj must support floor division by 2
  #   For that floored division, kj is 0 or positive
  # - The subscalars kj must support individual bit accesses
  # - The subscalars kj must support addition by a small value (0 or 1)
  # Hence we choose to use our own BigInt representation.
  #
  # - The digit bji must support floor division by 2
  #   For that floored division, bji may be negative!!!
  # In particular floored division of -1 is -1 not 0.
  # This means that arithmetic right shift must be used instead of logical right shift
  static: doAssert LengthInDigits == LengthInBits + 1
  # assert src[0].isOdd - Only happen on implementation error, we don't want to leak a single bit

  var k = src # Keep the source multiscalar in registers
  template b: untyped {.dirty.} = dst

  b[0][LengthInDigits-1] = 1
  for i in 0 .. LengthInDigits-2:
    b[0][i] = 2 * k[0].bit(i+1).int8 - 1
  for j in 1 .. M-1:
    for i in 0 .. LengthInDigits-1:
      let bji = b[0][i] * k[j].bit0.int8
      b[j][i] = bji
      # In the following equation
      #   kj = ⌊kj/2⌋ − ⌊bj_i/2⌋
      # We have ⌊bj_i/2⌋ (floor division)
      # = -1 if bj_i == -1
      # = 0  if bj_i ∈ {0, 1}
      # So we turn that statement in an addition
      # by the opposite
      k[j].div2()
      k[j] += SecretWord -bji.ashr(1)


# Sanity checks
# ----------------------------------------------------------------

when isMainModule:
  import ../io/io_bigints


  proc toString(glvSac: GLV_SAC): string =
    for j in 0 ..< glvSac.M:
      result.add "k" & $j & ": ["
      for i in countdown(glvSac.LengthInDigits-1, 0):
        result.add " " & (block:
          case glvSac[j][i]
          of -1: "1\u{0305}"
          of 0: "0"
          of 1: "1"
          else:
            raise newException(ValueError, "Unexpected encoded value: " & $glvSac[j][i])
        ) # " # Unbreak VSCode highlighting bug
      result.add " ]\n"


  proc main() =
    var k: MultiScalar[4, 4]
    var kRecoded: GLV_SAC[4, 5]

    k[0].fromUint(11)
    k[1].fromUint(6)
    k[2].fromuint(14)
    k[3].fromUint(3)

    kRecoded.nDimMultiScalarRecoding(k)

    echo kRecoded.toString()

  main()
