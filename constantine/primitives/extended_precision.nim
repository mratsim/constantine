# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#  Unsafe constant-time primitives with specific restrictions
#
# ############################################################

import ./constant_time

# ############################################################
#
#                     32-bit words
#
# ############################################################

func unsafeDiv2n1n*(q, r: var Ct[uint32], n_hi, n_lo, d: Ct[uint32]) {.inline.}=
  ## Division uint64 by uint32
  ## Warning ⚠️ :
  ##   - if n_hi == d, quotient does not fit in an uint32
  ##   - if n_hi > d result is undefined
  ##
  ## To avoid issues, n_hi, n_lo, d should be normalized.
  ## i.e. shifted (== multiplied by the same power of 2)
  ## so that the most significant bit in d is set.
  # TODO !!! - Replace by constant-time, portable, non-assembly version
  #          -> use uint128? Compiler might add unwanted branches
  {.warning: "unsafeDiv2n1n is not constant-time at the moment on most hardware".}
  let dividend = (uint64(n_hi) shl 32) or uint64(n_lo)
  let divisor = uint64(d)
  q = (Ct[uint32])(dividend div divisor)
  r = (Ct[uint32])(dividend mod divisor)

func unsafeFMA*(hi, lo: var Ct[uint32], a, b, c: Ct[uint32]) {.inline.} =
  ## Extended precision multiplication + addition
  ## This is constant-time on most hardware except some specific one like Cortex M0
  ## (hi, lo) <- a*b + c
  block:
    # Note: since a and b use 31-bit,
    # the result is 62-bit and carrying cannot overflow
    let dblPrec = uint64(a) * uint64(b) + uint64(c)
    hi = Ct[uint32](dblPrec shr 31)
    lo = Ct[uint32](dblPrec) and Ct[uint32](1 shl 31 - 1)

func unsafeFMA2*(hi, lo: var Ct[uint32], a1, b1, a2, b2, c1, c2: Ct[uint32]) {.inline.}=
  ## (hi, lo) <- a1 * b1 + a2 * b2 + c1 + c2
  block:
    # TODO: Can this overflow?
    let dblPrec = uint64(a1) * uint64(b1) +
                  uint64(a2) * uint64(b2) +
                  uint64(c1) +
                  uint64(c2)
    hi = Ct[uint32](dblPrec shr 31)
    lo = Ct[uint32](dblPrec) and Ct[uint32](1 shl 31 - 1)

func unsafeFMA2_hi*(hi: var Ct[uint32], a1, b1, a2, b2, c1: Ct[uint32]) {.inline.}=
  ## Returns the high word of the sum of extended precision multiply-adds
  ## (hi, _) <- a1 * b1 + a2 * b2 + c
  block:
    # TODO: Can this overflow?
    let dblPrec = uint64(a1) * uint64(b1) +
                  uint64(a2) * uint64(b2) +
                  uint64(c1)
    hi = Ct[uint32](dblPrec shr 31)

# ############################################################
#
#                     64-bit words
#
# ############################################################

const GccCompatible = defined(gcc) or defined(clang) or defined(llvm_gcc)

