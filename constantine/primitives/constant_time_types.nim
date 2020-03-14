# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

type
  BaseUint* = SomeUnsignedInt or byte

  Ct*[T: BaseUint] = distinct T

  CTBool*[T: Ct] = distinct T # range[T(0)..T(1)]
    ## To avoid the compiler replacing bitwise boolean operations
    ## by conditional branches, we don't use booleans.
    ## We use an int to prevent compiler "optimization" and introduction of branches
    # Note, we could use "range" but then the codegen
    # uses machine-sized signed integer types.
    # signed types and machine-dependent words are undesired
    # - we don't want compiler optimizing signed "undefined behavior"
    # - Basic functions like BigInt add/sub
    #   return and/or accept CTBool, we don't want them
    #   to require unnecessarily 8 bytes instead of 4 bytes

  Carry* = distinct uint8
  Borrow* = distinct uint8

const GCC_Compatible* = defined(gcc) or defined(clang) or defined(llvm_gcc)
const X86* = defined(amd64) or defined(i386)
