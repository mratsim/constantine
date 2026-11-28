# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[unittest, strutils, sequtils],
  # Internals
  constantine/hashes

# Squeezing the Keccak sponge
# ------------------------------------------------------------
#
# SHAKE256 is Keccak with a rate of 136 bytes and SHAKE's domain suffix 0x1F:
# the KeccakContext of Keccak-256 and SHA3-256 with another delimiter.
# Its output can have any length, so it checks `squeeze` across block boundaries
# and over successive calls, which must continue the same output stream.
# The squeeze code is shared by every KeccakContext.

type shake256 = KeccakContext[256, 0x1F]

# Reference outputs: the first 700 bytes of SHAKE256 from Python's hashlib (OpenSSL),
#   hashlib.shake_256(message).hexdigest(700)
# for the empty message, "abc", and 300 bytes (i * 7 + 3) mod 256 for i in 0 ..< 300.
# A shorter output is a prefix of a longer one.

const StreamEmpty =
  "46b9dd2b0ba88d13233b3feb743eeb243fcd52ea62b81b82b50c27646ed5762fd75dc4ddd8c0f200cb05019d67b592f6fc821c49479ab48640292eacb3b7c4be" &
  "141e96616fb13957692cc7edd0b45ae3dc07223c8e92937bef84bc0eab862853349ec75546f58fb7c2775c38462c5010d846c185c15111e595522a6bcd16cf86" &
  "f3d122109e3b1fdd943b6aec468a2d621a7c06c6a957c62b54dafc3be87567d677231395f6147293b68ceab7a9e0c58d864e8efde4e1b9a46cbe854713672f5c" &
  "aaae314ed9083dab4b099f8e300f01b8650f1f4b1d8fcf3f3cb53fb8e9eb2ea203bdc970f50ae55428a91f7f53ac266b28419c3778a15fd248d339ede785fb7f" &
  "5a1aaa96d313eacc890936c173cdcd0fab882c45755feb3aed96d477ff96390bf9a66d1368b208e21f7c10d04a3dbd4e360633e5db4b602601c14cea737db3dc" &
  "f722632cc77851cbdde2aaf0a33a07b373445df490cc8fc1e4160ff118378f11f0477de055a81a9eda57a4a2cfb0c83929d310912f729ec6cfa36c6ac6a75837" &
  "143045d791cc85eff5b21932f23861bcf23a52b5da67eaf7baae0f5fb1369db78f3ac45f8c4ac5671d85735cdddb09d2b1e34a1fc066ff4a162cb263d6541274" &
  "ae2fcc865f618abe27c124cd8b074ccd516301b91875824d09958f341ef274bdab0bae316339894304e35877b0c28a9b1fd166c796b9cc258a064a8f57e27f2a" &
  "5b8d548a728c9444ecb879adc19de0c1b8587de3e73e15d3ce2db7c9fa7b58ffc0e87251773faf3e8f3e3cf1d4dfa723afd4da9097cb3c866acbefab2c4e85e1" &
  "918990ff93e0656b5f75b08729c60e6a9d7352b9efd2e33e3d1ba6e6d89edfa671266ece6be7bb5ac948b737e41590abe138ce1869c08680162f08863d174e77" &
  "e07a9ddb33b57de04c443a5bd77c42036871aae7893362b27015b84b4139f0e313579b4ef5f6b6426563d7195b8c5b84736b14266160342c4093f8ab"

const StreamAbc =
  "483366601360a8771c6863080cc4114d8db44530f8f1e1ee4f94ea37e78b5739d5a15bef186a5386c75744c0527e1faa9f8726e462a12a4feb06bd8801e751e4" &
  "1385141204f329979fd3047a13c5657724ada64d2470157b3cdc288620944d78dbcddbd912993f0913f164fb2ce95131a2d09a3e6d51cbfc622720d7a75c6334" &
  "e8a2d7ec71a7cc29cf0ea610eeff1a588290a53000faa79932becec0bd3cd0b33a7e5d397fed1ada9442b99903f4dcfd8559ed3950faf40fe6f3b5d710ed3b67" &
  "7513771af6bfe11934817e8762d9896ba579d88d84ba7aa3cdc7055f6796f195bd9ae788f2f5bb96100d6bbaff7fbc6eea24d4449a2477d172a5507dcc931412" &
  "fc346b1bb39b878330e026b12ddf384af3334560ea1d363966caa7d8ddcbec7da52b42215c11d5f8ee57f341e399343ce63a752fc5edec99124a0eb314403e5f" &
  "358b8b83d05be2d2970099284b00dcc33d7c753d1f752ab743325bc53d91aa671e50f9c3f93abf6e9662f90145c61954f2abbd26edad1553ea3a626f359e8f79" &
  "ade16384e151755c47e822fc74c5d7100fd31f667564c6debc7d20d99e109f22abcbb8c86c0c1146333903422252a5d34a896770b6cb99a1f33935bf87a8e47b" &
  "0549dc2539de9e6a9d1e596111b660cb6b3e0040b4d4916f886dd0b6f1a702849440b99d6088e20203aebafa8e9dffa94ed35ef1f41f5fdf549fbcc5a0f68298" &
  "fa009a54d3a659c3c66542b1e3ecaa0d63e7bcf08d5381f245b2ad6f3f204b965b75df1f86700afeb4406dd95d6b13eff9a7dda552c13ea8a5fe635d3ed1f8d6" &
  "1a91fa78e680d7effa2cfc73a676520e97795e45b66bb624664c7b5522dfd8a1099f147d1f5e2c20477668719ebf073058161d5e7d54fc4fab73dd72881a37b8" &
  "541c9c0c6b3283209c44e10cf0ff604234422a9ccef506c0e83a6111a9712d1701e9ec896b58dd3ff4c8329aa4842f1fef0f45c46cce35954ef16ff9"

