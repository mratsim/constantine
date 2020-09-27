# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/[common, curves],
  ./bigints,
  ./finite_fields

# ############################################################
#
#                  Specialized inversions
#
# ############################################################

# Field-specific inversion routines
func square_repeated(r: var Fp, num: int) =
  ## Repeated squarings
  for _ in 0 ..< num:
    r.square()

# Secp256k1
# ------------------------------------------------------------
func inv_addchain(r: var Fp[Secp256k1], a: Fp[Secp256k1]) {.used.}=
  ## We invert via Little Fermat's theorem
  ## a^(-1) ≡ a^(p-2) (mod p)
  ## with p = "0xFFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFE FFFFFC2F"
  ## We take advantage of the prime special form to hardcode
  ## the sequence of squarings and multiplications for the modular exponentiation
  ##
  ## See libsecp256k1
  ##
  ## The binary representation of (p - 2) has 5 blocks of 1s, with lengths in
  ## { 1, 2, 22, 223 }. Use an addition chain to calculate 2^n - 1 for each block:
  ## [1], [2], 3, 6, 9, 11, [22], 44, 88, 176, 220, [223]

  var
    x2{.noInit.}: Fp[Secp256k1]
    x3{.noInit.}: Fp[Secp256k1]
    x6{.noInit.}: Fp[Secp256k1]
    x9{.noInit.}: Fp[Secp256k1]
    x11{.noInit.}: Fp[Secp256k1]
    x22{.noInit.}: Fp[Secp256k1]
    x44{.noInit.}: Fp[Secp256k1]
    x88{.noInit.}: Fp[Secp256k1]
    x176{.noInit.}: Fp[Secp256k1]
    x220{.noInit.}: Fp[Secp256k1]
    x223{.noInit.}: Fp[Secp256k1]

  x2.square(a)
  x2 *= a

  x3.square(x2)
  x3 *= a

  x6 = x3
  x6.square_repeated(3)
  x6 *= x3

  x9 = x6
  x9.square_repeated(3)
  x9 *= x3

  x11 = x9
  x11.square_repeated(2)
  x11 *= x2

  x22 = x11
  x22.square_repeated(11)
  x22 *= x11

  x44 = x22
  x44.square_repeated(22)
  x44 *= x22

  x88 = x44
  x88.square_repeated(44)
  x88 *= x44

  x176 = x88
  x88.square_repeated(88)
  x176 *= x88

  x220 = x176
  x220.square_repeated(44)
  x220 *= x44

  x223 = x220
  x223.square_repeated(3)
  x223 *= x3

  # The final result is then assembled using a sliding window over the blocks
  r = x223
  r.square_repeated(23)
  r *= x22
  r.square_repeated(5)
  r *= a
  r.square_repeated(3)
  r *= x2
  r.square_repeated(2)
  r *= a

