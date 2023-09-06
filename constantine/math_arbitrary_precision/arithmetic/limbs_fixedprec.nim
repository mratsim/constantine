# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/abstractions,
  ./limbs_views

# No exceptions allowed
{.push raises: [].}

# ############################################################
#
#            Fixed-precision type-erased arithmetic
#
# ############################################################
#
# This file implements non-performance critical type-erased
# fixed-precision primitives, i.e. it assumes that
# inputs use the same number of limbs.
#
# The goal is to avoid code-size explosion for procedures
# that are not in a hot path and don't benefits from staticFor loops
# like division or modular reduction.

# Comparison
# ------------------------------------------------------------

func lt*(a, b: distinct LimbsViewAny, len: int): SecretBool {.meter.} =
  ## Returns true if a < b
  ## Comparison is constant-time
  var diff: SecretWord
  var borrow: Borrow
  for i in 0 ..< len:
    subB(borrow, diff, a[i], b[i], borrow)

  result = (SecretBool)(borrow)

# Type-erased add-sub
# ------------------------------------------------------------

func cadd*(a: LimbsViewMut, b: LimbsViewAny, ctl: SecretBool, len: int): Carry {.meter.} =
  ## Type-erased conditional addition
  ## Returns the carry
  ##
  ## if ctl is true: a <- a + b
  ## if ctl is false: a <- a
  ## The carry is always computed whether ctl is true or false
  ##
  ## Time and memory accesses are the same whether a copy occurs or not
  result = Carry(0)
  var sum: SecretWord
  for i in 0 ..< len:
    addC(result, sum, a[i], b[i], result)
    ctl.ccopy(a[i], sum)

func csub*(a: LimbsViewMut, b: LimbsViewAny, ctl: SecretBool, len: int): Borrow {.meter.} =
  ## Type-erased conditional addition
  ## Returns the borrow
  ##
  ## if ctl is true: a <- a - b
  ## if ctl is false: a <- a
  ## The borrow is always computed whether ctl is true or false
  ##
  ## Time and memory accesses are the same whether a copy occurs or not
  result = Borrow(0)
  var diff: SecretWord
  for i in 0 ..< len:
    subB(result, diff, a[i], b[i], result)
    ctl.ccopy(a[i], diff)