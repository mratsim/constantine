# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config,
  ../constant_time/ct_types

# ############################################################
#
# Extended precision primitives on GCC & Clang (all CPU archs)
#
# ############################################################

static:
  doAssert GCC_Compatible
  doAssert sizeof(int) == 8

func mul*(hi, lo: var Ct[uint64], a, b: Ct[uint64]) {.inline.} =
  ## Extended precision multiplication
  ## (hi, lo) <- a*b
  ##
  ## This is constant-time on most hardware
  ## See: https://www.bearssl.org/ctmul.html
  block:
    var dblPrec {.noInit.}: uint128
    {.emit:[dblPrec, " = (unsigned __int128)", a," * (unsigned __int128)", b,";"].}

    # Don't forget to dereference the var param in C mode
    when defined(cpp):
      {.emit:[hi, " = (NU64)(", dblPrec," >> ", 64'u64, ");"].}
      {.emit:[lo, " = (NU64)", dblPrec,";"].}
    else:
      {.emit:["*",hi, " = (NU64)(", dblPrec," >> ", 64'u64, ");"].}
      {.emit:["*",lo, " = (NU64)", dblPrec,";"].}

func muladd1*(hi, lo: var Ct[uint64], a, b, c: Ct[uint64]) {.inline.} =
  ## Extended precision multiplication + addition
  ## (hi, lo) <- a*b + c
  ##
  ## Note: 0xFFFFFFFF_FFFFFFFF² -> (hi: 0xFFFFFFFFFFFFFFFE, lo: 0x0000000000000001)
  ##       so adding any c cannot overflow
  ##
  ## This is constant-time on most hardware
  ## See: https://www.bearssl.org/ctmul.html
  block:
    var dblPrec {.noInit.}: uint128
    {.emit:[dblPrec, " = (unsigned __int128)", a," * (unsigned __int128)", b, " + (unsigned __int128)",c,";"].}

    # Don't forget to dereference the var param in C mode
    when defined(cpp):
      {.emit:[hi, " = (NU64)(", dblPrec," >> ", 64'u64, ");"].}
      {.emit:[lo, " = (NU64)", dblPrec,";"].}
    else:
      {.emit:["*",hi, " = (NU64)(", dblPrec," >> ", 64'u64, ");"].}
      {.emit:["*",lo, " = (NU64)", dblPrec,";"].}

func muladd2*(hi, lo: var Ct[uint64], a, b, c1, c2: Ct[uint64]) {.inline.}=
  ## Extended precision multiplication + addition + addition
  ## This is constant-time on most hardware except some specific one like Cortex M0
  ## (hi, lo) <- a*b + c1 + c2
  ##
  ## Note: 0xFFFFFFFF_FFFFFFFF² -> (hi: 0xFFFFFFFFFFFFFFFE, lo: 0x0000000000000001)
  ##       so adding 0xFFFFFFFFFFFFFFFF leads to (hi: 0xFFFFFFFFFFFFFFFF, lo: 0x0000000000000000)
  ##       and we have enough space to add again 0xFFFFFFFFFFFFFFFF without overflowing
  block:
    var dblPrec {.noInit.}: uint128
    {.emit:[
      dblPrec, " = (unsigned __int128)", a," * (unsigned __int128)", b,
               " + (unsigned __int128)",c1," + (unsigned __int128)",c2,";"
    ].}

    # Don't forget to dereference the var param in C mode
    when defined(cpp):
      {.emit:[hi, " = (NU64)(", dblPrec," >> ", 64'u64, ");"].}
      {.emit:[lo, " = (NU64)", dblPrec,";"].}
    else:
      {.emit:["*",hi, " = (NU64)(", dblPrec," >> ", 64'u64, ");"].}
      {.emit:["*",lo, " = (NU64)", dblPrec,";"].}

func smul*(hi, lo: var Ct[uint64], a, b: Ct[uint64]) {.inline.} =
  ## Extended precision multiplication
  ## (hi, lo) <- a*b
  ##
  ## Inputs are intentionally unsigned
  ## as we use their unchecked raw representation for cryptography
  ##
  ## This is constant-time on most hardware
  ## See: https://www.bearssl.org/ctmul.html
  block:
    var dblPrec {.noInit.}: int128
    # We need to cast to int64 then sign-extended to int128
    {.emit:[dblPrec, " = (__int128)", cast[int64](a)," * (__int128)", cast[int64](b),";"].}

    # Don't forget to dereference the var param in C mode
    when defined(cpp):
      {.emit:[hi, " = (NU64)(", dblPrec," >> ", 64'u64, ");"].}
      {.emit:[lo, " = (NU64)", dblPrec,";"].}
    else:
      {.emit:["*",hi, " = (NU64)(", dblPrec," >> ", 64'u64, ");"].}
      {.emit:["*",lo, " = (NU64)", dblPrec,";"].}