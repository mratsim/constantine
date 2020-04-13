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
template repeat(num: int, body: untyped) =
  for _ in 0 ..< num:
    body

# Secp256k1
# ------------------------------------------------------------
func invmod_addchain(r: var Fp[Secp256k1], a: Fp[Secp256k1]) =
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
  repeat 3: x6.square()
  x6 *= x3

  x9 = x6
  repeat 3: x9.square()
  x9 *= x3

  x11 = x9
  repeat 2: x11.square()
  x11 *= x2

  x22 = x11
  repeat 11: x22.square()
  x22 *= x11

  x44 = x22
  repeat 22: x44.square()
  x44 *= x22

  x88 = x44
  repeat 44: x88.square()
  x88 *= x44

  x176 = x88
  repeat 88: x88.square()
  x176 *= x88

  x220 = x176
  repeat 44: x220.square()
  x220 *= x44

  x223 = x220
  repeat 3: x223.square()
  x223 *= x3

  # The final result is then assembled using a sliding window over the blocks
  r = x223
  repeat 23: r.square()
  r *= x22
  repeat 5: r.square()
  r *= a
  repeat 3: r.square()
  r *= x2
  repeat 2: r.square()
  r *= a

# BN Curves
# ------------------------------------------------------------
# Efficient Pairings and ECC for Embedded Systems
# Thomas Unterluggauer and Erich Wenger
# https://eprint.iacr.org/2014/800.pdf
#
# BN curve field modulus are of the form:
#   p = 36u^4 + 36u^3 + 24u^2 + 6u + 1
#
# We construct the following multiplication-squaring chain
# a^-1 mod p = a^(p-2) mod p                 (Little Fermat Theorem)
#            = a^(36 u^4 + 36 u^3 + 24 u^2 + 6u + 1 - 2) mod p
#            = a^(36 u^4) . a^(36 u^3) . a^(24 u^2) . a^(6u-1) mod p
#
# Note: it only works for u positive, in particular BN254 doesn't work :/
#       Is there a way to only use a^-u or even powers?

func invmod_addchain_bn[C](r: var Fp[C], a: Fp[C]) =
  ## Inversion on BN prime fields with positive base parameter `u`
  ## via Little Fermat theorem and leveraging the prime low Hamming weight
  ##
  ## Requires a `bn` curve with a positive parameter `u`
  # TODO: debug for input "0x0d2007d8aaface1b8501bfbe792974166e8f9ad6106e5b563604f0aea9ab06f6"
  #       see test suite
  static: doAssert C.canUse_BN_AddchainInversion()

  var v0 {.noInit.}, v1 {.noInit.}: Fp[C]

  v0 = a
  v0.powUnsafeExponent(C.getBN_param_6u_minus_1_BE()) # v0 <- a^(6u-1)
  v1.prod(v0, a)                                      # v1 <- a^(6u)
  v1.powUnsafeExponent(C.getBN_param_u_BE())          # v1 <- a^(6u²)
  r.square(v1)                                        # r  <- a^(12u²)
  v1.square(r)                                        # v1 <- a^(24u²)
  v0 *= v1                                            # v0 <- a^(24u²) a^(6u-1)
  v1 *= r                                             # v1 <- a^(24u²) a^(12u²) = a^(36u²)
  v1.powUnsafeExponent(C.getBN_param_u_BE())          # v1 <- a^(36u³)
  r.prod(v0, v1)                                      # r  <- a^(36u³) a^(24u²) a^(6u-1)
  v1.powUnsafeExponent(C.getBN_param_u_BE())          # v1 <- a^(36u⁴)
  r *= v1                                             # r  <- a^(36u⁴) a^(36u³) a^(24u²) a^(6u-1) = a^(p-2) = a^(-1)

# ############################################################
#
#                         Dispatch
#
# ############################################################

func inv*(r: var Fp, a: Fp) =
  ## Inversion modulo p
  # For now we don't activate the addition chains
  # neither for Secp256k1 nor BN curves
  # Performance is slower than GCD
  # To be revisited with faster squaring/multiplications
  r.mres.steinsGCD(a.mres, Fp.C.getR2modP(), Fp.C.Mod, Fp.C.getPrimePlus1div2())