when sizeof(int) == 8 and GccCompatible:
  type
    uint128*{.importc: "unsigned __int128".} = object

  func unsafeDiv2n1n*(q, r: var Ct[uint64], n_hi, n_lo, d: Ct[uint64]) {.inline.}=
    ## Division uint128 by uint64
    ## Warning ⚠️ :
    ##   - if n_hi == d, quotient does not fit in an uint64 and will throw SIGFPE
    ##   - if n_hi > d result is undefined
    {.warning: "unsafeDiv2n1n is not constant-time at the moment on most hardware".}

    # TODO !!! - Replace by constant-time, portable, non-assembly version
    #          -> use uint128? Compiler might add unwanted branches

    # DIV r/m64
    # Divide RDX:RAX (n_hi:n_lo) by r/m64
    #
    # Inputs
    #   - numerator high word in RDX,
    #   - numerator low word in RAX,
    #   - divisor as r/m parameter (register or memory at the compiler discretion)
    # Result
    #   - Quotient in RAX
    #   - Remainder in RDX

    # 1. name the register/memory "divisor"
    # 2. don't forget to dereference the var hidden pointer
    # 3. -
    # 4. no clobbered registers beside explectly used RAX and RDX
    when defined(amd64):
      asm """
        divq %[divisor]
        : "=a" (`*q`), "=d" (`*r`)
        : "d" (`n_hi`), "a" (`n_lo`), [divisor] "rm" (`d`)
        :
      """
    else:
      var dblPrec {.noInit.}: uint128
      {.emit:[dblPrec, " = (unsigned __int128)", n_hi," << 64 | (unsigned __int128)",n_lo,";"].}

      # Don't forget to dereference the var param
      {.emit:["*",q, " = (NU64)(", dblPrec," / ", d, ");"].}
      {.emit:["*",r, " = (NU64)(", dblPrec," % ", d, ");"].}

  func unsafeFMA*(hi, lo: var Ct[uint64], a, b, c: Ct[uint64]) {.inline.}=
    ## Extended precision multiplication + addition
    ## This is constant-time on most hardware except some specific one like Cortex M0
    ## (hi, lo) <- a*b + c
    block:
      # Note: since a and b use 63-bit,
      # the result is 126-bit and carrying cannot overflow
      var dblPrec {.noInit.}: uint128
      {.emit:[dblPrec, " = (unsigned __int128)", a," * (unsigned __int128)", b, " + (unsigned __int128)",c,";"].}

      # Don't forget to dereference the var param
      {.emit:["*",hi, " = (NU64)(", dblPrec," >> ", 63'u64, ");"].}
      {.emit:["*",lo, " = (NU64)", dblPrec," & ", 1'u64 shl 63 - 1, ";"].}

  func unsafeFMA2*(hi, lo: var Ct[uint64], a1, b1, a2, b2, c1, c2: Ct[uint64]) {.inline.}=
    ## (hi, lo) <- a1 * b1 + a2 * b2 + c1 + c2
    block:
      # TODO: Can this overflow?
      var dblPrec: uint128
      {.emit:[dblPrec, " = (unsigned __int128)", a1," * (unsigned __int128)", b1,
                       " + (unsigned __int128)", a2," * (unsigned __int128)", b2,
                       " + (unsigned __int128)", c1,
                       " + (unsigned __int128)", c2, ";"].}
      # Don't forget to dereference the var param
      {.emit:["*",hi, " = (NU64)(", dblPrec," >> ", 63'u64, ");"].}
      {.emit:["*",lo, " = (NU64)", dblPrec," & ", (1'u64 shl 63 - 1), ";"].}

  func unsafeFMA2_hi*(hi: var Ct[uint64], a1, b1, a2, b2, c: Ct[uint64]) {.inline.}=
    ## Returns the high word of the sum of extended precision multiply-adds
    ## (hi, _) <- a1 * b1 + a2 * b2 + c
    block:
      var dblPrec: uint128
      {.emit:[dblPrec, " = (unsigned __int128)", a1," * (unsigned __int128)", b1,
                       " + (unsigned __int128)", a2," * (unsigned __int128)", b2,
                       " + (unsigned __int128)", c, ";"].}
      # Don't forget to dereference the var param
      {.emit:["*",hi, " = (NU64)(", dblPrec," >> ", 63'u64, ");"].}

elif sizeof(int) == 8 and defined(vcc):
  func udiv128(highDividend, lowDividend, divisor: uint64, remainder: var uint64): uint64 {.importc:"_udiv128", header: "<immintrin.h>", nodecl.}
    ## Division 128 by 64, Microsoft only, 64-bit only,
    ## returns quotient as return value remainder as var parameter
    ## Warning ⚠️ :
    ##   - if n_hi == d, quotient does not fit in an uint64 and will throw SIGFPE
    ##   - if n_hi > d result is undefined

  func unsafeDiv2n1n*(q, r: var Ct[uint64], n_hi, n_lo, d: Ct[uint64]) {.inline.}=
      ## Division uint128 by uint64
      ## Warning ⚠️ :
      ##   - if n_hi == d, quotient does not fit in an uint64 and will throw SIGFPE
      ##   - if n_hi > d result is undefined
      {.warning: "unsafeDiv2n1n is not constant-time at the moment on most hardware".}

      # TODO !!! - Replace by constant-time, portable, non-assembly version
      #          -> use uint128? Compiler might add unwanted branches
      q = udiv128(n_hi, n_lo, d, r)

  func addcarry_u64(carryIn: cuchar, a, b: uint64, sum: var uint64): cuchar {.importc:"_addcarry_u64", header:"<intrin.h>", nodecl.}
    ## (CarryOut, Sum) <-- a + b
    ## Available on MSVC and ICC (Clang and GCC have very bad codegen, use uint128 instead)
    ## Return value is the carry-out

  func umul128(a, b: uint64, hi: var uint64): uint64 {.importc:"_umul128", header:"<intrin.h>", nodecl.}
    ## (hi, lo) <-- a * b
    ## Return value is the low word

  func unsafeFMA*(hi, lo: var Ct[uint64], a, b, c: Ct[uint64]) {.inline.}=
    ## Extended precision multiplication + addition
    ## This is constant-time on most hardware except some specific one like Cortex M0
    ## (hi, lo) <- a*b + c
    var carry: cuchar
    var hi, lo: uint64
    lo = umul128(uint64(a), uint64(b), hi)
    carry = addcarry_u64(cuchar(0), lo, uint64(c), lo)
    discard addcarry_u64(carry, hi, 0, hi)

  func unsafeFMA2*(hi, lo: var Ct[uint64], a1, b1, a2, b2, c1, c2: Ct[uint64]) {.inline.}=
    ## (hi, lo) <- a1 * b1 + a2 * b2 + c1 + c2
    var f1_lo, f1_hi, f2_lo, f2_hi: uint64
    var carry: cuchar

    f1_lo = umul128(uint64(a1), uint64(b1), f1_hi)
    f2_lo = umul128(uint64(a2), uint64(b2), f2_hi)

    # On CPU with ADX: we can use addcarryx_u64 (adcx/adox) to have
    # separate carry chains that can be processed in parallel by CPU

    # Carry chain 1
    carry = addcarry_u64(cuchar(0), f1_lo, uint64(c1), f1_lo)
    discard addcarry_u64(carry, f1_hi, 0, f1_hi)

    # Carry chain 2
    carry = addcarry_u64(cuchar(0), f2_lo, uint64(c2), f2_lo)
    discard addcarry_u64(carry, f2_hi, 0, f2_hi)

    # Merge
    carry = addcarry_u64(cuchar(0), f1_lo, f2_lo, lo)
    discard addcarry_u64(carry, f1_hi, f2_hi, hi)

  func unsafeFMA2_hi*(hi: var Ct[uint64], a1, b1, a2, b2, c: Ct[uint64]) {.inline.}=
    ## Returns the high word of the sum of extended precision multiply-adds
    ## (hi, _) <- a1 * b1 + a2 * b2 + c

    var f1_lo, f1_hi, f2_lo, f2_hi: uint64
    var carry: cuchar

    f1_lo = umul128(uint64(a1), uint64(b1), f1_hi)
    f2_lo = umul128(uint64(a2), uint64(b2), f2_hi)

    carry = addcarry_u64(cuchar(0), f1_lo, uint64(c), f1_lo)
    discard addcarry_u64(carry, f1_hi, 0, f1_hi)

    # Merge
    var lo: uint64
    carry = addcarry_u64(cuchar(0), f1_lo, f2_lo, lo)
    discard addcarry_u64(carry, f1_hi, f2_hi, hi)

else:
  {.error: "Compiler not implemented".}
