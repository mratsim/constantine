# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  constantine/ethereum_evm_precompiles,
  constantine/serialization/codecs,
  constantine/named/algebras,
  constantine/math/[arithmetic, ec_shortweierstrass, extension_fields],
  constantine/math/io/[io_bigints, io_fields],
  constantine/named/zoo_subgroups,
  # Stdlib
  std/tables,
  # Helpers
  ./bench_blueprint,
  helpers/prng_unsafe,
  # Standard library
  std/[os, strutils]

# For EIP-2537, we use the worst case vectors:
#   https://eips.ethereum.org/assets/eip-2537/bench_vectors

proc separator() = separator(128)

proc report(op: string, gas: int, startTime, stopTime: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stopTime-startTime) div iters)
  let throughput = 1e9 / float64(ns)
  let throughputMGas = throughput * 1e-6 * float64(gas)
  let cycles = (stopClk - startClk) div iters
  when SupportsGetTicks:
    echo &"{op:<24} {gas:>7} gas {throughputMGas:>10.2f} MGas/s {throughput:>15.3f} ops/s {ns:>12} ns/op {cycles:>12} CPU cycles (approx)"
  else:
    echo &"{op:<24} {gas:>7} gas {throughputMGas:>10.2f} MGas/s {throughput:>15.3f} ops/s {ns:>12} ns/op"

template bench(op: string, gas: int, iters: int, body: untyped): untyped =
  measure(iters, startTime, stopTime, startClk, stopClk, body)
  report(op, gas, startTime, stopTime, startClk, stopClk, iters)

# Gas schedule
# -----------------------------------------------------------------------------------------------------

const gasSchedule = {
  # Hashes
  "KECCAK256":               -1,
  "RIPEMD160":               -1,
  "SHA256":                  -1,
  # ECRecover
  "ECRECOVER":             3000,
  # EIP-196 and 197, gas cost from EIP-1108
  "BN254_G1ADD":            150,
  "BN254_G1MUL":           6000,
  "BN254_PAIRINGCHECK":      -1,
  # EIP 2537
  "BLS12_G1ADD":            375,
  "BLS12_G1MUL":          12000,
  "BLS12_G1MSM":             -1,
  "BLS12_G2ADD":            600,
  "BLS12_G2MUL":          22500,
  "BLS12_G2MSM":             -1,
  "BLS12_PAIRINGCHECK":      -1,
  "BLS12_MAP_FP_TO_G1":    5500,
  "BLS12_MAP_FP2_TO_G2":  23800,
  # EIP 4844
  "KZG_POINT_EVALUATION": 50000,
}.toTable()

func gasKeccak256(length: int): int =
  # 30 gas + 6 gas per 32 byte word
  # This does not take into account the gas for memory expansion
  return 30 + 6 * ((length+31) div 32)

func gasSha256(length: int): int =
  # 60 gas + 12 gas per 32 byte word
  return 60 + 12 * ((length+31) div 32)

func gasRipeMD160(length: int): int =
  # 600 gas + 120 gas per 32 byte word
  return 600 + 120 * ((length+31) div 32)

func gasBN254PairingCheck(length: int): int =
  return 34000*length + 45000

func gasBls12MsmG1(length: int, baseCost: int): int =
  const discount: array[1..128, int] = [1000, 949, 848, 797, 764, 750, 738, 728, 719, 712, 705, 698, 692, 687, 682, 677, 673, 669, 665, 661, 658, 654, 651, 648, 645, 642, 640, 637, 635, 632, 630, 627, 625, 623, 621, 619, 617, 615, 613, 611, 609, 608, 606, 604, 603, 601, 599, 598, 596, 595, 593, 592, 591, 589, 588, 586, 585, 584, 582, 581, 580, 579, 577, 576, 575, 574, 573, 572, 570, 569, 568, 567, 566, 565, 564, 563, 562, 561, 560, 559, 558, 557, 556, 555, 554, 553, 552, 551, 550, 549, 548, 547, 547, 546, 545, 544, 543, 542, 541, 540, 540, 539, 538, 537, 536, 536, 535, 534, 533, 532, 532, 531, 530, 529, 528, 528, 527, 526, 525, 525, 524, 523, 522, 522, 521, 520, 520, 519]
  const multiplier = 1000
  return length * baseCost * discount[min(length, discount.high)] div multiplier

