# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/curves,
  ../arithmetic/finite_fields

func invsqrt_addchain_pminus5over8*(r: var Fp[Edwards25519], a: Fp[Edwards25519]) =
  ## Returns a^((p-5)/8) = 2²⁵²-3 for inverse square root computation
  
  var t{.noInit.}, u{.noInit.}, v{.noinit.}: Fp[Edwards25519]
  u.square(a)               # 2
  v.square_repeated(u, 2)   # 8
  v *= a                    # 9
  u *= v                    # 11
  u.square()                # 22
  u *= v                    # 31 = 2⁵-1
  v.square_repeated(u, 5)   #
  u *= v                    # 2¹⁰-1
  v.square_repeated(u, 10)  #
  v *= u                    # 2²⁰-1
  t.square_repeated(v, 20)  #
  v *= t                    # 2⁴⁰-1
  v.square_repeated(10)     #
  u *= v                    # 2⁵⁰-1
  v.square_repeated(u, 50)  #
  v *= u                    # 2¹⁰⁰-1
  t.square_repeated(v, 100) #
  v *= t                    # 2²⁰⁰-1
  v.square_repeated(50)     # 
  u *= v                    # 2²⁵⁰-1
  u.square_repeated(2)      # 2²⁵²-4
  r.prod(a, u)              # 2²⁵²-3