# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#              Variable-time extended-precision
#                    compiler intrinsics
#
# ############################################################

import ../abstractions

func div2n1n_nim_vartime[T: SomeUnsignedInt](q, r: var T, n_hi, n_lo, d: T) {.used, tags:[VarTime].}=
  ## Division uint128 by uint64 or uint64 by uint32
  ## Warning ⚠️ :
  ##   - if n_hi == d, quotient does not fit in an uint64 and will throw SIGFPE
  ##   - if n_hi > d result is undefined

  # doAssert leadingZeros(d) == 0, "Divisor was not normalized"

  const
    size = sizeof(q) * 8
    halfSize = size div 2
    halfMask = (1.T shl halfSize) - 1.T

  func halfQR(n_hi, n_lo, d, d_hi, d_lo: T): tuple[q, r: T] {.nimcall.} =

    var (q, r) = (n_hi div d_hi, n_hi mod d_hi)
    let m = q * d_lo
    r = (r shl halfSize) or n_lo

    # Fix the reminder, we're at most 2 iterations off
    if r < m:
      dec q
      r += d
      if r >= d and r < m:
        dec q
        r += d
    r -= m
    (q, r)

  let
    d_hi = d shr halfSize
    d_lo = d and halfMask
    n_lohi = n_lo shr halfSize
    n_lolo = n_lo and halfMask

  # First half of the quotient
  let (q1, r1) = halfQR(n_hi, n_lohi, d, d_hi, d_lo)

  # Second half
  let (q2, r2) = halfQR(r1, n_lolo, d, d_hi, d_lo)

  q = (q1 shl halfSize) or q2
  r = r2

when not(CTT_32) and defined(vcc):
  func udiv128_vartime(highDividend, lowDividend, divisor: uint64, remainder: var uint64): uint64 {.importc:"_udiv128", header: "<intrin.h>", nodecl, tags:[VarTime].}
    ## Division 128 by 64, Microsoft only, 64-bit only,
    ## returns quotient as return value remainder as var parameter
    ## Warning ⚠️ :
    ##   - if n_hi == d, quotient does not fit in an uint64 and will throw SIGFPE
    ##   - if n_hi > d result is undefined

  func div2n1n_128_vartime(q, r: var uint64, n_hi, n_lo, d: uint64) {.inline.}=
      ## Division uint128 by uint64
      ## Warning ⚠️ :
      ##   - if n_hi == d, quotient does not fit in an uint64 and will throw SIGFPE
      ##   - if n_hi > d result is undefined
      q = udiv128_vartime(n_hi, n_lo, d, r)

elif not(CTT_32) and GCC_Compatible:
  type
    uint128{.importc: "unsigned __int128".} = object

  const
    newerNim = (NimMajor, NimMinor) > (1, 6)
    noExplicitPtrDeref = defined(cpp) or newerNim

  func div2n1n_128_vartime(q, r: var uint64, n_hi, n_lo, d: uint64) {.inline, tags:[VarTime].}=
    ## Division uint128 by uint64
    ## Warning ⚠️ :
    ##   - if n_hi == d, quotient does not fit in an uint64 and will throw SIGFPE on some platforms
    ##   - if n_hi > d result is undefined
    var dblPrec {.noinit.}: uint128
    {.emit:[dblPrec, " = (unsigned __int128)", n_hi," << 64 | (unsigned __int128)",n_lo,";"].}

    # Don't forget to dereference the var param in C mode
    when noExplicitPtrDeref:
      {.emit:[q, " = (NU64)(", dblPrec," / ", d, ");"].}
      {.emit:[r, " = (NU64)(", dblPrec," % ", d, ");"].}
    else:
      {.emit:["*",q, " = (NU64)(", dblPrec," / ", d, ");"].}
      {.emit:["*",r, " = (NU64)(", dblPrec," % ", d, ");"].}


func div2n1n_vartime*(q, r: var SecretWord, n_hi, n_lo, d: SecretWord) {.inline.} =
  ## Division uint128 by uint64
  ## Warning ⚠️ :
  ##   - if n_hi == d, quotient does not fit in an uint64 and will throw SIGFPE
  ##   - if n_hi > d result is undefined
  ##
  ## To avoid issues, n_hi, n_lo, d should be normalized.
  ## i.e. shifted (== multiplied by the same power of 2)
  ## so that the most significant bit in d is set.
  when CTT_32:
    let dividend = (uint64(n_hi) shl 32) or uint64(n_lo)
    let divisor = uint64(d)
    q = SecretWord(dividend div divisor)
    r = SecretWord(dividend mod divisor)
  else:
    when nimvm:
      div2n1n_nim_vartime(BaseType q, BaseType r, BaseType n_hi, BaseType n_lo, BaseType d)
    else:
      when declared(div2n1n_128_vartime):
        div2n1n_128_vartime(BaseType q, BaseType r, BaseType n_hi, BaseType n_lo, BaseType d)
      else:
        div2n1n_nim_vartime(BaseType q, BaseType r, BaseType n_hi, BaseType n_lo, BaseType d)
