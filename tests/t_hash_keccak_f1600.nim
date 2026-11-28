# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[unittest, times],
  # Internals
  constantine/hashes,
  constantine/hashes/keccak/keccak_generic,
  constantine/platforms/abstractions,
  constantine/serialization/endians,
  # Helpers
  helpers/prng_unsafe

when UseASM_X86_32:
  import constantine/hashes/keccak/keccak_x86_bmi1

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "t_hash_keccak_f1600 xoshiro512** seed: ", seed
when UseASM_X86_32:
  echo "BMI1 backend tested: ", hasBmi1()

# Reference values
# ------------------------------------------------------------
#
# Computed by `keccak256::keccak_f` of leanVM (https://github.com/leanEthereum/leanVM, crates/keccak256),
# whose state has the same layout: lane x + 5y holds A[x, y].
# The first output is the Keccak team's known answer for the zero state
# (KeccakF-1600-IntermediateValues.txt), which starts with lane 0 = 0xf1258f7940e1dde7.
# The inputs: zero, all ones, a single bit in lanes 0, 1, 5, 24 and in the top bit of lane 12,
# then 8 states from splitmix64 seeded with 0x123456789abcdef0.
# The chain starts from lane i = i * 0x9e3779b97f4a7c15 (mod 2^64).

const Vectors: array[15, tuple[input, output: array[25, uint64]]] = [
  (input: [
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64],
   output: [
      0xf1258f7940e1dde7'u64, 0x84d5ccf933c0478a'u64, 0xd598261ea65aa9ee'u64, 0xbd1547306f80494d'u64, 0x8b284e056253d057'u64,
      0xff97a42d7f8e6fd4'u64, 0x90fee5a0a44647c4'u64, 0x8c5bda0cd6192e76'u64, 0xad30a6f71b19059c'u64, 0x30935ab7d08ffc64'u64,
      0xeb5aa93f2317d635'u64, 0xa9a6e6260d712103'u64, 0x81a57c16dbcf555f'u64, 0x43b831cd0347c826'u64, 0x01f22f1a11a5569f'u64,
      0x05e5635a21d9ae61'u64, 0x64befef28cc970f2'u64, 0x613670957bc46611'u64, 0xb87c5a554fd00ecb'u64, 0x8c3ee88a1ccf32c8'u64,
      0x940c7922ae3a2614'u64, 0x1841f924a2c509e4'u64, 0x16f53526e70465c2'u64, 0x75f644e97f30a13b'u64, 0xeaf1ff7b5ceca249'u64]),
  (input: [
      0xffffffffffffffff'u64, 0xffffffffffffffff'u64, 0xffffffffffffffff'u64, 0xffffffffffffffff'u64, 0xffffffffffffffff'u64,
      0xffffffffffffffff'u64, 0xffffffffffffffff'u64, 0xffffffffffffffff'u64, 0xffffffffffffffff'u64, 0xffffffffffffffff'u64,
      0xffffffffffffffff'u64, 0xffffffffffffffff'u64, 0xffffffffffffffff'u64, 0xffffffffffffffff'u64, 0xffffffffffffffff'u64,
      0xffffffffffffffff'u64, 0xffffffffffffffff'u64, 0xffffffffffffffff'u64, 0xffffffffffffffff'u64, 0xffffffffffffffff'u64,
      0xffffffffffffffff'u64, 0xffffffffffffffff'u64, 0xffffffffffffffff'u64, 0xffffffffffffffff'u64, 0xffffffffffffffff'u64],
   output: [
      0x9f00f21bba6817c4'u64, 0xcdf5aa0d21af5e78'u64, 0xd6539abf24095b97'u64, 0x8bb6f30a010f8228'u64, 0xf0f711ba0547331d'u64,
      0x4f44330558eb182f'u64, 0x2213b79d9055207c'u64, 0xeb5e5b55ca4fb490'u64, 0x0bfaeb81a299b5d4'u64, 0x9e5d924f1a65ed48'u64,
      0x004650c533b7bfb3'u64, 0xddad454b84d7ab05'u64, 0xf03ce56503e82921'u64, 0xce442e92c6728660'u64, 0x1a9ce5e4b37ddcd3'u64,
      0xf63b60e27cea6f0e'u64, 0xcc4cc7fca665bfad'u64, 0x40cf4eba54a2285d'u64, 0x2725f1f142304213'u64, 0x554d327de6fbad9b'u64,
      0x19866a26cbc8bdc2'u64, 0xe8c3c28faf02c7f5'u64, 0xc6bc1f3512a665ae'u64, 0xcaa831f1a5dc86ce'u64, 0x3f82afe91ca4b9b0'u64]),
  (input: [
      0x0000000000000001'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64],
   output: [
      0xe2a944396f0b13c6'u64, 0x70fec06ceb0b06c4'u64, 0x721dfc5018f27a42'u64, 0x64a2af57149f7096'u64, 0xd3bc0b3f2712e2e6'u64,
      0x25b8444d0aea8b74'u64, 0x9396ef8130f1be5c'u64, 0x87a98f12b6ad542c'u64, 0x727078041f4f63f7'u64, 0x92cbec3174d6f74a'u64,
      0x23fbed32ed720767'u64, 0xac2329d693b10d76'u64, 0x493d4a7a941b2026'u64, 0x700069b797e2f86c'u64, 0x95d8e3aee6fc4b8c'u64,
      0x0bca1b8d9d0d82fc'u64, 0xe2ad33926d474c63'u64, 0x6a5415a4ebed8dfe'u64, 0xed6a86e4fecbac62'u64, 0xd86e73c1b945a137'u64,
      0x333256c252840104'u64, 0x9f111faa6a08d2e5'u64, 0x6d1f6a874f916feb'u64, 0xf716ae69d3a57f06'u64, 0xf5a843755d5374af'u64]),
  (input: [
      0x0000000000000000'u64, 0x0000000000000001'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64],
   output: [
      0xfdbbbbdf9001405f'u64, 0x248d44cfc37d1048'u64, 0xc57ff1f34c2c45aa'u64, 0x48a647926052397e'u64, 0xf32988e7542db934'u64,
      0xedd9e1dfb66ac13d'u64, 0x5680db1c9d45f25c'u64, 0x5c136d22769d2796'u64, 0x6da87b7ad69e1344'u64, 0xc3ad97a19b6d1541'u64,
      0x0747ba9e452c7955'u64, 0xc7352bf02826637f'u64, 0xef9732021e02c5e1'u64, 0x95b470bacfa87966'u64, 0x091c15aba90903e7'u64,
      0xe0158e550cb6dd1b'u64, 0xf704acb402fdd54e'u64, 0x55b685e488430784'u64, 0x781870fa88e4032b'u64, 0x26fef7fdb75ceb61'u64,
      0xa830979826e3a3da'u64, 0xdc3f22dac62f88ce'u64, 0x3ddf22941ef98d31'u64, 0x3e10eff7b9318f6e'u64, 0xeac9f006664deb35'u64]),
  (input: [
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000001'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64],
   output: [
      0x92f05536ecf5826b'u64, 0x16fa699c4c255780'u64, 0xcf4e48048f9ea41a'u64, 0x5ceabab984f95a9f'u64, 0xb57cbefea15a7caf'u64,
      0xb997abc0ba38c90d'u64, 0xfef97aabc2b2876c'u64, 0xadd57d81d50e60e3'u64, 0x2f53224df40207b3'u64, 0xf0a9212af140d820'u64,
      0xffa6b279efca4c93'u64, 0x327d0a3f5508b6cd'u64, 0xcc4213ead8992a64'u64, 0xb8b5f748fa46c278'u64, 0xffa0769df8d079f2'u64,
      0x800fd6728a541ae5'u64, 0xeba4f8a91cdb7a19'u64, 0x725bbec1c38016ed'u64, 0x4e1dcbf0f9a918ec'u64, 0x425d70aa415bbdc1'u64,
      0x2c42824d9b16afed'u64, 0xe226286e130beab7'u64, 0x021fa400d39ac621'u64, 0xbf74679b99f73ce4'u64, 0x919124848d5ef3c7'u64]),
  (input: [
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000001'u64],
   output: [
      0x4a064b7ecd0ecac2'u64, 0xc7d89fa0f8b1bd3b'u64, 0x3874f223c00e0969'u64, 0xa2a2c8080dfc67c2'u64, 0x69b0e422c922466c'u64,
      0x5714bbcdd03ba74f'u64, 0xff99d99d044e5603'u64, 0xb775c5551b4e89a4'u64, 0x3312daf81be51849'u64, 0x2e72acb751447af2'u64,
      0x10add8aa25a4ee13'u64, 0xf45e2d6360664074'u64, 0x4e79f600279d2705'u64, 0x6d89c71a421e4efa'u64, 0x86b931f8e5f8cfbe'u64,
      0x56b33ef44f0defba'u64, 0x00c6bcd4033d1910'u64, 0x86f621d0ec9cc3f2'u64, 0x9979d2903fedb41a'u64, 0xc2380162c94c5596'u64,
      0x11ba15eef29c7409'u64, 0xd78bc415fc2a1f62'u64, 0x2120a52a8cbe4dc9'u64, 0x6ddccf154dd55c03'u64, 0xc992c0689c835d7d'u64]),
  (input: [
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x8000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64],
   output: [
      0xc109160257b542de'u64, 0x38e1ad00785209da'u64, 0xa2aeb712c4791ef3'u64, 0x90742454b5483340'u64, 0x3fd7dfb674bfe6a5'u64,
      0xcbdb26d4935891b7'u64, 0x5328e58eb8268eb6'u64, 0x76d2d2dc49ef8b68'u64, 0x4fd58d6d2cccea27'u64, 0xbe3aeb83d2e41d14'u64,
      0x7d24014e4a98acc3'u64, 0x13fcd2d8ee7934a7'u64, 0x6a58cc0e24f19d35'u64, 0xd53a59f06c29effa'u64, 0xe942865aafdce685'u64,
      0x8b7e56305f96af6f'u64, 0xe11b0aed3e3249f9'u64, 0x5e743587072f1b85'u64, 0x07f5e76de170182d'u64, 0x0fed4a6e9294aa4c'u64,
      0xc4e97ad3f89c8b3c'u64, 0xb813b9c57b180cd5'u64, 0x9c911d1d970e437c'u64, 0x77a90aa9a6315f06'u64, 0x60707be280a99089'u64]),
  (input: [
      0x161922c645ce50e8'u64, 0xad760cafa1697b60'u64, 0x3501ff44902ca50d'u64, 0x417cb9a826d831df'u64, 0x99af6f9b0c4476b6'u64,
      0x5d51f5f75b762c59'u64, 0x66239e8c309a282b'u64, 0x53e01f580916c5cb'u64, 0xaa941016a4c2958b'u64, 0x279993774594e137'u64,
      0x20e9a7a844bdacc0'u64, 0x90ec693596cc8ab0'u64, 0x4d7760d307367afa'u64, 0x4315096655b77a33'u64, 0x0e907aa9d946b562'u64,
      0x1947cecfc10e24f3'u64, 0x8a27bdf7c4b88166'u64, 0x3989c8272f2ae095'u64, 0xb7dc9a7f27f0b595'u64, 0xa0f6c1d2ed13c145'u64,
      0xc54ad38a1e595bce'u64, 0xd87e930b7f41a756'u64, 0x87ead6b5c67ec06b'u64, 0xa4353faba48b2382'u64, 0x19a42fc02250ff9d'u64],
   output: [
      0x2d56a53f136fbaf5'u64, 0x56e30dafb1e37b2b'u64, 0x3e02dfb8f88793e5'u64, 0xa04e5245f9a9a979'u64, 0x149586c88d74ccc4'u64,
      0x75099e39b1039a31'u64, 0x0efe3b51010875bf'u64, 0x18fab4a5259834ee'u64, 0x545d8b64454684ed'u64, 0x1ef9e738a50b9ff3'u64,
      0xb08a72a70b206bcd'u64, 0xb5e3ca33f3fe5379'u64, 0x3f56c791b391d81e'u64, 0x96a2123e1e15fe6e'u64, 0x8943c09ada35879f'u64,
      0x19780a135a8d5f99'u64, 0x218ecfa3ffdab64a'u64, 0x357c7a20b4f06d77'u64, 0xcb06cf1caac8484f'u64, 0x9eccc8dc1d45601c'u64,
      0xd748d06340a0dd33'u64, 0xca1ac2e636959664'u64, 0x0b7c4b94a9eb82d7'u64, 0xebc3da20650b0e85'u64, 0x822e6ac05e0cfcfd'u64]),
  (input: [
      0x5baeac52832826b1'u64, 0x862b3e793173997b'u64, 0x60ba89bb02987253'u64, 0xd51b395c4f12bd9a'u64, 0x0bc7804037d52ade'u64,
      0x42252510d604c41f'u64, 0x29f45920a9f57c95'u64, 0xa93b6ea467675dbc'u64, 0x15c3aaabd5956aec'u64, 0xa5daabf7c364c8e5'u64,
      0xd094cf38e10d9faa'u64, 0xad06e37401370752'u64, 0xcdb61e7bd233a525'u64, 0x0a4ba189d018c8d3'u64, 0x50b327159db36439'u64,
      0x82a6283919ae345e'u64, 0xcbe4fec009a705bc'u64, 0x00140bc367f632b3'u64, 0xc01390dfaf502656'u64, 0xe4a211a9598495bf'u64,
      0x2de60a74ac7442e6'u64, 0x7c80a5d8393d87dc'u64, 0x0042f9e8ad284fd5'u64, 0x1e86ae8dae777e7b'u64, 0x056b110d49d7a50e'u64],
   output: [
      0xc2be845840bbe438'u64, 0xc91faad532d3c512'u64, 0x5cf3b550b635f49d'u64, 0xc4ae669130cd0bcd'u64, 0xcc659670c68aaec4'u64,
      0x2e8643b257d2fe70'u64, 0xccc1963959920fea'u64, 0x758bac5920cac888'u64, 0xa60174466b7193b8'u64, 0xf970d390ed6e89eb'u64,
      0xb10704352a15712a'u64, 0xfd72aecec32a37fa'u64, 0x626e5079a91bb8d5'u64, 0x65e5e7b4ce4ddf66'u64, 0x27390622a263c8b8'u64,
      0x135b9d5473c9e86c'u64, 0x1bcc98b913ca011f'u64, 0xe4b45de10a0a1175'u64, 0xaae0181b567c096a'u64, 0x08ef6ce6ce2660db'u64,
      0x519b8e68d7db03dc'u64, 0x65e40b482aebd803'u64, 0x267cdd2135b5a7bf'u64, 0xcce316be6c19e66a'u64, 0xb614fc3210228b69'u64]),
  (input: [
      0x0cb3ea3f164075ae'u64, 0x810c2241d09be6d9'u64, 0x8c3e2645b1f287d0'u64, 0xd1e311a47f9cd5f8'u64, 0xce8d06c14b42138d'u64,
      0xf655d4c61563800d'u64, 0x2b83b4facee21349'u64, 0xff5070d67c85f362'u64, 0xfff81fe0b509fd83'u64, 0x26584fd1187d611c'u64,
      0xa339def8905cc9b6'u64, 0x062d2657944baf3c'u64, 0x53395a748d962c4b'u64, 0xadfc499f2a938342'u64, 0x7ea69ed006af8bd7'u64,
      0x8a2d3e828f6d3ae5'u64, 0x32fb0973d630265d'u64, 0x4051fe43c4b522ae'u64, 0x082c3a7ac6f2b2da'u64, 0x0c3a17d99df22145'u64,
      0xf6445251c28d637b'u64, 0x9975c19cf44affdb'u64, 0xb35f858bd5a4c400'u64, 0x698f51eb4b966aa9'u64, 0x825a83fad5f42f53'u64],
   output: [
      0xaf70723f01efe4c2'u64, 0xe0c4d31a28d36a2e'u64, 0xfc26848f1bc0869a'u64, 0x60c149d6f48e6b64'u64, 0xff49c11c384a746a'u64,
      0xc32f6347a9a9c520'u64, 0x7ed0c45fa69be807'u64, 0x4631462a2af2e51e'u64, 0xbc30c7e1b2f8da8c'u64, 0xe3ca429ba9690714'u64,
      0x5ea7c97b839e6e86'u64, 0x0b109f2c113a3708'u64, 0x0d8c24193d0bc85b'u64, 0x8c9389bedf549b35'u64, 0x3c29b7c12ae0dcf3'u64,
      0x856d646d39b65593'u64, 0xdbac405158d4716d'u64, 0xf1ba27bf0c512de5'u64, 0xe72f52ca12df67f4'u64, 0x96894c90ce4b29ed'u64,
      0xda43272b890c41c9'u64, 0x86cdbe25dee7e4c3'u64, 0xc70d854bfcd4258e'u64, 0x779ef28a4ab5c2d1'u64, 0x84d3657e755486d3'u64]),
  (input: [
      0xb1a1c87a8e370a11'u64, 0xdd78e2d4f2beffbc'u64, 0xde74c9244ae698f4'u64, 0x853315df4f1b7c7a'u64, 0x5953cf89da9626e9'u64,
      0x7ef1aff252b419a7'u64, 0x0d7c263366fa669e'u64, 0x8576aac3174e2232'u64, 0x9c20825cd0a0e128'u64, 0x922a277c96f9a79e'u64,
      0x66fe071aa89214d5'u64, 0x28e26d7561f3016d'u64, 0x08bb2d9d88ba3be2'u64, 0xb1b00e7b7dd5f20c'u64, 0x5c5b6b824c2705ae'u64,
      0x9f6535d60528fb6c'u64, 0x50ab140e38a246c6'u64, 0x993b4bf586e84635'u64, 0x44dfc222af3ef96d'u64, 0xaab7732237af2bca'u64,
      0xde089459f29e2aaf'u64, 0xeb399ec3f5faa893'u64, 0x86bc73b51214aefb'u64, 0x3235a8d4e6b2b330'u64, 0x6c98d4263aa01342'u64],
   output: [
      0xcb9eba11ccb90dfd'u64, 0x528a68b9ddb8e835'u64, 0x6176eb6a0f3cd6ca'u64, 0x5bac3f8205e80257'u64, 0x258e80c9dead745f'u64,
      0x805ba1dbec599eb8'u64, 0x23d375b3bbce1479'u64, 0x25e2f167c210d8e3'u64, 0x65d5a97c5801adb0'u64, 0xa5742c403b346f0e'u64,
      0xb6bd2e20982f2882'u64, 0xde92841116f0c917'u64, 0x23e61e5e8d08b408'u64, 0x3a2085c8270de317'u64, 0x96de162b920d8fe6'u64,
      0xd9c32b5b9623bcc2'u64, 0xdad152a4d48f8c24'u64, 0x2a0d2196a116181c'u64, 0x81cc3e2323ce4ce7'u64, 0xbdeb2f869ed05e7b'u64,
      0x9e5ef3d27fc4efdf'u64, 0xc28b1ea0876f3b0b'u64, 0x38c9261e36f4c4c6'u64, 0x1e0d577105d9b0d5'u64, 0x9279ca7b9759c0a3'u64]),
  (input: [
      0xeba2c848fbf2f151'u64, 0xf0617b36bdef52f8'u64, 0x7359334c5cc1d837'u64, 0xca488d0a3e805164'u64, 0x557edcf42586aa06'u64,
      0x831a3dbf422ebdb6'u64, 0x0b7183f2af6defc7'u64, 0x3ca78d39e1a1a93d'u64, 0x7d96c744610c034e'u64, 0xaf43c1f572b365d4'u64,
      0xa0a90b7e6688faaa'u64, 0x1dd7168c3a6b4c74'u64, 0x08426523307a1662'u64, 0xebe9adef78634e13'u64, 0x7da4310ddc823b8b'u64,
      0xda579bf86fae8b5a'u64, 0xf653a134a4c747dc'u64, 0xbc5486addab05206'u64, 0x91d48852d77f8c1c'u64, 0xffdc36128b720421'u64,
      0x696576be9bd2f14c'u64, 0x36c0ffbedd4bdf79'u64, 0x0d80d05b8e4fdf8f'u64, 0x8be7b9e56060c921'u64, 0xfc5eaa037b74faa7'u64],
   output: [
      0x05a85ef787925611'u64, 0xd305f9fe67bd96c9'u64, 0x30ae8ac4d43a199a'u64, 0x86b5f87532ebc700'u64, 0x86af623dc80db158'u64,
      0x9e49db33a11bd063'u64, 0x9908c2e9108d7c43'u64, 0xa6b2f84e3374f239'u64, 0xbcb6848f96e35de6'u64, 0xe9c2c32cd7000219'u64,
      0x25b7f3bbca08ef06'u64, 0xf5cd0aaa8a1d9700'u64, 0x03465ba5f6bec3a2'u64, 0x63ae4ba7005582cb'u64, 0x021e6098a967f5aa'u64,
      0x3fcca1f527fa56d7'u64, 0x8ca98b0ba6f60fd1'u64, 0xff0d0cd53282e31d'u64, 0xa3a24db62b893475'u64, 0xac8b3909ecf6ba36'u64,
      0x3e46ba66880516cc'u64, 0x2dbaa980aec3eb27'u64, 0xb6224b6e6ea8cbd7'u64, 0xb4dc063579d4d1e5'u64, 0xc302bcda779815cf'u64]),
  (input: [
      0xb6a9c94f46d601ad'u64, 0x203f082946b4a0f6'u64, 0x8e059f98e9c6069b'u64, 0xd5b54bd28a19acb8'u64, 0xb343dd5a78f8b450'u64,
      0x36079f11691ee4bb'u64, 0xc49f5fbdc6610839'u64, 0x31338b7fde79ca2e'u64, 0x22668f106ff6bff1'u64, 0x717be48a0921e6a4'u64,
      0xd3005c7d06b347a7'u64, 0x88adcba352c0aa12'u64, 0x0d727f23d654948c'u64, 0x8da856c2fa827fe8'u64, 0x7826fc59ddbbc97f'u64,
      0x25557d00e33333dd'u64, 0x6033aff71ebbe4ec'u64, 0x1c1c81bb063415a8'u64, 0x2ba93ba66ce2f230'u64, 0x33b8ba7d7c707a7c'u64,
      0x7fafa11db8782f26'u64, 0x24223fa0d0736b12'u64, 0xa90e63b82c2f481e'u64, 0x5a6b12258c9920b5'u64, 0xff2304eede1531e4'u64],
   output: [
      0x5a61c248810e7029'u64, 0xb8b7b05a353dccc1'u64, 0xe622df575a39570a'u64, 0xfd96b82023fb394c'u64, 0x1f3d15f220526801'u64,
      0x37250d6d8ea67447'u64, 0x43ee85e21e004a30'u64, 0xfac3986951357998'u64, 0xa30fd3eaac5f356f'u64, 0x966c0e4af9848815'u64,
      0x57b942e9b6348c89'u64, 0xc80958eb0c2c3293'u64, 0x27e5793fbe0b2424'u64, 0x66af4ef284b5d455'u64, 0x865d7a59f0f7c58d'u64,
      0x12be492ba8b0c069'u64, 0x923a6fe94e5cf730'u64, 0x038174e885175711'u64, 0xa7c6f684a170e43a'u64, 0xdada7f2358e71227'u64,
      0xb9b708592bcdd5ce'u64, 0x7962269449f8c9e8'u64, 0x04c03353e48ac38f'u64, 0x66affbc43331c6a2'u64, 0x1e78131731a8bbd3'u64]),
  (input: [
      0x84fe097fde1d8469'u64, 0xc8992dce1397403b'u64, 0x4846e5ee33ac3fb2'u64, 0x8404322637000bbc'u64, 0x09d6006a1a5525d6'u64,
      0xd605db240dd49e26'u64, 0xcf13d9c29bc3e6c6'u64, 0xdc5339ee61466f5e'u64, 0x76de1c04fbd26e72'u64, 0xd285febfe53ee592'u64,
      0xed8852011245ba89'u64, 0xa34dae9383e4fed1'u64, 0x3ce937eddc675df6'u64, 0x6c0eced66a6f703f'u64, 0xb99df75e3eb2de36'u64,
      0x482b5a5739286e35'u64, 0x12471e12223f1d69'u64, 0x9a195b06398c4375'u64, 0x601b91de3551443f'u64, 0xe207c680ddfca9d8'u64,
      0xbdde1dd799d22472'u64, 0x1365ae8c8e0463e3'u64, 0xbbbf5c35a8301ca6'u64, 0xddbfa7323a79e77a'u64, 0x975795d03753999b'u64],
   output: [
      0x9d45f1e689a4eb45'u64, 0xf4ea57a97ef3b0bb'u64, 0x62b2dab356389a97'u64, 0xe72c2d27e26bc2ac'u64, 0x47560b9c750d786f'u64,
      0xb77a0ddecd0c83aa'u64, 0x84c6c3fc6875bbbd'u64, 0xc78fcadc4f9e81f9'u64, 0xfb097ba801f8a3cd'u64, 0x017c7fbeb6337aa1'u64,
      0xe2f1b79e2a21489b'u64, 0xdd22c261806c17e4'u64, 0xdc86f3d3cc129037'u64, 0x6314a697ca6566a6'u64, 0xb5833e4d7e04db6b'u64,
      0x11cd23a1bf40977c'u64, 0xa049620f9e68617f'u64, 0x0f67b065eb3efba5'u64, 0x26e9edbc31727dbb'u64, 0xf506a9bf67142a7e'u64,
      0x3b33b36d5366011f'u64, 0xa12fac49f61618e0'u64, 0xc08313304b470fae'u64, 0x2dde7f4c5c62b4a0'u64, 0xb60d074e3359e5e4'u64]),
  (input: [
      0xb42d170f98a37694'u64, 0x873cca3f004fa35f'u64, 0x6426be49467ad445'u64, 0x82f3f34340c65372'u64, 0xeaac60cf55373f10'u64,
      0x7d8bc4a13793ef8f'u64, 0x36be91bdba01424a'u64, 0xe224abb895d92ef4'u64, 0x24a827201fffecaa'u64, 0xc60f8957d003e7e3'u64,
      0xa2dce8feed8ef8d3'u64, 0x02d8a2c1da0325a3'u64, 0xa3d3a8c5fccee46a'u64, 0x47d0d7c1880bd7f0'u64, 0xaa24c34dfd59d363'u64,
      0xb47a9cb39d5b1e88'u64, 0xd043e700aaddc81e'u64, 0xf4382b6a43edb55e'u64, 0x371b1d53c01b8623'u64, 0x42ee771782290d54'u64,
      0xfe8adc45ee9674e1'u64, 0x275ebd3de2960fae'u64, 0x6f5393514f0c4205'u64, 0x18de42fbf438dddb'u64, 0x15ee1b0bac1032ed'u64],
   output: [
      0xdf854c26c8e3d4a8'u64, 0x98dedd6513324368'u64, 0xb066be1e95615ae7'u64, 0x4d3c07d3b0d4ca9f'u64, 0x4265636c691af12b'u64,
      0xb2ac7cbb8a89aecc'u64, 0x0b8f8c9c46b92090'u64, 0x67b5e9ad5d251cde'u64, 0xcad6fb7c1ea49779'u64, 0x92227ca01d2ce0fd'u64,
      0xe24d444797006c35'u64, 0xff874c1c7bb1aec8'u64, 0x100dc88163c47c24'u64, 0x3b210ecf11b0b570'u64, 0x3466ede84538a7f7'u64,
      0xdf3d84cba13af49c'u64, 0x73f616448862d868'u64, 0x6781538ffd8ee2d1'u64, 0x1a4e64a2680150a6'u64, 0xb9036eb49757d3aa'u64,
      0xc7ba452c5035650d'u64, 0x82ef793e7347a5aa'u64, 0xfc6b5cdb1b37136e'u64, 0x817601781f358223'u64, 0x120e98299a6ea5be'u64]),
]
const ChainStart: array[25, uint64] = [
  0x0000000000000000'u64, 0x9e3779b97f4a7c15'u64, 0x3c6ef372fe94f82a'u64, 0xdaa66d2c7ddf743f'u64, 0x78dde6e5fd29f054'u64,
  0x1715609f7c746c69'u64, 0xb54cda58fbbee87e'u64, 0x538454127b096493'u64, 0xf1bbcdcbfa53e0a8'u64, 0x8ff34785799e5cbd'u64,
  0x2e2ac13ef8e8d8d2'u64, 0xcc623af8783354e7'u64, 0x6a99b4b1f77dd0fc'u64, 0x08d12e6b76c84d11'u64, 0xa708a824f612c926'u64,
  0x454021de755d453b'u64, 0xe3779b97f4a7c150'u64, 0x81af155173f23d65'u64, 0x1fe68f0af33cb97a'u64, 0xbe1e08c47287358f'u64,
  0x5c55827df1d1b1a4'u64, 0xfa8cfc37711c2db9'u64, 0x98c475f0f066a9ce'u64, 0x36fbefaa6fb125e3'u64, 0xd5336963eefba1f8'u64]
const ChainLength = 100000
const ChainEnd: array[25, uint64] = [
  0xd4e92f9b4ff0d71c'u64, 0x0cbe23815dc89a60'u64, 0x0972eba3fe2ba0e7'u64, 0x8ae79a138982e02a'u64, 0x49b6795909401872'u64,
  0x908a1fe1defbcd5c'u64, 0xba637a54bbc3e086'u64, 0x8ea1f0183cce4afa'u64, 0xb6424e894b7cc0c6'u64, 0x7ee94c4855b0560c'u64,
  0x7a65f3eb33a6243a'u64, 0x785264319bb2a7ae'u64, 0xed6a5fca78460c7a'u64, 0x02cd186714668170'u64, 0xf1def0d677215f03'u64,
  0xb49bea1ec3075647'u64, 0xd889d85ae0eeb95e'u64, 0x32b87baae6340dc4'u64, 0xa083dd06d8953480'u64, 0x1d79007520e3fc1d'u64,
  0xfb0bb63bf817d795'u64, 0xf778519d80acb415'u64, 0x06ef076145c119c5'u64, 0xf5e512d2c499e9d3'u64, 0xaf506e51d1e2c495'u64]

# Transcription of FIPS 202 §3.2
# ------------------------------------------------------------
#
# The step mappings as the specification writes them, A[x, y] indexed by coordinates,
# with the round constants from the LFSR of Algorithm 5 and the ρ offsets from Algorithm 2,
# so none of the tables or tricks of the implementation under test.

func rc(t: int): uint64 =
  ## FIPS 202 Algorithm 5: bit rc(t) of the LFSR, R[i] in bit i
  if t mod 255 == 0:
    return 1
  var r = 1'u64 # R = 10000000
  for _ in 1 .. t mod 255:
    r = r shl 1
    let r8 = (r shr 8) and 1
    r = r xor (r8 shl 0) xor (r8 shl 4) xor (r8 shl 5) xor (r8 shl 6)
    r = r and 0xFF
  return r and 1

func roundConstant(ir: int): uint64 =
  ## FIPS 202 Algorithm 6, step 3: RC[2^j - 1] = rc(j + 7·ir) for j in 0 .. 6
  for j in 0 .. 6:
    result = result or (rc(j + 7*ir) shl ((1 shl j) - 1))

func rhoOffsets(): array[5, array[5, int]] =
  ## FIPS 202 Algorithm 2, indexed [x][y]
  var (x, y) = (1, 0)
  for t in 0 .. 23:
    result[x][y] = ((t+1)*(t+2) div 2) mod 64
    (x, y) = (y, (2*x + 3*y) mod 5)

func rotl(v: uint64, n: int): uint64 =
  if n == 0: v else: (v shl n) or (v shr (64 - n))

func keccak_f1600_reference(lanes: var array[25, uint64]) =
  const rho = rhoOffsets()
  var A: array[5, array[5, uint64]] # A[x][y]
  for x in 0 ..< 5:
    for y in 0 ..< 5:
      A[x][y] = lanes[x + 5*y]

  for ir in 0 ..< 24:
    # θ
    var C, D: array[5, uint64]
    for x in 0 ..< 5:
      C[x] = A[x][0] xor A[x][1] xor A[x][2] xor A[x][3] xor A[x][4]
    for x in 0 ..< 5:
      D[x] = C[(x + 4) mod 5] xor rotl(C[(x + 1) mod 5], 1)
    for x in 0 ..< 5:
      for y in 0 ..< 5:
        A[x][y] = A[x][y] xor D[x]
    # ρ
    for x in 0 ..< 5:
      for y in 0 ..< 5:
        A[x][y] = rotl(A[x][y], rho[x][y])
    # π: A'[x, y] = A[(x + 3y) mod 5, x]
    var P: array[5, array[5, uint64]]
    for x in 0 ..< 5:
      for y in 0 ..< 5:
        P[x][y] = A[(x + 3*y) mod 5][x]
    # χ
    for x in 0 ..< 5:
      for y in 0 ..< 5:
        A[x][y] = P[x][y] xor ((not P[(x + 1) mod 5][y]) and P[(x + 2) mod 5][y])
    # ι
    A[0][0] = A[0][0] xor roundConstant(ir)

  for x in 0 ..< 5:
    for y in 0 ..< 5:
      lanes[x + 5*y] = A[x][y]

proc keccak256_onPermutation(msg: openArray[byte]): array[32, byte] =
  ## Keccak-256 written directly on keccak_f1600:
  ## rate 136 bytes, padding 0x01 ‖ 0* ‖ 0x80, little-endian lanes
  const Rate = 136
  var padded = @msg
  padded.setLen(msg.len - msg.len mod Rate + Rate)
  padded[msg.len] = padded[msg.len] xor 0x01
  padded[^1] = padded[^1] xor 0x80

  var state: array[25, uint64]
  for blk in 0 ..< padded.len div Rate:
    for i in 0 ..< Rate div 8:
      state[i] = state[i] xor uint64.fromBytes(padded, blk*Rate + 8*i, littleEndian)
    keccak_f1600(state)
  for i in 0 ..< 4:
    result.dumpRawInt(state[i], 8*i, littleEndian)

template checkEveryBackend(input, expected: array[25, uint64]) =
  ## The public entry point and each backend it dispatches to
  block:
    var s = input
    keccak_f1600(s)
    check: s == expected
  block:
    var s = input
    s.permute_generic(NumRounds = 24)
    check: s == expected
  when UseASM_X86_32:
    if hasBmi1():
      var s = input
      s.permute_x86_bmi1(NumRounds = 24)
      check: s == expected

# Tests
# ------------------------------------------------------------

suite "Keccak-f[1600] permutation on 25 lanes" & " [" & $WordBitWidth & "-bit words]":
  test "Matches leanVM's keccak256::keccak_f, every backend":
    for (input, output) in Vectors:
      checkEveryBackend(input, output)

  test "100000 chained permutations match leanVM's":
    var s = ChainStart
    for _ in 0 ..< ChainLength:
      keccak_f1600(s)
    check: s == ChainEnd

  test "The FIPS 202 transcription reproduces leanVM's values":
    # Validates the reference used on random states below
    for (input, output) in Vectors:
      var s = input
      s.keccak_f1600_reference()
      check: s == output

  test "Matches the FIPS 202 transcription on random states, every backend":
    for _ in 0 ..< 1000:
      var input: array[25, uint64]
      for lane in input.mitems:
        lane = rng.next()
      var expected = input
      expected.keccak_f1600_reference()
      checkEveryBackend(input, expected)

  test "Keccak-256 written on the permutation matches keccak256.hash":
    # Ties the lane layout and byte order to the tested hash,
    # on both sides of every block boundary up to 5 blocks
    for len in 0 .. 700:
      let msg = rng.random_byte_seq(len)
      var digest: array[32, byte]
      keccak256.hash(digest, msg)
      check: keccak256_onPermutation(msg) == digest
    for len in [1023, 1024, 1025, 4096]:
      let msg = rng.random_byte_seq(len)
      var digest: array[32, byte]
      keccak256.hash(digest, msg)
      check: keccak256_onPermutation(msg) == digest

  test "Lanes need no particular alignment":
    var buffer {.align: 64.}: array[26, uint64]
    let lanes = cast[ptr array[25, uint64]](buffer[1].addr) # 8-byte aligned, not 16
    lanes[] = Vectors[^1].input
    keccak_f1600(lanes[])
    check:
      lanes[] == Vectors[^1].output
      buffer[0] == 0