func gasBls12MsmG2(length: int, baseCost: int): int =
  const discount: array[1..128, int] = [1000, 1000, 923, 884, 855, 832, 812, 796, 782, 770, 759, 749, 740, 732, 724, 717, 711, 704, 699, 693, 688, 683, 679, 674, 670, 666, 663, 659, 655, 652, 649, 646, 643, 640, 637, 634, 632, 629, 627, 624, 622, 620, 618, 615, 613, 611, 609, 607, 606, 604, 602, 600, 598, 597, 595, 593, 592, 590, 589, 587, 586, 584, 583, 582, 580, 579, 578, 576, 575, 574, 573, 571, 570, 569, 568, 567, 566, 565, 563, 562, 561, 560, 559, 558, 557, 556, 555, 554, 553, 552, 552, 551, 550, 549, 548, 547, 546, 545, 545, 544, 543, 542, 541, 541, 540, 539, 538, 537, 537, 536, 535, 535, 534, 533, 532, 532, 531, 530, 530, 529, 528, 528, 527, 526, 526, 525, 524, 524]
  const multiplier = 1000
  return length * baseCost * discount[min(length, discount.high)] div multiplier

func gasBls12PairingCheck(length: int): int =
  return 32600*length + 37700

# Constructors
# -----------------------------------------------------------------------------------------------------

func clearCofactor[F; G: static Subgroup](ec: var EC_ShortW_Aff[F, G]) =
  # For now we don't have any affine operation defined
  var t {.noInit.}: EC_ShortW_Prj[F, G]
  t.fromAffine(ec)
  t.clearCofactor()
  ec.affine(t)

proc createPairingInputsBN254(length: int): seq[byte] =
  var buf: array[32, byte]
  const Name = BN254_Snarks
  for _ in 0 ..< length:
    var P = rng.random_unsafe(EC_ShortW_Aff[Fp[Name], G1])
    P.clearCofactor()
    var Q = rng.random_unsafe(EC_ShortW_Aff[Fp2[Name], G2])
    Q.clearCofactor()

    buf.marshal(P.x, bigEndian)
    result.add buf
    buf.marshal(P.y, bigEndian)
    result.add buf

    # Coordinates are serialized in a swapped order

    buf.marshal(Q.x.c1, bigEndian)
    result.add buf
    buf.marshal(Q.x.c0, bigEndian)
    result.add buf

    buf.marshal(Q.y.c1, bigEndian)
    result.add buf
    buf.marshal(Q.y.c0, bigEndian)
    result.add buf


proc createPairingInputsBLS12381(length: int): seq[byte] =
  var buf: array[64, byte]
  const Name = BLS12_381
  for _ in 0 ..< length:
    var P = rng.random_unsafe(EC_ShortW_Aff[Fp[Name], G1])
    P.clearCofactor()
    var Q = rng.random_unsafe(EC_ShortW_Aff[Fp2[Name], G2])
    Q.clearCofactor()

    buf.marshal(P.x, bigEndian)
    result.add buf
    buf.marshal(P.y, bigEndian)
    result.add buf

    buf.marshal(Q.x.c0, bigEndian)
    result.add buf
    buf.marshal(Q.x.c1, bigEndian)
    result.add buf
    buf.marshal(Q.y.c0, bigEndian)
    result.add buf
    buf.marshal(Q.y.c1, bigEndian)
    result.add buf

# Hashes
# -----------------------------------------------------------------------------------------------------

proc benchKeccak256(words, iters: int) =
  let length = words*32
  var inputs = rng.random_byte_seq(length)
  var output: array[32, byte]

  let opName = &"Keccak256 - {length:>3} bytes"
  bench(opName, gasKeccak256(length), iters):
    keccak256.hash(output, inputs)

proc benchSha256(words, iters: int) =
  let length = words*32
  var inputs = rng.random_byte_seq(length)
  var output = newSeq[byte](32)

  let opName = &"SHA256 - {length:>3} bytes"
  bench(opName, gasSha256(length), iters):
    discard output.eth_evm_sha256(inputs)

proc benchRipeMD160(words, iters: int) =
  let length = words*32
  var inputs = rng.random_byte_seq(length)
  var output = newSeq[byte](32)

  let opName = &"RipeMD160 - {length:>3} bytes"
  bench(opName, gasRipeMD160(length), iters):
    discard output.eth_evm_ripemd160(inputs)

# EcRecover
# -----------------------------------------------------------------------------------------------------

proc benchEcRecover(iters: int) =
  let inputhex = "18c547e4f7b0f325ad1e56f57e26c745b09a3e503d86e00e5255ff7f715d3d1c000000000000000000000000000000000000000000000000000000000000001c73b1693892219d736caba55bdb67216e485557ea6b6af75f37096c9aa6a5a75feeb940b1d03b21e36b0e47e79769f095fe2ab855bd91e3a38756b7d75a9c4549"
  var input = newSeq[byte](inputhex.len div 2)
  input.paddedFromHex(inputhex, bigEndian)
  var output = newSeq[byte](32)

  let opName = "ECRECOVER"
  bench(opName, gasSchedule[opName], iters):
    discard output.eth_evm_ecrecover(input)

