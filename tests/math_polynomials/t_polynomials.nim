# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[times, unittest, algorithm],
  # Internals
  constantine/math/arithmetic,
  constantine/named/algebras,
  constantine/math/polynomials/polynomials,
  constantine/math/io/io_fields,
  # Test utilities
  helpers/prng_unsafe

const Degree = 42
const NumCoefs = Degree+1
const NumSamples = Degree * 2
type F = Fr[Banderwagon]

var rng: RngState
let timeseed = uint32(toUnix(getTime()) and (1'i64 shl 32 - 1)) # unixTime mod 2^32
seed(rng, timeseed)
echo "\n------------------------------------------------------\n"
echo "test_polynomials seed: ", timeseed

suite "Polynomials":
  test "Formal derivative evaluations are consistent":
    proc t_deriv() =
      var p: PolynomialCoef[NumCoefs, F]
      rng.random_unsafe(p.coefs)

      var dp{.noInit.}: PolynomialCoef[NumCoefs-1, F]
      dp.formal_derivative(p)

      for _ in 0 ..< NumSamples:
        let z = rng.random_unsafe(F)
        var pz, dpz, dpz2: F
        evalPolyAndDerivAt(pz, dpz, p, z)
        dpz2.evalPolyAt(dp, z)

        doAssert bool(dpz == dpz2)

    t_deriv()

  test "Vanishing polynomial evaluations are consistent":
    proc t_vanishing() =
      var roots_u64: array[NumCoefs+1, uint64]
      var roots: array[NumCoefs+1, F]

      rng.random_unsafe(roots_u64)
      roots_u64.sort()

      for i in 0 .. NumCoefs:
        roots[i].fromInt(roots_u64[i])

      var V{.noInit.}: PolynomialCoef[roots.len+1, F]
      V.vanishing_poly(roots)

      for i in 0 ..< roots.len:
        var vroot: F
        vroot.evalPolyAt(V, roots[i])
        doAssert vroot.isZero().bool()

      for _ in 0 ..< NumSamples:
        let z = rng.random_unsafe(F)
        var vz, vz2: F
        vz.evalPolyAt(V, z)
        vz2.evalVanishingPolyAt(roots, z)

        doAssert bool(vz == vz2)

      var dV{.noInit.}: PolynomialCoef[roots.len, F]
      dV.formal_derivative(V)

      for i in 0 ..< roots.len:
        var dvz, dvz2, dvz3: F
        var vz2: F

        dvz.evalPolyAt(dV, roots[i])
        evalPolyAndDerivAt(vz2, dvz2, V, roots[i])
        dvz3.evalVanishingPolyDerivativeAtRoot(roots, i)

        doAssert vz2.isZero().bool()
        doAssert bool(dvz == dvz2)
        doAssert bool(dvz == dvz3)

    t_vanishing()
