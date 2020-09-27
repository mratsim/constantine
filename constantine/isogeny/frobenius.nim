# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/macros,
  ../config/[common, curves],
  ../io/io_towers,
  ../towers, ../arithmetic

# Frobenius Map
# ------------------------------------------------------------
#
# https://en.wikipedia.org/wiki/Frobenius_endomorphism
# For p prime
#
#   a^p (mod p) ≡ a (mod p)
#
# Also
#
#   (a + b)^p (mod p) ≡ a^p + b^p (mod p)
#                     ≡ a   + b   (mod p)
#
# Because p is prime and all expanded terms (from binomial expansion)
# besides a^p and b^p are divisible by p

# For 𝔽p2, with `u` the quadratic non-residue (usually the complex 𝑖)
# (a + u b)^p² (mod p²) ≡ a + u^p² b (mod p²)
#
# For 𝔽p2, frobenius acts like the conjugate
# whether u = √-1 = i
# or          √-2 or √-5

func frobenius_map*(r: var Fp2, a: Fp2, k: static int = 1) {.inline.} =
  ## Computes a^(p^k)
  ## The p-power frobenius automorphism on 𝔽p2
  when (k and 1) == 1:
    r.conj(a)
  else:
    r = a

template mulCheckSparse[Fp2](a: var Fp2, b: Fp2) =
  when b.c0.isOne().bool and b.c1.isZero().bool:
    discard
  elif b.c0.isZero().bool and b.c1.isOne().bool:
    var t {.noInit.}: type(a.c0)
    when fromComplexExtension(b):
      t.neg(a.c1)
      a.c1 = a.c0
      a.c0 = t
    else:
      t = NonResidue * a.c1
      a.c1 = a.c0
      a.c0 = t
  elif b.c0.isZero().bool:
    a.mul_sparse_by_0y(b)
  elif b.c1.isZero().bool:
    a.mul_sparse_by_x0(b)
  else:
    a *= b

# Frobenius map - on extension fields
# -----------------------------------------------------------------

