# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/times,
  # Internals
  constantine/boolean_hypercube/multilinear_extensions,
  constantine/named/algebras,
  constantine/math/arithmetic,
  constantine/math/io/io_fields,
  # Helpers
  helpers/prng_unsafe

# Compile with -d:CTT_TEST_CURVES to define F5

func toF5[N: static int](a: array[N, SomeUnsignedInt]): array[N, Fp[F5]] =
  for i in 0 ..< N:
    result[i] = Fp[F5].fromUint(a[i])

func transpose[M, N: static int, T](a: array[M, array[N, T]]): array[N, array[M, T]] =
  for i in 0 ..< M:
    for j in 0 ..< N:
      result[j][i] = a[i][j]

# - https://people.cs.georgetown.edu/jthaler/IPsandextensions.pdf\
#   Note: first row is
#     1 2 3 4 0 not 1 2 3 4 5 (though 5 ≡ 0 (mod 5) so arguably not wrong)
# - https://people.cs.georgetown.edu/jthaler/ProofsArgsAndZK.pdf
#   Chapter 3.5
proc test_thaler() =
  let evals = [uint32 1, 2, 1, 4].toF5()
  let mle_evals_be = [
        [byte 1, 2, 3, 4, 0],
        [byte 1, 4, 2, 0, 3],
        [byte 1, 1, 1, 1, 1],
        [byte 1, 3, 0, 2, 4],
        [byte 1, 0, 4, 3, 2],
  ]
  let mle_evals_le = mle_evals_be.transpose()

  let mle = MultilinearExtension[Fp[F5]].new(2, evals)

  block:
    for i in 0'u32 .. 4:
      var row: array[5, byte]
      for j in 0'u32 .. 4:
        var r: Fp[F5]
        r.evalMultilinearExtensionAt_reference(
          mle, [Fp[F5].fromUint(i), Fp[F5].fromUint(j)],
          bigEndian)
        var buf: array[1, byte]
        buf.marshal(r, bigEndian)
        row[j] = buf[0]

      echo row
      doAssert row == mle_evals_be[i]

    echo "=== SUCCESS reference MLE big-endian evaluation ==="

  block:
    for i in 0'u32 .. 4:
      var row: array[5, byte]
      for j in 0'u32 .. 4:
        var r: Fp[F5]
        r.evalMultilinearExtensionAt(
          mle, [Fp[F5].fromUint(i), Fp[F5].fromUint(j)],
          bigEndian)
        var buf: array[1, byte]
        buf.marshal(r, bigEndian)
        row[j] = buf[0]

      echo row
      doAssert row == mle_evals_be[i]

    echo "=== SUCCESS optimized MLE big-endian evaluation ==="

  block:
    for i in 0'u32 .. 4:
      var row: array[5, byte]
      for j in 0'u32 .. 4:
        var r: Fp[F5]
        r.evalMultilinearExtensionAt_reference(
          mle, [Fp[F5].fromUint(i), Fp[F5].fromUint(j)],
          littleEndian)
        var buf: array[1, byte]
        buf.marshal(r, bigEndian)
        row[j] = buf[0]

      echo row
      doAssert row == mle_evals_le[i]

    echo "=== SUCCESS reference MLE little-endian evaluation ==="

  block:
    for i in 0'u32 .. 4:
      var row: array[5, byte]
      for j in 0'u32 .. 4:
        var r: Fp[F5]
        r.evalMultilinearExtensionAt(
          mle, [Fp[F5].fromUint(i), Fp[F5].fromUint(j)],
          littleEndian)
        var buf: array[1, byte]
        buf.marshal(r, bigEndian)
        row[j] = buf[0]

      echo row
      doAssert row == mle_evals_le[i]

    echo "=== SUCCESS optimized MLE little-endian evaluation ==="

var rng*: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "\n------------------------------------------------------\n"
echo "Multilinear Extensions xoshiro512** seed: ", seed

proc test_randomized(F: typedesc, num_vars: int) =
  var evals = newSeq[F](1 shl num_vars)
  for eval in evals.mitems():
    eval = rng.random_unsafe(F)

  let mle = MultilinearExtension[F].new(num_vars, evals)

  var coords = newSeq[F](num_vars)
  for coord in coords.mitems():
    coord = rng.random_unsafe(F)

  var r_ref {.noInit.}: F
  var r_opt {.noInit.}: F

  r_ref.evalMultilinearExtensionAt_reference(mle, coords, bigEndian)
  r_opt.evalMultilinearExtensionAt(mle, coords, bigEndian)

  doAssert bool(r_ref == r_opt)
  echo "Success: ", F, ", ", num_vars, " variables, bigEndian"    #, r: ", r_ref.toHex()

  r_ref.evalMultilinearExtensionAt_reference(mle, coords, littleEndian)
  r_opt.evalMultilinearExtensionAt(mle, coords, littleEndian)

  doAssert bool(r_ref == r_opt)
  echo "Success: ", F, ", ", num_vars, " variables, littleEndian" #, r: ", r_ref.toHex()

test_thaler()
test_randomized(Fr[BN254_Snarks], 3)
test_randomized(Fr[BN254_Snarks], 3)
test_randomized(Fr[BN254_Snarks], 7)
test_randomized(Fr[BN254_Snarks], 7)
test_randomized(Fr[BN254_Snarks], 11)
test_randomized(Fr[BN254_Snarks], 11)
test_randomized(Fr[BLS12_381], 3)
test_randomized(Fr[BLS12_381], 3)
test_randomized(Fr[BLS12_381], 7)
test_randomized(Fr[BLS12_381], 7)
test_randomized(Fr[BLS12_381], 11)
test_randomized(Fr[BLS12_381], 11)