# BLS12-381
# ------------------------------------------------------------
func inv_addchain*(r: var Fp[BLS12_381], a: Fp[BLS12_381]) =
  var
    x10       {.noinit.}: Fp[BLS12_381]
    x100      {.noinit.}: Fp[BLS12_381]
    x1000     {.noinit.}: Fp[BLS12_381]
    x1001     {.noinit.}: Fp[BLS12_381]
    x1011     {.noinit.}: Fp[BLS12_381]
    x1101     {.noinit.}: Fp[BLS12_381]
    x10001    {.noinit.}: Fp[BLS12_381]
    x10100    {.noinit.}: Fp[BLS12_381]
    x11001    {.noinit.}: Fp[BLS12_381]
    x11010    {.noinit.}: Fp[BLS12_381]
    x110100   {.noinit.}: Fp[BLS12_381]
    x110110   {.noinit.}: Fp[BLS12_381]
    x110111   {.noinit.}: Fp[BLS12_381]
    x1001101  {.noinit.}: Fp[BLS12_381]
    x1001111  {.noinit.}: Fp[BLS12_381]
    x1010101  {.noinit.}: Fp[BLS12_381]
    x1011101  {.noinit.}: Fp[BLS12_381]
    x1100111  {.noinit.}: Fp[BLS12_381]
    x1101001  {.noinit.}: Fp[BLS12_381]
    x1110111  {.noinit.}: Fp[BLS12_381]
    x1111011  {.noinit.}: Fp[BLS12_381]
    x10001001 {.noinit.}: Fp[BLS12_381]
    x10010101 {.noinit.}: Fp[BLS12_381]
    x10010111 {.noinit.}: Fp[BLS12_381]
    x10101001 {.noinit.}: Fp[BLS12_381]
    x10110001 {.noinit.}: Fp[BLS12_381]
    x10111111 {.noinit.}: Fp[BLS12_381]
    x11000011 {.noinit.}: Fp[BLS12_381]
    x11010000 {.noinit.}: Fp[BLS12_381]
    x11010111 {.noinit.}: Fp[BLS12_381]
    x11100001 {.noinit.}: Fp[BLS12_381]
    x11100101 {.noinit.}: Fp[BLS12_381]
    x11101011 {.noinit.}: Fp[BLS12_381]
    x11110101 {.noinit.}: Fp[BLS12_381]
    x11111111 {.noinit.}: Fp[BLS12_381]

  x10       .square(a)
  x100      .square(x10)
  x1000     .square(x100)
  x1001     .prod(a, x1000)
  x1011     .prod(x10, x1001)
  x1101     .prod(x10, x1011)
  x10001    .prod(x100, x1101)
  x10100    .prod(x1001, x1011)
  x11001    .prod(x1000, x10001)
  x11010    .prod(a, x11001)
  x110100   .square(x11010)
  x110110   .prod(x10, x110100)
  x110111   .prod(a, x110110)
  x1001101  .prod(x11001, x110100)
  x1001111  .prod(x10, x1001101)
  x1010101  .prod(x1000, x1001101)
  x1011101  .prod(x1000, x1010101)
  x1100111  .prod(x11010, x1001101)
  x1101001  .prod(x10, x1100111)
  x1110111  .prod(x11010, x1011101)
  x1111011  .prod(x100, x1110111)
  x10001001 .prod(x110100, x1010101)
  x10010101 .prod(x11010, x1111011)
  x10010111 .prod(x10, x10010101)
  x10101001 .prod(x10100, x10010101)
  x10110001 .prod(x1000, x10101001)
  x10111111 .prod(x110110, x10001001)
  x11000011 .prod(x100, x10111111)
  x11010000 .prod(x1101, x11000011)
  x11010111 .prod(x10100, x11000011)
  x11100001 .prod(x10001, x11010000)
  x11100101 .prod(x100, x11100001)
  x11101011 .prod(x10100, x11010111)
  x11110101 .prod(x10100, x11100001)
  x11111111 .prod(x10100, x11101011) # 35 operations

  # TODO: we can accumulate in a partially reduced
  #       doubled-size `r` to avoid the final substractions.
  #       and only reduce at the end.
  #       This requires the number of op to be less than log2(p) == 381

  # 35 + 22 = 57 operations
  r.prod(x10111111, x11100001)
  r.square_repeated(8)
  r *= x10001
  r.square_repeated(11)
  r *= x11110101

  # 57 + 28 = 85 operations
  r.square_repeated(11)
  r *= x11100101
  r.square_repeated(8)
  r *= x11111111
  r.square_repeated(7)

  # 88 + 22 = 107 operations
  r *= x1001101
  r.square_repeated(9)
  r *= x1101001
  r.square_repeated(10)
  r *= x10110001

  # 107+24 = 131 operations
  r.square_repeated(7)
  r *= x1011101
  r.square_repeated(9)
  r *= x1111011
  r.square_repeated(6)

  # 131+23 = 154 operations
  r *= x11001
  r.square_repeated(11)
  r *= x1101001
  r.square_repeated(9)
  r *= x11101011

  # 154+28 = 182 operations
  r.square_repeated(10)
  r *= x11010111
  r.square_repeated(6)
  r *= x11001
  r.square_repeated(10)

  # 182+23 = 205 operations
  r *= x1110111
  r.square_repeated(9)
  r *= x10010111
  r.square_repeated(11)
  r *= x1001111

  # 205+30 = 235 operations
  r.square_repeated(10)
  r *= x11100001
  r.square_repeated(9)
  r *= x10001001
  r.square_repeated(9)

  # 235+21 = 256 operations
  r *= x10111111
  r.square_repeated(8)
  r *= x1100111
  r.square_repeated(10)
  r *= x11000011

  # 256+28 = 284 operations
  r.square_repeated(9)
  r *= x10010101
  r.square_repeated(12)
  r *= x1111011
  r.square_repeated(5)

  # 284 + 21 = 305 operations
  r *= x1011
  r.square_repeated(11)
  r *= x1111011
  r.square_repeated(7)
  r *= x1001

  # 305+32 = 337 operations
  r.square_repeated(13)
  r *= x11110101
  r.square_repeated(9)
  r *= x10111111
  r.square_repeated(8)

  # 337+22 = 359 operations
  r *= x11111111
  r.square_repeated(8)
  r *= x11101011
  r.square_repeated(11)
  r *= x10101001

  # 359+24 = 383 operations
  r.square_repeated(8)
  r *= x11111111
  r.square_repeated(8)
  r *= x11111111
  r.square_repeated(6)

  # 383+22 = 405 operations
  r *= x110111
  r.square_repeated(10)
  r *= x11111111
  r.square_repeated(9)
  r *= x11111111

  # 405+26 = 431 operations
  r.square_repeated(8)
  r *= x11111111
  r.square_repeated(8)
  r *= x11111111
  r.square_repeated(8)

  # 431+19 = 450 operations
  r *= x11111111
  r.square_repeated(7)
  r *= x1010101
  r.square_repeated(9)
  r *= x10101001

  # Total 450 operations:
  # - 74 multiplications
  # - 376 squarings

