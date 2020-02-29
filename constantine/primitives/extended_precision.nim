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

template unsafeFMA*(hi, lo: var Ct[uint32], a, b, c: Ct[uint32]) =
  ## Extended precision multiplication + addition
  ## This is constant-time on most hardware except some specific one like Cortex M0
  ## (hi, lo) <- a*b + c
  block:
    # Note: since a and b use 31-bit,
    # the result is 62-bit and carrying cannot overflow
    let dblPrec = uint64(a) * uint64(b) + uint64(c)
    hi = Ct[uint32](dblPrec shr 31)
    lo = Ct[uint32](dblPrec) and Ct[uint32](1 shl 31 - 1)

template unsafeFMA2*(hi, lo: var Ct[uint32], a1, b1, a2, b2, c1, c2: Ct[uint32]) =
  ## (hi, lo) <- a1 * b1 + a2 * b2 + c1 + c2
  block:
    # TODO: Can this overflow?
    let dblPrec = uint64(a1) * uint64(b1) +
                  uint64(a2) * uint64(b2) +
                  uint64(c1) +
                  uint64(c2)
    hi = Ct[uint32](dblPrec shr 31)
    lo = Ct[uint32](dblPrec) and Ct[uint32](1 shl 31 - 1)

# ############################################################
#
#                     64-bit words
#
# ############################################################

when defined(gcc) or defined(clang) or defined(llvm_gcc):
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
    asm """
      divq %[divisor]
      : "=a" (`*q`), "=d" (`*r`)
      : "d" (`n_hi`), "a" (`n_lo`), [divisor] "rm" (`d`)
      :
    """

  template unsafeFMA*(hi, lo: var Ct[uint64], a, b, c: Ct[uint64]) =
    ## Extended precision multiplication + addition
    ## This is constant-time on most hardware except some specific one like Cortex M0
    ## (hi, lo) <- a*b + c
    block:
      # Note: since a and b use 63-bit,
      # the result is 126-bit and carrying cannot overflow
      var dblPrec {.noInit.}: uint128
      {.emit:[dblPrec, " = (unsigned __int128)", a," * (unsigned __int128)", b, " + (unsigned __int128)",c,";"].}

      {.emit:[hi, " = (NU64)(", dblPrec," >> ", 63'u64, ");"].}
      {.emit:[lo, " = (NU64)", dblPrec," & ", 1'u64 shl 63 - 1, ";"].}

  template unsafeFMA2*(hi, lo: var Ct[uint64], a1, b1, a2, b2, c1, c2: Ct[uint64]) =
    ## (hi, lo) <- a1 * b1 + a2 * b2 + c1 + c2
    block:
      # TODO: Can this overflow?
      var dblPrec: uint128
      {.emit:[dblPrec, " = (unsigned __int128)", a1," * (unsigned __int128)", b1,
                       " + (unsigned __int128)", a2," * (unsigned __int128)", b2,
                       " + (unsigned __int128)", c1,
                       " + (unsigned __int128)", c2, ";"].}
      {.emit:[hi, " = (NU64)", dblPrec," >> ", 63'u64, ";"].}
      {.emit:[lo, " = (NU64)", dblPrec," & ", 1'u64 shl 63 - 1, ";"].}

else:
  {.error: "Compiler not implemented".}
  # For VCC and ICC use add_carry_u64, _add_carryx_u64 intrinsics
  # and _umul128