# EIP-196 & EIP-197
# -----------------------------------------------------------------------------------------------------

proc benchBN254G1Add(iters: int) =
  var inputs = newSeq[byte](128)
  var output = newSeq[byte](64)
  inputs.fromHex("18b18acfb4c2c30276db5411368e7185b311dd124691610c5d3b74034e093dc9063c909c4720840cb5134cb9f59fa749755796819658d32efc0d288198f3726607c2b7f58a84bd6145f00c9c2bc0bb1a187f20ff2c92963a88019e7c6a014eed06614e20c147e940f2d70da3f74c9a17df361706a4485c742bd6788478fa17d7")

  let opName = "BN254_G1ADD"
  bench(opName, gasSchedule[opName], iters):
    discard output.eth_evm_bn254_g1add(inputs)

proc benchBN254G1Mul(iters: int) =
  var inputs = newSeq[byte](96)
  var output = newSeq[byte](64)
  inputs.fromHex("070a8d6a982153cae4be29d434e8faef8a47b274a053f5a4ee2a6c9c13c31e5c031b8ce914eba3a9ffb989f9cdd5b0f01943074bf4f0f315690ec3cec6981afc30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd46")

  let opName = "BN254_G1MUL"
  bench(opName, gasSchedule[opName], iters):
    discard output.eth_evm_bn254_g1mul(inputs)

proc benchBN254PairingCheck(pairingCtx: seq[byte], size, iters: int) =
  var inputs = @(pairingCtx.toOpenArray(0, 192*size-1))
  var output = newSeq[byte](32)

  bench(&"BN254_PAIRINGCHECK {size:>1}", gasBN254PairingCheck(size), iters):
    discard output.eth_evm_bn254_ecpairingcheck(inputs)

# EIP-2537
# -----------------------------------------------------------------------------------------------------

proc benchBls12G1Add(iters: int) =
  var inputs = newSeq[byte](256)
  var output = newSeq[byte](128)
  inputs.fromHex("0x0000000000000000000000000000000012196c5a43d69224d8713389285f26b98f86ee910ab3dd668e413738282003cc5b7357af9a7af54bb713d62255e80f560000000000000000000000000000000006ba8102bfbeea4416b710c73e8cce3032c31c6269c44906f8ac4f7874ce99fb17559992486528963884ce429a992fee000000000000000000000000000000000001101098f5c39893765766af4512a0c74e1bb89bc7e6fdf14e3e7337d257cc0f94658179d83320b99f31ff94cd2bac0000000000000000000000000000000003e1a9f9f44ca2cdab4f43a1a3ee3470fdf90b2fc228eb3b709fcd72f014838ac82a6d797aeefed9a0804b22ed1ce8f7")

  let opName = "BLS12_G1ADD"
  bench(opName, gasSchedule[opName], iters):
    discard output.eth_evm_bls12381_g1add(inputs)

proc benchBls12G2Add(iters: int) =
  var inputs = newSeq[byte](512)
  var output = newSeq[byte](256)
  inputs.fromHex("0x0000000000000000000000000000000018c0ada6351b70661f053365deae56910798bd2ace6e2bf6ba4192d1a229967f6af6ca1c9a8a11ebc0a232344ee0f6d6000000000000000000000000000000000cc70a587f4652039d8117b6103858adcd9728f6aebe230578389a62da0042b7623b1c0436734f463cfdd187d20903240000000000000000000000000000000009f50bd7beedb23328818f9ffdafdb6da6a4dd80c5a9048ab8b154df3cad938ccede829f1156f769d9e149791e8e0cd900000000000000000000000000000000079ba50d2511631b20b6d6f3841e616e9d11b68ec3368cd60129d9d4787ab56c4e9145a38927e51c9cd6271d493d938800000000000000000000000000000000192fa5d8732ff9f38e0b1cf12eadfd2608f0c7a39aced7746837833ae253bb57ef9c0d98a4b69eeb2950901917e99d1e0000000000000000000000000000000009aeb10c372b5ef1010675c6a4762fda33636489c23b581c75220589afbc0cc46249f921eea02dd1b761e036ffdbae220000000000000000000000000000000002d225447600d49f932b9dd3ca1e6959697aa603e74d8666681a2dca8160c3857668ae074440366619eb8920256c4e4a00000000000000000000000000000000174882cdd3551e0ce6178861ff83e195fecbcffd53a67b6f10b4431e423e28a480327febe70276036f60bb9c99cf7633")

  let opName = "BLS12_G2ADD"
  bench(opName, gasSchedule[opName], iters):
    discard output.eth_evm_bls12381_g2add(inputs)