const StreamPattern300 =
  "685d9873233fd4c7ce4bb15d7b947c9841f0e5cc18847a4ef07769ccb13022be75ab878b1c49a037276714755b87c8e553c98b24721f93b444598fb0d5826391" &
  "799f3edba2a78d1d14dddf03a74973e32f7d15ea517c05ad1405fc69864dfcfd270edde8250dc92cb8608bd8d91aaf7d8fa25d6f67201923f1e3fc8d5b41e1a3" &
  "2db5401006be32a4f4d3701542419753ff36a95e1d81d5eeca5a62d1ce3989486f7dad2bdb35ce5def3d41b1da995ff0cf776d5c213fd1ebb7901a00916c6bb1" &
  "8fe89774375f939c3e284b7268a66ce0f4e94a3ac1f17273691fdcecb10bb3c7e1c0f896fa5acfd5357e5e6bb0c4af31d18589453e4a1a83a1ecab01323401b2" &
  "c1269070be49c2a49533ac453a9a4d6f465a89388e275de0d2924980f917839584cf0c7953bd50870aa48cf7cb12965ee2deac95bf24a8a3913d86a372fcd876" &
  "4cd896e80f8c734b637ab72e260d127996561cab1897d751d2929ce78ff689fd17805c14b0e1ee2b3f623f3ad8442faa37d8ac045a355fa8ce5453963ef19f27" &
  "34f138133eace37db48b10053a49597706503ffbefd1a64072d96170966ad2dba0f75ce52f35805bef3f6c7bef253b029eeefcf65eb5cee21a951a264d6461a1" &
  "d719ce11b0973b312ac61a87badda095b8478db6de473402a417401dc2abc7bc383558b6447ea27d1bc47804b07dc42efa5234e5df01e0aeec23e4abfa561c72" &
  "a05b7b907be48ac33fa97be35ee50f62aa728293e472b3651ab645d9c951042fb16b7e97896b59835dcdd90a51e0a952fee85d6ebfafdb3ed33b8b040368ac93" &
  "b3340dfafa05763f20be6c2fed3ed87361b9d28927d86cafe4e23a868669f0c3a7171e7c18ab25377334748685695bbdc725fa3b773e8f4d3cd454e89a4b0533" &
  "4cce3595eca2089fabaf9e6baa8de2015558b286c885619412c986f77c278adc8a4e7cef2ed82a0ef48b40dc382c4cbeff0cd2cae34b8e63c0972e24"

func pattern(n: int): seq[byte] =
  for i in 0 ..< n:
    result.add byte((i * 7 + 3) and 0xFF)

func bytesFromHex(hex: string): seq[byte] =
  parseHexStr(hex).mapIt(byte(it))

proc squeezeInPieces(message: openArray[byte], pieces: openArray[int]): seq[byte] =
  ## Absorb `message`, then squeeze pieces.len times, pieces[i] bytes each, and concatenate
  var ctx: shake256
  ctx.init()
  ctx.absorb(message)
  for len in pieces:
    var buf = newSeq[byte](len)
    ctx.squeeze(buf)
    result.add buf

func firstDifference(a, b: openArray[byte]): int =
  ## Index of the first byte that differs, -1 if none
  for i in 0 ..< min(a.len, b.len):
    if a[i] != b[i]:
      return i
  if a.len != b.len:
    return min(a.len, b.len)
  return -1

let messages = [
  ("empty message", newSeq[byte](), bytesFromHex(StreamEmpty)),
  ("\"abc\"", @[byte 'a', byte 'b', byte 'c'], bytesFromHex(StreamAbc)),
  ("300-byte message", pattern(300), bytesFromHex(StreamPattern300))]

let splits = [
  (@[32], "32 bytes, a digest"),
  (@[136], "136 bytes, exactly the rate"),
  (@[136, 64], "136 then 64 bytes, the second call starting a block"),
  (@[272], "272 bytes, exactly two blocks"),
  (@[200], "200 bytes in one call, past the rate"),
  (@[300], "300 bytes in one call, two blocks and a tail"),
  (@[100, 100], "100 then 100 bytes, the second call crossing a block boundary"),
  (@[32, 32, 32], "32 bytes three times, inside one block"),
  (repeat(1, 300), "1 byte 300 times, across two block boundaries"),
  (@[7, 13, 136, 1, 200, 50], "7, 13, 136, 1, 200 and 50 bytes")]

suite "Keccak sponge squeeze, against SHAKE256":
  for (messageName, message, stream) in messages:
    for (pieces, description) in splits:
      test "Squeeze " & description & ", " & messageName:
        let total = foldl(pieces, a + b)
        let got = squeezeInPieces(message, pieces)
        let firstDifferentByte = firstDifference(got, stream[0 ..< total])
        check: firstDifferentByte == -1
