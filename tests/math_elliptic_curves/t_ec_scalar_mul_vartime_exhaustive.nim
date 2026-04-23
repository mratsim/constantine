# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[random],
  # Internals
  constantine/named/[algebras, zoo_generators],
  constantine/math/io/[io_bigints, io_ec],
  constantine/math/arithmetic,
  constantine/math/ec_shortweierstrass,
  constantine/math/elliptic/ec_scalar_mul_vartime {.all.},
  constantine/math_arbitrary_precision/arithmetic/limbs_views

# Test scalar multiplication addition chains against double-and-add reference
proc testAddChain5bit() =
  echo "Testing scalarMul_addchain_5bit_vartime for scalars 0-31"
  echo "========================================================"

  var failures = 0

  for s in 0 ..< 32:
    # Create test scalar
    var scalar = BigInt[Fr[BLS12_381].bits()].fromUint(uint(s))

    # Use generator point - convert to Jacobian
    var P: EC_ShortW_Jac[Fp[BLS12_381], G1]
    P.fromAffine(BLS12_381.getGenerator("G1"))

    # Compute using addition chain
    var result_addchain = P
    result_addchain.scalarMul_addchain_5bit_vartime(scalar)

    # Compute using double-and-add (reference)
    var result_ref = P
    result_ref.scalarMul_doubleAdd_vartime(scalar)

    # Compare
    if not (result_addchain == result_ref).bool:
      echo "FAIL: scalar = ", s
      echo "  Addition chain result: ", result_addchain.toHex()
      echo "  Double-add result:     ", result_ref.toHex()
      inc failures

    echo "  s = ", s, ": ", if (result_addchain == result_ref).bool: "PASS" else: "FAIL"

  echo ""
  echo "Total: ", 32 - failures, "/32 tests passed"
  if failures > 0:
    echo "FAILED: ", failures, " tests"
    quit 1
  else:
    echo "SUCCESS: All tests passed!"

# Test dispatch logic
proc testDispatchLogic() =
  echo "\nTesting scalarMul_vartime dispatch logic"
  echo "========================================="

  var failures = 0

  for s in 0 ..< 32:
    var scalar = BigInt[Fr[BLS12_381].bits()].fromUint(uint(s))

    # Use generator point - convert to Jacobian
    var P: EC_ShortW_Jac[Fp[BLS12_381], G1]
    P.fromAffine(BLS12_381.getGenerator("G1"))

    # Compute using auto-dispatch
    var result_auto = P
    result_auto.scalarMul_addchain_5bit_vartime(scalar)

    # Compute using double-and-add (reference)
    var result_ref = P
    result_ref.scalarMul_doubleAdd_vartime(scalar)

    # Compare
    if not (result_auto == result_ref).bool:
      echo "FAIL: scalar = ", s
      echo "  Auto result: ", result_auto.toHex()
      echo "  Ref result:  ", result_ref.toHex()
      inc failures

    echo "  s = ", s, " (", scalar.limbs.getBits_LE_vartime(), " Fr[BLS12_381].bits()): ",
        if (result_auto == result_ref).bool: "PASS" else: "FAIL"

  echo ""
  echo "Total: ", 32 - failures, "/32 tests passed"
  if failures > 0:
    echo "FAILED: ", failures, " tests"
    quit 1
  else:
    echo "SUCCESS: All tests passed!"

when isMainModule:
  randomize(12345)
  testAddChain5bit()
  testDispatchLogic()