# c = (SNR^((p-1)/6)^coef).
# Then for frobenius(2): c * conjugate(c)
# And for frobenius(3): c² * conjugate(c)
const FrobMapConst_BLS12_377 = [
  # frobenius(1)
  [Fp2[BLS12_377].fromHex( # SNR^((p-1)/6)^0
    "0x1",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # SNR^((p-1)/6)^1
    "0x9a9975399c019633c1e30682567f915c8a45e0f94ebc8ec681bf34a3aa559db57668e558eb0188e938a9d1104f2031",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(  # SNR^((p-1)/6)^2 = SNR^((p-1)/3)
    "0x9b3af05dd14f6ec619aaf7d34594aabc5ed1347970dec00452217cc900000008508c00000000002",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex( # SNR^((p-1)/6)^3 = SNR^((p-1)/2)
    "0x1680a40796537cac0c534db1a79beb1400398f50ad1dec1bce649cf436b0f6299588459bff27d8e6e76d5ecf1391c63",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex( # SNR^((p-1)/6)^4 = SNR^(2(p-1)/3)
    "0x9b3af05dd14f6ec619aaf7d34594aabc5ed1347970dec00452217cc900000008508c00000000001",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex( # SNR^((p-1)/6)^5
    "0xcd70cb3fc936348d0351d498233f1fe379531411832232f6648a9a9fc0b9c4e3e21b7467077c05853e2c1be0e9fc32",
    "0x0"
  )],
  # frobenius(2)
  [Fp2[BLS12_377].fromHex( # norm(SNR)^((p-1)/6)^1
    "0x1",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex( # norm(SNR)^((p-1)/6)^2
    "0x9b3af05dd14f6ec619aaf7d34594aabc5ed1347970dec00452217cc900000008508c00000000002",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(
    "0x9b3af05dd14f6ec619aaf7d34594aabc5ed1347970dec00452217cc900000008508c00000000001",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(
    "0x1ae3a4617c510eac63b05c06ca1493b1a22d9f300f5138f1ef3622fba094800170b5d44300000008508c00000000000",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(
    "0x1ae3a4617c510eabc8756ba8f8c524eb8882a75cc9bc8e359064ee822fb5bffd1e945779fffffffffffffffffffffff",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(
    "0x1ae3a4617c510eabc8756ba8f8c524eb8882a75cc9bc8e359064ee822fb5bffd1e94577a00000000000000000000000",
    "0x0"
  )],
  # frobenius(3)
  [Fp2[BLS12_377].fromHex(
    "0x1",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(
    "0x1680a40796537cac0c534db1a79beb1400398f50ad1dec1bce649cf436b0f6299588459bff27d8e6e76d5ecf1391c63",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(
    "0x1ae3a4617c510eac63b05c06ca1493b1a22d9f300f5138f1ef3622fba094800170b5d44300000008508c00000000000",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(
    "0x4630059e5fd9200575d0e552278a89da1f40fdf62334cd620d1860769e389d7db2d8ea700d82721691ea130ec6e39e",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(
    "0x1",
    "0x0"
  ),
  Fp2[BLS12_377].fromHex(
    "0x1680a40796537cac0c534db1a79beb1400398f50ad1dec1bce649cf436b0f6299588459bff27d8e6e76d5ecf1391c63",
    "0x0"
  )]]

# c = (SNR^((p-1)/6)^coef).
# Then for frobenius(2): c * conjugate(c)
# And for frobenius(3): c² * conjugate(c)
const FrobMapConst_BLS12_381 = [
  # frobenius(1)
  [Fp2[BLS12_381].fromHex( # SNR^((p-1)/6)^0
    "0x1",
    "0x0"
  ),
  Fp2[BLS12_381].fromHex(  # SNR^((p-1)/6)^1
    "0x1904d3bf02bb0667c231beb4202c0d1f0fd603fd3cbd5f4f7b2443d784bab9c4f67ea53d63e7813d8d0775ed92235fb8",
    "0xfc3e2b36c4e03288e9e902231f9fb854a14787b6c7b36fec0c8ec971f63c5f282d5ac14d6c7ec22cf78a126ddc4af3"
  ),
  Fp2[BLS12_381].fromHex(  # SNR^((p-1)/6)^2 = SNR^((p-1)/3)
    "0x0",
    "0x1a0111ea397fe699ec02408663d4de85aa0d857d89759ad4897d29650fb85f9b409427eb4f49fffd8bfd00000000aaac"
  ),
  Fp2[BLS12_381].fromHex( # SNR^((p-1)/6)^3 = SNR^((p-1)/2)
    "0x6af0e0437ff400b6831e36d6bd17ffe48395dabc2d3435e77f76e17009241c5ee67992f72ec05f4c81084fbede3cc09",
    "0x6af0e0437ff400b6831e36d6bd17ffe48395dabc2d3435e77f76e17009241c5ee67992f72ec05f4c81084fbede3cc09"
  ),
  Fp2[BLS12_381].fromHex( # SNR^((p-1)/6)^4 = SNR^(2(p-1)/3)
    "0x1a0111ea397fe699ec02408663d4de85aa0d857d89759ad4897d29650fb85f9b409427eb4f49fffd8bfd00000000aaad",
    "0x0"
  ),
  Fp2[BLS12_381].fromHex( # SNR^((p-1)/6)^5
    "0x5b2cfd9013a5fd8df47fa6b48b1e045f39816240c0b8fee8beadf4d8e9c0566c63a3e6e257f87329b18fae980078116",
    "0x144e4211384586c16bd3ad4afa99cc9170df3560e77982d0db45f3536814f0bd5871c1908bd478cd1ee605167ff82995"
  )],
  # frobenius(2)
  [Fp2[BLS12_381].fromHex( # norm(SNR)^((p-1)/6)^1
    "0x1",
    "0x0"
  ),
  Fp2[BLS12_381].fromHex( # norm(SNR)^((p-1)/6)^2
    "0x5f19672fdf76ce51ba69c6076a0f77eaddb3a93be6f89688de17d813620a00022e01fffffffeffff",
    "0x0"
  ),
  Fp2[BLS12_381].fromHex(
    "0x5f19672fdf76ce51ba69c6076a0f77eaddb3a93be6f89688de17d813620a00022e01fffffffefffe",
    "0x0"
  ),
  Fp2[BLS12_381].fromHex(
    "0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaaa",
    "0x0"
  ),
  Fp2[BLS12_381].fromHex(
    "0x1a0111ea397fe699ec02408663d4de85aa0d857d89759ad4897d29650fb85f9b409427eb4f49fffd8bfd00000000aaac",
    "0x0"
  ),
  Fp2[BLS12_381].fromHex(
    "0x1a0111ea397fe699ec02408663d4de85aa0d857d89759ad4897d29650fb85f9b409427eb4f49fffd8bfd00000000aaad",
    "0x0"
  )],
  # frobenius(3)
  [Fp2[BLS12_381].fromHex(
    "0x1",
    "0x0"
  ),
  Fp2[BLS12_381].fromHex(
    "0x135203e60180a68ee2e9c448d77a2cd91c3dedd930b1cf60ef396489f61eb45e304466cf3e67fa0af1ee7b04121bdea2",
    "0x6af0e0437ff400b6831e36d6bd17ffe48395dabc2d3435e77f76e17009241c5ee67992f72ec05f4c81084fbede3cc09"
  ),
  Fp2[BLS12_381].fromHex(
    "0x0",
    "0x1"
  ),
  Fp2[BLS12_381].fromHex(
    "0x135203e60180a68ee2e9c448d77a2cd91c3dedd930b1cf60ef396489f61eb45e304466cf3e67fa0af1ee7b04121bdea2",
    "0x135203e60180a68ee2e9c448d77a2cd91c3dedd930b1cf60ef396489f61eb45e304466cf3e67fa0af1ee7b04121bdea2"
  ),
  Fp2[BLS12_381].fromHex(
    "0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaaa",
    "0x0"
  ),
  Fp2[BLS12_381].fromHex(
    "0x6af0e0437ff400b6831e36d6bd17ffe48395dabc2d3435e77f76e17009241c5ee67992f72ec05f4c81084fbede3cc09",
    "0x135203e60180a68ee2e9c448d77a2cd91c3dedd930b1cf60ef396489f61eb45e304466cf3e67fa0af1ee7b04121bdea2"
  )]]

const FrobMapConst_BN254_Nogami = [
  # frobenius(1)
  [Fp2[BN254_Nogami].fromHex( # SNR^((p-1)/6)^0
    "0x1",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex(  # SNR^((p-1)/6)^1
    "0x1b377619212e7c8cb6499b50a846953f850974924d3f77c2e17de6c06f2a6de9",
    "0x9ebee691ed1837503eab22f57b96ac8dc178b6db2c08850c582193f90d5922a"
  ),
  Fp2[BN254_Nogami].fromHex(  # SNR^((p-1)/6)^2 = SNR^((p-1)/3)
    "0x0",
    "0x25236482400000017080eb4000000006181800000000000cd98000000000000b"
  ),
  Fp2[BN254_Nogami].fromHex( # SNR^((p-1)/6)^3 = SNR^((p-1)/2)
    "0x23dfc9d1a39f4db8c69b87a8848aa075a7333a0e62d78cbf4b1b8eeae58b81c5",
    "0x23dfc9d1a39f4db8c69b87a8848aa075a7333a0e62d78cbf4b1b8eeae58b81c5"
  ),
  Fp2[BN254_Nogami].fromHex( # SNR^((p-1)/6)^4 = SNR^(2(p-1)/3)
    "0x25236482400000017080eb4000000006181800000000000cd98000000000000c",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex( # SNR^((p-1)/6)^5
    "0x19f3db6884cdca43c2b0d5792cd135accb1baea0b017046e859975ab54b5ef9b",
    "0xb2f8919bb3235bdf7837806d32eca5b9605515f4fe8fba521668a54ab4a1078"
  )],
  # frobenius(2)
  [Fp2[BN254_Nogami].fromHex( # norm(SNR)^((p-1)/6)^1
    "0x1",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex( # norm(SNR)^((p-1)/6)^2
    "0x49b36240000000024909000000000006cd80000000000008",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex(
    "0x49b36240000000024909000000000006cd80000000000007",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex(
    "0x2523648240000001ba344d80000000086121000000000013a700000000000012",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex(
    "0x25236482400000017080eb4000000006181800000000000cd98000000000000b",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex(
    "0x25236482400000017080eb4000000006181800000000000cd98000000000000c",
    "0x0"
  )],
  # frobenius(3)
  [Fp2[BN254_Nogami].fromHex(
    "0x1",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex(
    "0x1439ab09c60b248f398c5d77b755f92b9edc5f19d2873545be471151a747e4e",
    "0x23dfc9d1a39f4db8c69b87a8848aa075a7333a0e62d78cbf4b1b8eeae58b81c5"
  ),
  Fp2[BN254_Nogami].fromHex(
    "0x0",
    "0x1"
  ),
  Fp2[BN254_Nogami].fromHex(
    "0x1439ab09c60b248f398c5d77b755f92b9edc5f19d2873545be471151a747e4e",
    "0x1439ab09c60b248f398c5d77b755f92b9edc5f19d2873545be471151a747e4e"
  ),
  Fp2[BN254_Nogami].fromHex(
    "0x2523648240000001ba344d80000000086121000000000013a700000000000012",
    "0x0"
  ),
  Fp2[BN254_Nogami].fromHex(
    "0x23dfc9d1a39f4db8c69b87a8848aa075a7333a0e62d78cbf4b1b8eeae58b81c5",
    "0x1439ab09c60b248f398c5d77b755f92b9edc5f19d2873545be471151a747e4e"
  )]]

const FrobMapConst_BN254_Snarks = [
  # frobenius(1)
  [Fp2[BN254_Snarks].fromHex( # SNR^((p-1)/6)^0
    "0x1",
    "0x0"
  ),
  Fp2[BN254_Snarks].fromHex(  # SNR^((p-1)/6)^1
    "0x1284b71c2865a7dfe8b99fdd76e68b605c521e08292f2176d60b35dadcc9e470",
    "0x246996f3b4fae7e6a6327cfe12150b8e747992778eeec7e5ca5cf05f80f362ac"
  ),
  Fp2[BN254_Snarks].fromHex(  # SNR^((p-1)/6)^2 = SNR^((p-1)/3)
    "0x2fb347984f7911f74c0bec3cf559b143b78cc310c2c3330c99e39557176f553d",
    "0x16c9e55061ebae204ba4cc8bd75a079432ae2a1d0b7c9dce1665d51c640fcba2"
  ),
  Fp2[BN254_Snarks].fromHex( # SNR^((p-1)/6)^3 = SNR^((p-1)/2)
    "0x63cf305489af5dcdc5ec698b6e2f9b9dbaae0eda9c95998dc54014671a0135a",
    "0x7c03cbcac41049a0704b5a7ec796f2b21807dc98fa25bd282d37f632623b0e3"
  ),
  Fp2[BN254_Snarks].fromHex( # SNR^((p-1)/6)^4 = SNR^(2(p-1)/3)
    "0x5b54f5e64eea80180f3c0b75a181e84d33365f7be94ec72848a1f55921ea762",
    "0x2c145edbe7fd8aee9f3a80b03b0b1c923685d2ea1bdec763c13b4711cd2b8126"
  ),
  Fp2[BN254_Snarks].fromHex( # SNR^((p-1)/6)^5
    "0x183c1e74f798649e93a3661a4353ff4425c459b55aa1bd32ea2c810eab7692f",
    "0x12acf2ca76fd0675a27fb246c7729f7db080cb99678e2ac024c6b8ee6e0c2c4b"
  )],
  # frobenius(2)
  [Fp2[BN254_Snarks].fromHex( # norm(SNR)^((p-1)/6)^1
    "0x1",
    "0x0"
  ),
  Fp2[BN254_Snarks].fromHex( # norm(SNR)^((p-1)/6)^2
    "0x30644e72e131a0295e6dd9e7e0acccb0c28f069fbb966e3de4bd44e5607cfd49",
    "0x0"
  ),
  Fp2[BN254_Snarks].fromHex(
    "0x30644e72e131a0295e6dd9e7e0acccb0c28f069fbb966e3de4bd44e5607cfd48",
    "0x0"
  ),
  Fp2[BN254_Snarks].fromHex(
    "0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd46",
    "0x0"
  ),
  Fp2[BN254_Snarks].fromHex(
    "0x59e26bcea0d48bacd4f263f1acdb5c4f5763473177fffffe",
    "0x0"
  ),
  Fp2[BN254_Snarks].fromHex(
    "0x59e26bcea0d48bacd4f263f1acdb5c4f5763473177ffffff",
    "0x0"
  )],
  # frobenius(3)
  [Fp2[BN254_Snarks].fromHex(
    "0x1",
    "0x0"
  ),
  Fp2[BN254_Snarks].fromHex(
    "0x19dc81cfcc82e4bbefe9608cd0acaa90894cb38dbe55d24ae86f7d391ed4a67f",
    "0xabf8b60be77d7306cbeee33576139d7f03a5e397d439ec7694aa2bf4c0c101"
  ),
  Fp2[BN254_Snarks].fromHex(
    "0x856e078b755ef0abaff1c77959f25ac805ffd3d5d6942d37b746ee87bdcfb6d",
    "0x4f1de41b3d1766fa9f30e6dec26094f0fdf31bf98ff2631380cab2baaa586de"
  ),
  Fp2[BN254_Snarks].fromHex(
    "0x2a275b6d9896aa4cdbf17f1dca9e5ea3bbd689a3bea870f45fcc8ad066dce9ed",
    "0x28a411b634f09b8fb14b900e9507e9327600ecc7d8cf6ebab94d0cb3b2594c64"
  ),
  Fp2[BN254_Snarks].fromHex(
    "0xbc58c6611c08dab19bee0f7b5b2444ee633094575b06bcb0e1a92bc3ccbf066",
    "0x23d5e999e1910a12feb0f6ef0cd21d04a44a9e08737f96e55fe3ed9d730c239f"
  ),
  Fp2[BN254_Snarks].fromHex(
    "0x13c49044952c0905711699fa3b4d3f692ed68098967c84a5ebde847076261b43",
    "0x16db366a59b1dd0b9fb1b2282a48633d3e2ddaea200280211f25041384282499"
  )]]

{.experimental: "dynamicBindSym".}

macro frobMapConst(C: static Curve): untyped =
  return bindSym("FrobMapConst_" & $C)

func frobenius_map*[C](r: var Fp4[C], a: Fp4[C], k: static int = 1) {.inline.} =
  ## Computes a^(p^k)
  ## The p-power frobenius automorphism on 𝔽p4
  r.c0.frobenius_map(a.c0, k)
  r.c1.frobenius_map(a.c1, k)
  r.c1.mulCheckSparse frobMapConst(C)[k-1][3]

func frobenius_map*[C](r: var Fp6[C], a: Fp6[C], k: static int = 1) {.inline.} =
  ## Computes a^(p^k)
  ## The p-power frobenius automorphism on 𝔽p6
  r.c0.frobenius_map(a.c0, k)
  r.c1.frobenius_map(a.c1, k)
  r.c2.frobenius_map(a.c2, k)
  r.c1.mulCheckSparse frobMapConst(C)[k-1][2]
  r.c2.mulCheckSparse frobMapConst(C)[k-1][4]

func frobenius_map*[C](r: var Fp12[C], a: Fp12[C], k: static int = 1) {.inline.} =
  ## Computes a^(p^k)
  ## The p-power frobenius automorphism on 𝔽p12
  static: doAssert r.c0 is Fp4
  for r_fp4, a_fp4 in fields(r, a):
    for r_fp2, a_fp2 in fields(r_fp4, a_fp4):
      r_fp2.frobenius_map(a_fp2, k)

  r.c0.c0.mulCheckSparse frobMapConst(C)[k-1][0]
  r.c0.c1.mulCheckSparse frobMapConst(C)[k-1][3]
  r.c1.c0.mulCheckSparse frobMapConst(C)[k-1][1]
  r.c1.c1.mulCheckSparse frobMapConst(C)[k-1][4]
  r.c2.c0.mulCheckSparse frobMapConst(C)[k-1][2]
  r.c2.c1.mulCheckSparse frobMapConst(C)[k-1][5]

# ψ (Psi) - Untwist-Frobenius-Twist Endomorphisms on twisted curves
# -----------------------------------------------------------------
# TODO: generate those constants via Sage in a Json file
#       and parse at compile-time

# Constants:
#   Assuming embedding degree of 12 and a sextic twist
#   with SNR the sextic non-residue
#
#   BN254_Snarks is a D-Twist: SNR^((p-1)/6)
const FrobPsiConst_BN254_Snarks_psi1_coef1 = Fp2[BN254_Snarks].fromHex(
  "0x1284b71c2865a7dfe8b99fdd76e68b605c521e08292f2176d60b35dadcc9e470",
  "0x246996f3b4fae7e6a6327cfe12150b8e747992778eeec7e5ca5cf05f80f362ac"
)
#  SNR^((p-1)/3)
const FrobPsiConst_BN254_Snarks_psi1_coef2 = Fp2[BN254_Snarks].fromHex(
  "0x2fb347984f7911f74c0bec3cf559b143b78cc310c2c3330c99e39557176f553d",
  "0x16c9e55061ebae204ba4cc8bd75a079432ae2a1d0b7c9dce1665d51c640fcba2"
)
#  SNR^((p-1)/2)
const FrobPsiConst_BN254_Snarks_psi1_coef3 = Fp2[BN254_Snarks].fromHex(
  "0x63cf305489af5dcdc5ec698b6e2f9b9dbaae0eda9c95998dc54014671a0135a",
  "0x7c03cbcac41049a0704b5a7ec796f2b21807dc98fa25bd282d37f632623b0e3"
)
#  norm(SNR)^((p-1)/3)
const FrobPsiConst_BN254_Snarks_psi2_coef2 = Fp2[BN254_Snarks].fromHex(
  "0x30644e72e131a0295e6dd9e7e0acccb0c28f069fbb966e3de4bd44e5607cfd48",
  "0x0"
)

#   BN254_Nogami is a D-Twist: SNR^((p-1)/6)
const FrobPsiConst_BN254_Nogami_psi1_coef1 = Fp2[BN254_Nogami].fromHex(
  "0x1b377619212e7c8cb6499b50a846953f850974924d3f77c2e17de6c06f2a6de9",
  "0x9ebee691ed1837503eab22f57b96ac8dc178b6db2c08850c582193f90d5922a"
)
#  SNR^((p-1)/3)
const FrobPsiConst_BN254_Nogami_psi1_coef2 = Fp2[BN254_Nogami].fromHex(
  "0x0",
  "0x25236482400000017080eb4000000006181800000000000cd98000000000000b"
)
#  SNR^((p-1)/2)
const FrobPsiConst_BN254_Nogami_psi1_coef3 = Fp2[BN254_Nogami].fromHex(
  "0x23dfc9d1a39f4db8c69b87a8848aa075a7333a0e62d78cbf4b1b8eeae58b81c5",
  "0x23dfc9d1a39f4db8c69b87a8848aa075a7333a0e62d78cbf4b1b8eeae58b81c5"
)
#  norm(SNR)^((p-1)/3)
const FrobPsiConst_BN254_Nogami_psi2_coef2 = Fp2[BN254_Nogami].fromHex(
  "0x49b36240000000024909000000000006cd80000000000007",
  "0x0"
)

#   BLS12_377 is a D-Twist: SNR^((p-1)/6)
const FrobPsiConst_BLS12_377_psi1_coef1 = Fp2[BLS12_377].fromHex(
  "0x9a9975399c019633c1e30682567f915c8a45e0f94ebc8ec681bf34a3aa559db57668e558eb0188e938a9d1104f2031",
  "0x0"
)
#  SNR^((p-1)/3)
const FrobPsiConst_BLS12_377_psi1_coef2 = Fp2[BLS12_377].fromHex(
  "0x9b3af05dd14f6ec619aaf7d34594aabc5ed1347970dec00452217cc900000008508c00000000002",
  "0x0"
)
#  SNR^((p-1)/2)
const FrobPsiConst_BLS12_377_psi1_coef3 = Fp2[BLS12_377].fromHex(
  "0x1680a40796537cac0c534db1a79beb1400398f50ad1dec1bce649cf436b0f6299588459bff27d8e6e76d5ecf1391c63",
  "0x0"
)
#  norm(SNR)^((p-1)/3)
const FrobPsiConst_BLS12_377_psi2_coef2 = Fp2[BLS12_377].fromHex(
  "0x9b3af05dd14f6ec619aaf7d34594aabc5ed1347970dec00452217cc900000008508c00000000001",
  "0x0"
)

#   BLS12_381 is a M-twist: (1/SNR)^((p-1)/6)
const FrobPsiConst_BLS12_381_psi1_coef1 = Fp2[BLS12_381].fromHex(
  "0x5b2cfd9013a5fd8df47fa6b48b1e045f39816240c0b8fee8beadf4d8e9c0566c63a3e6e257f87329b18fae980078116",
  "0x5b2cfd9013a5fd8df47fa6b48b1e045f39816240c0b8fee8beadf4d8e9c0566c63a3e6e257f87329b18fae980078116"
)
#  (1/SNR)^((p-1)/3)
const FrobPsiConst_BLS12_381_psi1_coef2 = Fp2[BLS12_381].fromHex(
  "0x0",
  "0x1a0111ea397fe699ec02408663d4de85aa0d857d89759ad4897d29650fb85f9b409427eb4f49fffd8bfd00000000aaad"
)
#  (1/SNR)^((p-1)/2)
const FrobPsiConst_BLS12_381_psi1_coef3 = Fp2[BLS12_381].fromHex(
  "0x135203e60180a68ee2e9c448d77a2cd91c3dedd930b1cf60ef396489f61eb45e304466cf3e67fa0af1ee7b04121bdea2",
  "0x6af0e0437ff400b6831e36d6bd17ffe48395dabc2d3435e77f76e17009241c5ee67992f72ec05f4c81084fbede3cc09"
)
#  norm(SNR)^((p-1)/3)
const FrobPsiConst_BLS12_381_psi2_coef2 = Fp2[BLS12_381].fromHex(
  "0x1a0111ea397fe699ec02408663d4de85aa0d857d89759ad4897d29650fb85f9b409427eb4f49fffd8bfd00000000aaac",
  "0x0"
)

macro frobPsiConst(C: static Curve, psipow, coefpow: static int): untyped =
  return bindSym("FrobPsiConst_" & $C & "_psi" & $psipow & "_coef" & $coefpow)

func frobenius_psi*[PointG2](r: var PointG2, P: PointG2) =
  ## "Untwist-Frobenius-Twist" endomorphism
  ## r = ψ(P)
  for coordR, coordP in fields(r, P):
    coordR.frobenius_map(coordP, 1)

  # With ξ (xi) the sextic non-residue
  # c = ξ^((p-1)/6) for D-Twist
  # c = (1/ξ)^((p-1)/6) for M-Twist
  #
  # c1_2 = c²
  # c1_3 = c³

  r.x.mulCheckSparse frobPsiConst(PointG2.F.C, psipow=1, coefpow=2)
  r.y.mulCheckSparse frobPsiConst(PointG2.F.C, psipow=1, coefpow=3)

func frobenius_psi2*[PointG2](r: var PointG2, P: PointG2) =
  ## "Untwist-Frobenius-Twist" endomorphism applied twice
  ## r = ψ(ψ(P))
  for coordR, coordP in fields(r, P):
    coordR.frobenius_map(coordP, 2)

  # With ξ (xi) the sextic non-residue
  # c = ξ for D-Twist
  # c = (1/ξ) for M-Twist
  #
  # frobenius(a) = conj(a) = a^p
  #
  # c1_2 = (c^((p-1)/6))² = c^((p-1)/3)
  # c1_3 = (c^((p-1)/6))³ = c^((p-1)/2)
  #
  # c2_2 = c1_2 * frobenius(c1_2) = c^((p-1)/3) * c^((p-1)/3)^p
  #      = c^((p-1)/3) * conj(c)^((p-1)/3)
  #      = norm(c)^((p-1)/3)
  #
  # c2_3 = c1_3 * frobenius(c1_3) = c^((p-1)/2) * c^((p-1)/2)^p
  #      = c^((p-1)/2) * conj(c)^((p-1)/2)
  #      = norm(c)^((p-1)/2)
  # We prove that c2_3 ≡ -1 (mod p²) with the following:
  #
  # - Whether c = ξ or c = (1/ξ), c is a quadratic non-residue (QNR) in 𝔽p2
  #   because:
  #   - ξ is quadratic non-residue as it is a sextic non-residue
  #     by construction of the tower extension
  #   - if a is QNR then 1/a is also a QNR
  # - Then c^((p²-1)/2) ≡ -1 (mod p²) from the Legendre symbol in 𝔽p2
  #
  # c2_3 = c^((p-1)/2) * c^((p-1)/2)^p = c^((p+1)*(p-1)/2)
  #      = c^((p²-1)/2)
  # c2_3 ≡ -1 (mod p²)
  # QED

  r.x.mulCheckSparse frobPsiConst(PointG2.F.C, psipow=2, coefpow=2)
  r.y.neg(r.y)
