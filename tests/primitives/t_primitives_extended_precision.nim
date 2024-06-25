# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.


import
  std/[unittest, times, math],
  constantine/platforms/abstractions,
  helpers/prng_unsafe

suite "Extended precision bugs":
  test $uint32 & " sanity check":
    let a = ct(0x0000_0001, uint32)
    let b = ct(0x0000_0001, uint32)
    let c = ct(0x0000_0001, uint32)
    var hi, lo: Ct[uint32]
    muladd1(hi, lo, a, b, c)

    check:
      hi.uint32 == 0'u32
      lo.uint32 == 0x0000_0002'u32

  test $uint32 & " muladd1 - #61-1":
    let a = ct(0x8000_0001, uint32)
    var t = ct(0xE35C_5451, uint32)
    var C: Ct[uint32]
    muladd1(C, t, a, a, t)

    check:
      C.uint32 == 0x4000_0001'u32
      t.uint32 == 0xe35c_5452'u32

  test $uint32 & " muladd1 - #61-2":
    let a = ct(0xFFFF_FFFE, uint32)
    var t = ct(0x0000_0004, uint32)
    var C: Ct[uint32]
    muladd1(C, t, a, a, t)

    check:
      C.uint32 == 0xffff_fffc'u32
      t.uint32 == 0x0000_0008'u32

  test $uint32 & " muladd1 - #61-3":
    let a = ct(0x1480_0020, uint32)
    var t = ct(0x5454_109E, uint32)
    var C: Ct[uint32]
    muladd1(C, t, a, a, t)

    check:
      C.uint32 == 0x01a4_4005'u32
      t.uint32 == 0x7454_149e'u32

  test $uint32 & " muladd1 - #62":
    let a = ct(0x7FEF_FFFF, uint32)
    var t = ct(0x67A4_B24C, uint32)
    var C: Ct[uint32]
    muladd1(C, t, a, a, t)

    check:
      C.uint32 == 0x3ff0_00ff'u32
      t.uint32 == 0x67c4_b24d'u32
