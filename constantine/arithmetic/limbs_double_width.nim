# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/common,
  ../primitives,
  ./limbs

when UseASM_X86_32:
  import ./assembly/limbs_asm_montred_x86
when UseASM_X86_64:
  import ./assembly/limbs_asm_montred_x86_adx_bmi2
  import ./assembly/limbs_asm_mul_x86
  import ./assembly/limbs_asm_mul_x86_adx_bmi2

# ############################################################
#
#         Limbs raw representation and operations
#
# ############################################################

# No exceptions allowed
{.push raises: [].}

# Multiplication
# ------------------------------------------------------------

func prod*[rLen, aLen, bLen: static int](r: var Limbs[rLen], a: Limbs[aLen], b: Limbs[bLen]) =
  ## Multi-precision multiplication
  ## r <- a*b
  ##
  ## `a`, `b`, `r` can have a different number of limbs
  ## if `r`.limbs.len < a.limbs.len + b.limbs.len
  ## The result will be truncated, i.e. it will be
  ## a * b (mod (2^WordBitwidth)^r.limbs.len)
  ##
  ## `r` must not alias ``a`` or ``b``

  when UseASM_X86_64 and aLen <= 6:
    if ({.noSideEffect.}: hasBmi2()) and ({.noSideEffect.}: hasAdx()):
      mul_asm_adx_bmi2(r, a, b)
    else:
      mul_asm(r, a, b)
  elif UseASM_X86_64:
    mul_asm(r, a, b)
  else:
    # We use Product Scanning / Comba multiplication
    var t, u, v = Zero
    const stopEx = min(a.len+b.len, r.len)

    staticFor i, 0, stopEx:
      const ib = min(b.len-1, i)
      const ia = i - ib
      staticFor j, 0, min(a.len - ia, ib+1):
        mulAcc(t, u, v, a[ia+j], b[ib-j])

      r[i] = v
      when i < stopEx-1:
        v = u
        u = t
        t = Zero

    if aLen+bLen < rLen:
      for i in aLen+bLen ..< rLen:
        r[i] = Zero

func prod_high_words*[rLen, aLen, bLen](
       r: var Limbs[rLen],
       a: Limbs[aLen], b: Limbs[bLen],
       lowestWordIndex: static int) =
  ## Multi-precision multiplication keeping only high words
  ## r <- a*b >> (2^WordBitWidth)^lowestWordIndex
  ##
  ## `a`, `b`, `r` can have a different number of limbs
  ## if `r`.limbs.len < a.limbs.len + b.limbs.len - lowestWordIndex
  ## The result will be truncated, i.e. it will be
  ## a * b >> (2^WordBitWidth)^lowestWordIndex (mod (2^WordBitwidth)^r.limbs.len)
  #
  # This is useful for
  # - Barret reduction
  # - Approximating multiplication by a fractional constant in the form f(a) = K/C * a
  #   with K and C known at compile-time.
  #   We can instead find a well chosen M = (2^WordBitWidth)^w, with M > C (i.e. M is a power of 2 bigger than C)
  #   Precompute P = K*M/C at compile-time
  #   and at runtime do P*a/M <=> P*a >> (WordBitWidth*w)
  #   i.e. prod_high_words(result, P, a, w)

  # We use Product Scanning / Comba multiplication
  var t, u, v = Zero # Will raise warning on empty iterations
  var z: Limbs[rLen] # zero-init, ensure on stack and removes in-place problems

  # The previous 2 columns can affect the lowest word due to carries
  # but not the ones before (we accumulate in 3 words (t, u, v))
  const w = lowestWordIndex - 2
  const stopEx = min(a.len+b.len, r.len+lowestWordIndex)

  staticFor i, max(0, w), stopEx:
    const ib = min(b.len-1, i)
    const ia = i - ib
    staticFor j, 0, min(a.len - ia, ib+1):
      mulAcc(t, u, v, a[ia+j], b[ib-j])

    when i >= lowestWordIndex:
      z[i-lowestWordIndex] = v
    when i < stopEx-1:
      v = u
      u = t
      t = Zero

  r = z

# Montgomery Reduction
# ------------------------------------------------------------
# This is the reduction part of SOS (Separated Operand Scanning) modular multiplication technique

# TODO upstream, using Limbs[N] breaks semcheck
func montyRed*[N: static int](
       r: var array[N, SecretWord],
       t: array[N*2, SecretWord],
       M: array[N, SecretWord],
       m0ninv: BaseType, canUseNoCarryMontyMul: static bool) =
  ## Montgomery reduce a double-width bigint modulo M
  # - Analyzing and Comparing Montgomery Multiplication Algorithms
  #   Cetin Kaya Koc and Tolga Acar and Burton S. Kaliski Jr.
  #   http://pdfs.semanticscholar.org/5e39/41ff482ec3ee41dc53c3298f0be085c69483.pdf
  #
  # - Arithmetic of Finite Fields
  #   Chapter 5 of Guide to Pairing-Based Cryptography
  #   Jean Luc Beuchat, Luis J. Dominguez Perez, Sylvain Duquesne, Nadia El Mrabet, Laura Fuentes-Castañeda, Francisco Rodríguez-Henríquez, 2017
  #   https://www.researchgate.net/publication/319538235_Arithmetic_of_Finite_Fields
  #
  # Algorithm
  # Inputs:
  # - N number of limbs
  # - t[0 ..< 2N] (double-width input to reduce)
  # - M[0 ..< N] The field modulus (must be odd for Montgomery reduction)
  # - m0ninv: Montgomery Reduction magic number = -1/M[0]
  # Output:
  # - r[0 ..< N], in the Montgomery domain
  # Parameters:
  # - w, the word width usually 64 on 64-bit platforms or 32 on 32-bit
  #
  # for i in 0 .. n-1:
  #   C <- 0
  #   m <- t[i] * m0ninv mod 2^w (i.e. simple multiplication)
  #   for j in 0 .. n-1:
  #     (C, S) <- t[i+j] + m * M[j] + C
  #     t[i+j] <- S
  #   t[i+n] += C
  # for i in 0 .. n-1:
  #   r[i] = t[i+n]
  # if r >= M:
  #   r -= M
  #
  # Important note: `t[i+n] += C` should propagate the carry
  # to the higher limb if any, thank you "implementation detail"
  # missing from paper.
  when UseASM_X86_64 and r.len <= 6:
    if ({.noSideEffect.}: hasBmi2()) and ({.noSideEffect.}: hasAdx()):
      montRed_asm_adx_bmi2(r, t, M, m0ninv, canUseNoCarryMontyMul)
    else:
      montRed_asm(r, t, M, m0ninv, canUseNoCarryMontyMul)
  elif UseASM_X86_32 and r.len <= 6:
    # TODO: Assembly faster than GCC but slower than Clang
    montRed_asm(r, t, M, m0ninv, canUseNoCarryMontyMul)
  else:
    var t = t          # Copy "t" for mutation and ensure on stack
    var res: typeof(r) # Accumulator
    staticFor i, 0, N:
      var C = Zero
      let m = t[i] * SecretWord(m0ninv)
      staticFor j, 0, N:
        muladd2(C, t[i+j], m, M[j], t[i+j], C)
      res[i] = C

    # This does t[i+n] += C
    # but in a separate carry chain, fused with the
    # copy "r[i] = t[i+n]"
    var carry = Carry(0)
    staticFor i, 0, N:
      addC(carry, res[i], t[i+N], res[i], carry)

    # Final substraction
    discard res.csub(M, SecretWord(carry).isNonZero() or not(res < M))
    r = res
