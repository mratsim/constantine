# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/abstractions,
  ./limbs

when UseASM_X86_64:
  import ./assembly/limbs_asm_mul_x86
  import ./assembly/limbs_asm_mul_x86_adx_bmi2

# ############################################################
#
#         Limbs raw representation and operations
#
# ############################################################

# Inlining note:
# - The public dispatch functions are inlined.
#   This allows the compiler to check CPU features only once
#   in the high-level proc and also removes an intermediate function call
#   to the wrapper function
# - The ASM procs or internal fallbacks are not inlined
#   to save on code size.

# No exceptions allowed
{.push raises: [].}

# Multiplication
# ------------------------------------------------------------

func prod_comba[rLen, aLen, bLen: static int](r: var Limbs[rLen], a: Limbs[aLen], b: Limbs[bLen]) =
  ## Extended precision multiplication
  ## `r` must not alias ``a`` or ``b``
  # We use Product Scanning / Comba multiplication
  var t, u, v = Zero
  const stopEx = min(a.len+b.len, r.len)

  staticFor i, 0, stopEx:
    # Invariant for product scanning:
    # if we multiply accumulate by a[k1] * b[k2]
    # we have k1+k2 == i
    const ib = min(b.len-1, i)
    const ia = i - ib
    staticFor j, 0, min(a.len - ia, ib+1):
      mulAcc(t, u, v, a[ia+j], b[ib-j])

    r[i] = v
    when i < stopEx-1:
      v = u
      u = t
      t = Zero

  for i in aLen+bLen ..< rLen:
    r[i] = Zero

func prod*[rLen, aLen, bLen: static int](r{.noalias.}: var Limbs[rLen], a: Limbs[aLen], b: Limbs[bLen]) {.inline.} =
  ## Multi-precision multiplication
  ## r <- a*b
  ##
  ## `a`, `b`, `r` can have a different number of limbs
  ## if `r`.limbs.len < a.limbs.len + b.limbs.len
  ## The result will be truncated, i.e. it will be
  ## a * b (mod (2^WordBitWidth)^r.limbs.len)
  ##
  ## `r` must not alias ``a`` or ``b``

  when UseASM_X86_64 and aLen <= 6:
    # ADX implies BMI2
    if ({.noSideEffect.}: hasAdx()):
      mul_asm_adx(r, a, b)
    else:
      mul_asm(r, a, b)
  elif UseASM_X86_64:
    mul_asm(r, a, b)
  else:
    prod_comba(r, a, b)

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
  ## a * b >> (2^WordBitWidth)^lowestWordIndex (mod (2^WordBitWidth)^r.limbs.len)
  #
  # This is useful for
  # - Barret reduction
  # - Approximating multiplication by a fractional constant in the form f(a) = K/C * a
  #   with K and C known at compile-time.
  #   We can instead find a well chosen M = (2^WordBitWidth)ʷ, with M > C (i.e. M is a power of 2 bigger than C)
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

func square_Comba[rLen, aLen](
       r: var Limbs[rLen],
       a: Limbs[aLen]) =
  ## Multi-precision squaring using Comba / Product Scanning
  var t, u, v = Zero
  const stopEx = min(a.len * 2, r.len)

  staticFor i, 0, stopEx:
    # Invariant for product scanning:
    # if we multiply accumulate by a[k1] * a[k2]
    # we have k1+k2 == i
    const ib = min(a.len-1, i)
    const ia = i - ib
    staticFor j, 0, min(a.len - ia, ib+1):
      const k1 = ia+j
      const k2 = ib-j
      when k1 < k2:
        mulDoubleAcc(t, u, v, a[k1], a[k2])
      elif k1 == k2:
        mulAcc(t, u, v, a[k1], a[k2])
      else:
        discard

    r[i] = v
    when i < stopEx-1:
      v = u
      u = t
      t = Zero

  for i in aLen*2 ..< rLen:
    r[i] = Zero

func square_operandScan[rLen, aLen](
       r: var Limbs[rLen],
       a: Limbs[aLen]) {.used.} =
  ## Multi-precision squaring using Operand Scanning
  const stopEx = min(a.len * 2, r.len)
  var t: typeof(r) # zero-init, ensure on stack
  var C = Zero
  static: doAssert aLen * 2 == rLen, "Truncated square operand scanning is not implemented"

  staticFor i, 0, stopEx:
    staticFor j, i+1, stopEx:
      muladd2(C, t[i+j], a[j], a[i], t[i+j], C)
    t[i+stopEx] = C

  staticFor i, 0, aLen:
    # (t[2*i+1], t[2*i]) <- 2*t[2*i] + a[i]*a[i]
    var u, v = Zero
    var carry: Carry
    # a[i] * a[i]
    mul(u, v, a[i], a[i])
    # 2*t[2*i]
    addC(carry, t[2*i], t[2*i], t[2*i], Carry(0))
    addC(carry, t[2*i+1], Zero, Zero, carry)
    # 2*t[2*i] + a[i] * a[i]
    addC(carry, t[2*i], t[2*i], u, Carry(0))
    addC(carry, t[2*i+1], Zero, v, carry)

  r = t

func square*[rLen, aLen](
       r: var Limbs[rLen],
       a: Limbs[aLen]) {.inline.} =
  ## Multi-precision squaring
  ## r <- a²
  ##
  ## if `r`.limbs.len < a.limbs.len * 2
  ## The result will be truncated, i.e. it will be
  ## a² (mod (2^WordBitWidth)^r.limbs.len)
  ##
  ## `r` must not alias ``a`` or ``b``
  when UseASM_X86_64 and aLen in {4, 6} and rLen == 2*aLen:
    # ADX implies BMI2
    if ({.noSideEffect.}: hasAdx()):
      square_asm_adx(r, a)
    else:
      square_asm(r, a)
  elif UseASM_X86_64:
    square_asm(r, a)
  else:
    square_comba(r, a)
