# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                 Field arithmetic over Fp
#
# ############################################################

# We assume that p is prime known at compile-time

import ./word_types, ./bigints, ./curves_config
from ./private/word_types_internal import unsafe_div2n1n

type
  Fp*[C: static Curve] = object
    ## P is the prime modulus of the Curve C
    ## All operations on a field are modulo P
    value: BigInt[CurveBitSize[C]]

  Montgomery*[C: static Curve] = object
    ## P is the prime modulus of the Curve C
    ## All operations in the Montgomery domain are modulo P
    ## P **must** be odd
    value: BigInt[CurveBitSize[C]]

# ############################################################
#
#                         Aliases
#
# ############################################################

const
  CtTrue* = ctrue(Word)
  CtFalse* = cfalse(Word)

template add(a: var Fp, b: Fp, ctl: CTBool[Word]): CTBool[Word] =
  add(a.value, b.value, ctl)

template sub(a: var Fp, b: Fp, ctl: CTBool[Word]): CTBool[Word] =
  sub(a.value, b.value, ctl)

template `[]`(a: Fp, idx: int): Word =
  a.value.limbs[idx]

# ############################################################
#
#                Field arithmetic primitives
#
# ############################################################

func `+`*(a, b: Fp): Fp =
  ## Addition over Fp

  # Non-CT implementation from Stint
  #
  # let b_from_p = p - b    # Don't do a + b directly to avoid overflows
  # if a >= b_from_p:
  #   return a - b_from_p
  # return m - b_from_p + a

  result = a
  var ctl = add(result, b, CtTrue)
  ctl = ctl or not sub(result, Fp.C.Mod, CtFalse)
  sub(result, Fp.C.Mod, ctl)

func shiftAdd*(a: var Fp, c: Word) =
  ## Shift-accumulate
  ## Shift input `a` by a word and add `c`.
  ##
  ## With a word W = 2^WordBitSize and a field Fp
  ## Does a <- a * W + c (mod p)
  const len = a.value.limbs.len

  when Fp.C.Mod.bits <= WordBitSize:
    # If the prime fits in a single limb
    var q: Word

    # (hi, lo) = a * 2^63 + c
    let hi = a[0] shr 1                               # 64 - 63 = 1
    let lo = (a[0] shl WordBitSize) or c              # Assumes most-significant bit in c is not set
    unsafeDiv2n1n(q, a[0], hi, lo, Fp.C.Mod.limbs[0]) # (hi, lo) mod P
    return

  else:
    ## Multiple limbs
    let hi = a[^1]                                 # Save the high word to detect carries
    const R = Fp.C.Mod.bits and WordBitSize        # R = bits mod 64

    when R == 0:                                   # If the number of bits is a multiple of 64
      let a1 = a[^2]                               #
      let a0 = a[^1]                               #
      moveMem(a[1], a[0], (len-1) * Word.sizeof)   # we can just shift words
      a[0] = c                                     # and replace the first one by c
      const p0 = Fp.C.Mod[^1]
    else:                                          # Need to deal with partial word shifts at the edge.
      let a1 = ((a[^2] shl (WordBitSize-R)) or (a[^3] shr R)) and MaxWord
      let a0 = ((a[^1] shl (WordBitSize-R)) or (a[^2] shr R)) and MaxWord
      moveMem(a[1], a[0], (len-1) * Word.sizeof)
      a[0] = c
      const p0 = ((Fp.C.Mod[^1] shl (WordBitSize-R)) or (Fp.C.Mod[^2] shr R)) and MaxWord

    # p0 has its high bit set. (a0, a1)/p0 fits in a limb.
    # Get a quotient q, at most we will be 2 iterations off
    # from the true quotient

    let
      a_hi = a0 shr 1                              # 64 - 63 = 1
      a_lo = (a0 shl WordBitSize) or a1
    var q, r: Word
    q = unsafeDiv2n1n(q, r, a_hi, a_lo, p0)        # Estimate quotient
    q = mux(                                       # If n_hi == divisor
          a0 == b0, MaxWord,                       # Quotient == MaxWord (0b0111...1111)
          mux(
            q == 0, 0,                             # elif q == 0, true quotient = 0
            q - 1                                  # else instead of being of by 0, 1 or 2
          )                                        # we returning q-1 to be off by -1, 0 or 1
        )

    # Now substract a*2^63 - q*p
    var carry = Word(0)
    var over_p = Word(1)                           # Track if quotient than the modulus

    for i in static(0 ..< Fp.C.Mod.limbs.len):
      var qp_lo: Word

      block: # q*p
        qp_hi: Word
        unsafeExtendedPrecMul(qp_hi, qp_lo, q, Fp.C.Mod[i]) # q * p
        assert qp_lo.isMsbSet.not
        assert carry.isMsbSet.not
        qp_lo += carry                                      # Add carry from previous limb
        let qp_carry = qp_lo.isMsbSet
        carry = mux(qp_carry, qp_hi + Word(1), qp_hi)       # New carry

        qp_lo = qp_lo and MaxWord                           # Normalize to u63

      block: # a*2^63 - q*p
        a[i] -= qp_lo
        carry += Word(a[i].isMsbSet)                        # Adjust if borrow
        a[i] = a[i] and MaxWord                             # Normalize to u63

      over_p = mux(
                a[i] == Fp.C.Mod[i], over_p,
                a[i] > Fp.C.Mod[i]
              )

    # Fix quotient, the true quotient is either q-1, q or q+1
    #
    # if carry < q or carry == q and over_p we must do "a -= p"
    # if carry > hi (negative result) we must do "a+= p"

    let neg = carry < hi
    let tooBig = not neg and (over_p or (carry < hi))

    add(a, Fp.C.Mod, neg)
    sub(a, Fp.C.Mod, tooBig)
    return