proc benchBls12G1Mul(iters: int) =
  var inputs = newSeq[byte](160)
  var output = newSeq[byte](128)
  # G1 Mul worst-case
  inputs.fromHex("0x0000000000000000000000000000000017f1d3a73197d7942695638c4fa9ac0fc3688c4f9774b905a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb0000000000000000000000000000000008b3f481e3aaa0f1a09e30ed741d8ae4fcf5e095d5d00af600db18cb2c04b3edd03cc744a2888ae40caa232946c5e7e1ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")

  let opName = "BLS12_G1MUL"
  bench(opName, gasSchedule[opName], iters):
    discard output.eth_evm_bls12381_g1mul(inputs)

proc benchBls12G2Mul(iters: int) =
  var inputs = newSeq[byte](288)
  var output = newSeq[byte](256)
  # G2 Mul worst-case
  inputs.fromHex("0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051c6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb80000000000000000000000000000000013e02b6052719f607dacd3a088274f65596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351aadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99cb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79beffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")

  let opName = "BLS12_G2MUL"
  bench(opName, gasSchedule[opName], iters):
    discard output.eth_evm_bls12381_g2mul(inputs)

proc benchBls12MapToG1(iters: int) =
  var inputs = newSeq[byte](64)
  var output = newSeq[byte](128)
  # G1 Mul worst-case
  inputs.fromHex("0x00000000000000000000000000000000156c8a6a2c184569d69a76be144b5cdc5141d2d2ca4fe341f011e25e3969c55ad9e9b9ce2eb833c81a908e5fa4ac5f03")

  let opName = "BLS12_MAP_FP_TO_G1"
  bench(opName, gasSchedule[opName], iters):
    discard output.eth_evm_bls12381_map_fp_to_g1(inputs)

proc benchBls12MapToG2(iters: int) =
  var inputs = newSeq[byte](128)
  var output = newSeq[byte](256)
  # G2 Mul worst-case
  inputs.fromHex("0x0000000000000000000000000000000007355d25caf6e7f2f0cb2812ca0e513bd026ed09dda65b177500fa31714e09ea0ded3a078b526bed3307f804d4b93b040000000000000000000000000000000002829ce3c021339ccb5caf3e187f6370e1e2a311dec9b75363117063ab2015603ff52c3d3b98f19c2f65575e99e8b78c")

  let opName = "BLS12_MAP_FP2_TO_G2"
  bench(opName, gasSchedule[opName], iters):
    discard output.eth_evm_bls12381_map_fp2_to_g2(inputs)

proc benchBls12PairingCheck(pairingCtx: seq[byte], size, iters: int) =
  var inputs = @(pairingCtx.toOpenArray(0, 384*size-1))
  var output = newSeq[byte](32)

  bench(&"BLS12_PAIRINGCHECK {size:>1}", gasBls12PairingCheck(size), iters):
    discard output.eth_evm_bls12381_pairingcheck(inputs)

proc createMsmInputs(EC: typedesc, length: int): seq[byte] =
  var P: affine(EC)
  var buf64: array[64, byte]
  var buf32: array[32, byte]

  for _ in 0 ..< length:
    var t = rng.random_unsafe(EC)
    t.clearCofactor()
    P.affine(t)
    when EC.F is Fp:
      buf64.marshal(P.x, bigEndian)
      result.add buf64
      buf64.marshal(P.y, bigEndian)
      result.add buf64
    else:
      buf64.marshal(P.x.c0, bigEndian)
      result.add buf64
      buf64.marshal(P.x.c1, bigEndian)
      result.add buf64
      buf64.marshal(P.y.c0, bigEndian)
      result.add buf64
      buf64.marshal(P.y.c1, bigEndian)
      result.add buf64

    let k = rng.random_unsafe(BigInt[255])
    buf32.marshal(k, bigEndian)
    result.add buf32

proc benchBls12MsmG1(msmCtx: seq[byte], size, iters: int) =
  var inputs = @(msmCtx.toOpenArray(0, 160*size-1))
  var output = newSeq[byte](128)

  bench(&"BLS12_G1MSM {size:>3}", gasBls12MsmG1(size, gasSchedule["BLS12_G1MUL"]), iters):
    discard output.eth_evm_bls12381_g1msm(inputs)

