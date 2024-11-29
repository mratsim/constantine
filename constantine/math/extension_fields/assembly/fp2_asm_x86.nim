# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internal
  constantine/platforms/abstractions,
  constantine/named/algebras,
  constantine/math/arithmetic

import constantine/math/arithmetic/assembly/limbs_asm_modular_x86 {.all.}

# ############################################################
#                                                            #
#             Assembly implementation of 𝔽p2                 #
#                                                            #
# ############################################################

static: doAssert UseASM_X86_64

# No exceptions allowed
{.push raises: [].}

# 𝔽p2 addition law
# ------------------------------------------------------------

template aliasPtr(coord, name: untyped): untyped =
  # The *_gen macros get confused by bracket [] and dot `.` expressions
  # when deriving names so create aliases
  # Furthermore the C compiler requires asm inputs to be lvalues
  # and arrays should be passed as pointers (aren't they aren't if we use a dot expression)
  let name {.inject.} = coord.mres.limbs.unsafeAddr()

func fp2_add_asm*(
        r: var array[2, Fp],
        a, b: array[2, Fp]) =
  ## Addition on Fp2
  # This specialized proc inline calls and limits data movement (for example register pop/push)
  const spareBits = Fp.getSpareBits()

  aliasPtr r[0], r0
  aliasPtr r[1], r1
  aliasPtr a[0], a0
  aliasPtr a[1], a1
  aliasPtr b[0], b0
  aliasPtr b[1], b1
  let p = Fp.getModulus().limbs.unsafeAddr()

  addmod_gen(r0[], a0[], b0[], p[], spareBits)
  addmod_gen(r1[], a1[], b1[], p[], spareBits)

func fp2_sub_asm*(
        r: var array[2, Fp],
        a, b: array[2, Fp]) =
  ## Substraction on Fp2
  # This specialized proc inline calls and limits data movement (for example register pop/push)
  aliasPtr r[0], r0
  aliasPtr r[1], r1
  aliasPtr a[0], a0
  aliasPtr a[1], a1
  aliasPtr b[0], b0
  aliasPtr b[1], b1
  let p = Fp.getModulus().limbs.unsafeAddr()

  submod_gen(r0[], a0[], b0[], p[])
  submod_gen(r1[], a1[], b1[], p[])

func fp2_neg_asm*(
        r: var array[2, Fp],
        a: array[2, Fp]) =
  ## Negation on Fp2
  # This specialized proc inline calls and limits data movement (for example register pop/push)

  aliasPtr r[0], r0
  aliasPtr r[1], r1
  aliasPtr a[0], a0
  aliasPtr a[1], a1
  let p = Fp.getModulus().limbs.unsafeAddr()

  negmod_gen(r0[], a0[], p[])
  negmod_gen(r1[], a1[], p[])