# BN Curves
# ------------------------------------------------------------

func inv_addchain*(r: var Fp[BN254_Snarks], a: Fp[BN254_Snarks]) =
  var
    x10       {.noInit.}: Fp[BN254_Snarks]
    x11       {.noInit.}: Fp[BN254_Snarks]
    x101      {.noInit.}: Fp[BN254_Snarks]
    x110      {.noInit.}: Fp[BN254_Snarks]
    x1000     {.noInit.}: Fp[BN254_Snarks]
    x1101     {.noInit.}: Fp[BN254_Snarks]
    x10010    {.noInit.}: Fp[BN254_Snarks]
    x10011    {.noInit.}: Fp[BN254_Snarks]
    x10100    {.noInit.}: Fp[BN254_Snarks]
    x10111    {.noInit.}: Fp[BN254_Snarks]
    x11100    {.noInit.}: Fp[BN254_Snarks]
    x100000   {.noInit.}: Fp[BN254_Snarks]
    x100011   {.noInit.}: Fp[BN254_Snarks]
    x101011   {.noInit.}: Fp[BN254_Snarks]
    x101111   {.noInit.}: Fp[BN254_Snarks]
    x1000001  {.noInit.}: Fp[BN254_Snarks]
    x1010011  {.noInit.}: Fp[BN254_Snarks]
    x1011011  {.noInit.}: Fp[BN254_Snarks]
    x1100001  {.noInit.}: Fp[BN254_Snarks]
    x1110101  {.noInit.}: Fp[BN254_Snarks]
    x10010001 {.noInit.}: Fp[BN254_Snarks]
    x10010101 {.noInit.}: Fp[BN254_Snarks]
    x10110101 {.noInit.}: Fp[BN254_Snarks]
    x10111011 {.noInit.}: Fp[BN254_Snarks]
    x11000001 {.noInit.}: Fp[BN254_Snarks]
    x11000011 {.noInit.}: Fp[BN254_Snarks]
    x11010011 {.noInit.}: Fp[BN254_Snarks]
    x11100001 {.noInit.}: Fp[BN254_Snarks]
    x11100011 {.noInit.}: Fp[BN254_Snarks]
    x11100111 {.noInit.}: Fp[BN254_Snarks]

  x10       .square(a)
  x11       .prod(x10, a)
  x101      .prod(x10, x11)
  x110      .prod(x101, a)
  x1000     .prod(x10, x110)
  x1101     .prod(x101, x1000)
  x10010    .prod(x101, x1101)
  x10011    .prod(x10010, a)
  x10100    .prod(x10011, a)
  x10111    .prod(x11, x10100)
  x11100    .prod(x101, x10111)
  x100000   .prod(x1101, x10011)
  x100011   .prod(x11, x100000)
  x101011   .prod(x1000, x100011)
  x101111   .prod(x10011, x11100)
  x1000001  .prod(x10010, x101111)
  x1010011  .prod(x10010, x1000001)
  x1011011  .prod(x1000, x1010011)
  x1100001  .prod(x110, x1011011)
  x1110101  .prod(x10100, x1100001)
  x10010001 .prod(x11100, x1110101)
  x10010101 .prod(x100000, x1110101)
  x10110101 .prod(x100000, x10010101)
  x10111011 .prod(x110, x10110101)
  x11000001 .prod(x110, x10111011)
  x11000011 .prod(x10, x11000001)
  x11010011 .prod(x10010, x11000001)
  x11100001 .prod(x100000, x11000001)
  x11100011 .prod(x10, x11100001)
  x11100111 .prod(x110, x11100001) # 30 operations

  # 30 + 27 = 57 operations
  r.square(x11000001)
  r.square_repeated(7)
  r *= x10010001
  r.square_repeated(10)
  r *= x11100111
  r.square_repeated(7)

  # 57 + 19 = 76 operations
  r *= x10111
  r.square_repeated(9)
  r *= x10011
  r.square_repeated(7)
  r *= x1101

  # 76 + 33 = 109 operations
  r.square_repeated(14)
  r *= x1010011
  r.square_repeated(9)
  r *= x11100001
  r.square_repeated(8)

  # 109 + 18 = 127 operations
  r *= x1000001
  r.square_repeated(10)
  r *= x1011011
  r.square_repeated(5)
  r *= x1101

  # 127 + 34 = 161 operations
  r.square_repeated(8)
  r *= x11
  r.square_repeated(12)
  r *= x101011
  r.square_repeated(12)

  # 161 + 25 = 186 operations
  r *= x10111011
  r.square_repeated(8)
  r *= x101111
  r.square_repeated(14)
  r *= x10110101

  # 186 + 28 = 214
  r.square_repeated(9)
  r *= x10010001
  r.square_repeated(5)
  r *= x1101
  r.square_repeated(12)

  # 214 + 22 = 236
  r *= x11100011
  r.square_repeated(8)
  r *= x10010101
  r.square_repeated(11)
  r *= x11010011

  # 236 + 32 = 268
  r.square_repeated(7)
  r *= x1100001
  r.square_repeated(11)
  r *= x100011
  r.square_repeated(12)

  # 268 + 20 = 288
  r *= x1011011
  r.square_repeated(9)
  r *= x11000011
  r.square_repeated(8)
  r *= x11100111

  # 288 + 15 = 303
  r.square_repeated(7)
  r *= x1110101
  r.square_repeated(6)
  r *= x101

# ############################################################
#
#                         Dispatch
#
# ############################################################

func inv_euclid*(r: var Fp, a: Fp) =
  ## Inversion modulo p via
  ## Niels Moller constant-time version of
  ## Stein's GCD derived from extended binary Euclid algorithm
  r.mres.steinsGCD(a.mres, Fp.C.getR2modP(), Fp.C.Mod, Fp.C.getPrimePlus1div2())

func inv*(r: var Fp, a: Fp) =
  ## Inversion modulo p
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  # For now we don't activate the addition chains
  # neither for Secp256k1 nor BN curves
  # Performance is slower than GCD
  # To be revisited with faster squaring/multiplications
  when Fp.C in {BN254_Snarks, BLS12_381}:
    r.inv_addchain(a)
  else:
    r.inv_euclid(a)

func inv*(a: var Fp) =
  ## Inversion modulo p
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  # For now we don't activate the addition chains
  # for Secp256k1 nor BN curves
  # Performance is slower than GCD
  when Fp.C in {BN254_Snarks, BLS12_381}:
    a.inv_addchain(a)
  else:
    a.inv_euclid(a)
