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
    #
    # Also Nim adds tests everywhere a range type is used which is great
    # except in a crypto library:
    # - We don't want exceptions
    # - Nim will be helpful and return the offending value, which might be secret data
    # - This will hint the underlying C compiler about the value range
    #   and seeing 0/1 it might want to use branches again.

  Carry* = Ct[uint8]  # distinct range[0'u8 .. 1]
  Borrow* = Ct[uint8] # distinct range[0'u8 .. 1]

  VarTime*   = object
    ## For use with Nim effect system to track vartime subroutines