proc benchBls12MsmG2(msmCtx: seq[byte], size, iters: int) =
  var inputs = @(msmCtx.toOpenArray(0, 288*size-1))
  var output = newSeq[byte](256)

  bench(&"BLS12_G2MSM {size:>3}", gasBls12MsmG2(size, gasSchedule["BLS12_G2MUL"]), iters):
    discard output.eth_evm_bls12381_g2msm(inputs)

# EIP-4844
# -----------------------------------------------------------------------------------------------------

const TrustedSetupMainnet =
  currentSourcePath.rsplit(DirSep, 1)[0] /
  ".." / "constantine" /
  "commitments_setups" /
  "trusted_setup_ethereum_kzg4844_reference.dat"

proc benchKzgPointEvaluation(iters: int) =
  let inputhex = "01e798154708fe7789429634053cbf9f99b619f9f084048927333fce637f549b564c0a11a0f704f4fc3e8acfe0f8245f0ad1347b378fbf96e206da11a5d3630624d25032e67a7e6a4910df5834b8fe70e6bcfeeac0352434196bdf4b2485d5a18f59a8d2a1a625a17f3fea0fe5eb8c896db3764f3185481bc22f91b4aaffcca25f26936857bc3a7c2539ea8ec3a952b7873033e038326e87ed3e1276fd140253fa08e9fc25fb2d9a98527fc22a2c9612fbeafdad446cbc7bcdbdcd780af2c16a"
  var input = newSeq[byte](inputhex.len div 2)
  input.paddedFromHex(inputhex, bigEndian)
  var output = newSeq[byte](64)

  var ctx: ptr EthereumKZGContext
  let status = ctx.trusted_setup_load(TrustedSetupMainnet, kReferenceCKzg4844)
  doAssert status == tsSuccess, "\n[Trusted Setup Error] " & $status

  let opName = "KZG_POINT_EVALUATION"
  bench(opName, gasSchedule[opName], iters):
    discard ctx.eth_evm_kzg_point_evaluation(output, input)

# Main
# -----------------------------------------------------------------------------------------------------

const Iters        =  1000
const ItersPairing =    10
const ItersMsm     =    10
proc main() =
  separator()
  for words in 1..8:
    benchSha256(words, Iters)
  separator()
  for words in 1..8:
    benchKeccak256(words, Iters)
  separator()
  for words in 1..8:
    benchRipeMD160(words, Iters)
  separator()
  benchEcRecover(Iters)
  separator()
  benchBn254G1Add(Iters)
  benchBn254G1Mul(Iters)
  separator()
  let pairingCtxBN = createPairingInputsBN254(8)
  for i in 1..8:
    pairingCtxBN.benchBn254PairingCheck(i, ItersPairing)
  separator()
  benchBls12G1Add(Iters)
  benchBls12G2Add(Iters)
  benchBls12G1Mul(Iters)
  benchBls12G2Mul(Iters)
  benchBls12MapToG1(Iters)
  benchBls12MapToG2(Iters)
  separator()
  let pairingCtxBLS = createPairingInputsBLS12381(8)
  for i in 1..8:
    pairingCtxBLS.benchBls12PairingCheck(i, ItersPairing)
  separator()
  let msmG1Ctx = createMsmInputs(EC_ShortW_Jac[Fp[BLS12_381], G1], 128)
  msmG1Ctx.benchBls12MsmG1(  2, ItersMsm)
  msmG1Ctx.benchBls12MsmG1(  4, ItersMsm)
  msmG1Ctx.benchBls12MsmG1(  8, ItersMsm)
  msmG1Ctx.benchBls12MsmG1( 16, ItersMsm)
  msmG1Ctx.benchBls12MsmG1( 32, ItersMsm)
  msmG1Ctx.benchBls12MsmG1( 64, ItersMsm)
  msmG1Ctx.benchBls12MsmG1(128, ItersMsm)
  separator()
  let msmG2Ctx = createMsmInputs(EC_ShortW_Jac[Fp2[BLS12_381], G2], 128)
  msmG2Ctx.benchBls12MsmG2(  2, ItersMsm)
  msmG2Ctx.benchBls12MsmG2(  4, ItersMsm)
  msmG2Ctx.benchBls12MsmG2(  8, ItersMsm)
  msmG2Ctx.benchBls12MsmG2( 16, ItersMsm)
  msmG2Ctx.benchBls12MsmG2( 32, ItersMsm)
  msmG2Ctx.benchBls12MsmG2( 64, ItersMsm)
  msmG2Ctx.benchBls12MsmG2(128, ItersMsm)
  separator()
  benchKzgPointEvaluation(ItersPairing)
  separator()
main()
notes()
