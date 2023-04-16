# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../platforms/[abstractions, views],
  ../math/arithmetic/bigints,
  ../math/arithmetic/[limbs, limbs_extmul],
  ../math/io/io_bigints

when UseASM_X86_64:
  import ../math/arithmetic/assembly/limbs_asm_modular_x86

# No exceptions allowed
{.push raises: [].}

# ############################################################
#
#               Poly1305 Message Authentication Code
#
# ############################################################

# TODO: instead of using a saturated representation,
#       since there is 62 extra bits unused in the last limb
#       use an unsaturated representation and remove all carry dependency chains.
#       Given the number of add with carries, this would significantly
#       improve instruction level parallelism.
#
#       Also vectorizing the code requires removing carry chains anyway.

const P1305 = BigInt[130].fromHex"0x3fffffffffffffffffffffffffffffffb"

func partialReduce_1305[N1, N2: static int](r: var Limbs[N1], a: Limbs[N2]) =
  ## The prime 2¹³⁰-5 has a special form 2ᵐ-c
  ## called "Crandall prime" or Pseudo-Mersenne Prime
  ## in the litterature
  ## which allows fast reduction from the fact that
  ##        2ᵐ-c ≡  0     (mod p)
  ##   <=>  2ᵐ   ≡  c     (mod p)   [1]
  ##   <=> a2ᵐ+b ≡ ac + b (mod p)
  ##
  ## This partially reduces the input in range [0, 2¹³⁰)
  #
  # Assuming 64-bit words,
  #   N1 = 3 words (192-bit necessary for 2¹³⁰-1)
  #   N2 = 4 words (256-bit necessary for 2¹³¹.2¹²⁴)
  # Assuming 32-bit words,
  #   N1 = 5 words (160-bit necessary for 2¹³⁰-1)
  #   N2 = 8 words (288-bit necessary for 2¹³¹.2¹²⁴)
  #
  # from 64-bit, starting from [1]
  #   2ᵐ      ≡  c     (mod p)
  #   2¹³⁰    ≡  5     (mod p)
  # 2¹³⁰.2⁶²  ≡  5.2⁶² (mod p)
  #   2¹⁹²    ≡  5.2⁶² (mod p)
  #
  # Hence if we call a the [2¹⁹², 2²⁶⁰) range
  # and b the [0, 2¹⁹²) range
  # we have
  # a2¹⁹²+b ≡ a.5.2⁶² + b (mod p)
  #
  # Then we can handle the highest word which has
  # 62 bits that should be folded back as well
  #
  # Similarly for 32-bit
  #   2¹⁶⁰    ≡  5.2³⁰ (mod p)
  # and we need to fold back the top 30 bits
  #
  # But there is a twist. 5.2⁶² need 65-bit not 64
  # and 5.2³⁰ need 33-bit not 32

  when WordBitWidth == 64:
    static:
      doAssert N1 == 3
      doAssert N2 == 4

    block:
      # First pass, fold everything greater than 2¹⁹²-1
      # a2¹⁹²+b ≡ a.5.2⁶² + b (mod p)
      #   scale by 5.2⁶¹ first as 5.2⁶² does not fit in 64-bit words
      const c = SecretWord 5
      const cExcess = c shl 61

      var carry: Carry
      var hi, lo: SecretWord
      mul(hi, lo, a[3], cExcess)
      addC(carry, r[0], lo, a[0], Carry(0))
      addC(carry, r[1], hi, a[1], carry)
      addC(carry, r[2], Zero, a[2], carry)
      #   finally double to scale by 5.2⁶²
      addC(carry, r[0], lo, r[0], Carry(0))
      addC(carry, r[1], hi, r[1], carry)
      addC(carry, r[2], Zero, r[2], carry)
  else:
    static:
      doAssert N1 == 5
      doAssert N2 == 8

    block:
      # First pass, fold everything greater than 2¹⁶⁰-1
      # a2¹⁶⁰+b ≡ a.5.2³⁰ + b (mod p)
      #   scale by 5.2²⁹ first as 5.2³⁰ does not fit in 32-bit words
      const c = SecretWord 5
      const cExcess = c shl 29

      staticFor i, 0, N1:
        r[i] = a[i]

      mulDoubleAcc(r[2], r[1], r[0], a[5], cExcess)
      mulDoubleAcc(r[3], r[2], r[1], a[6], cExcess)
      mulDoubleAcc(r[4], r[3], r[2], a[7], cExcess)

  const bits = 130
  const excessBits = wordsRequired(bits)*WordBitWidth - bits

  # Second pass, fold everything greater than 2¹³⁰-1
  # into the lower bits
  var carry, carry2: Carry
  var hi = r[N1-1] shr (WordBitWidth - excessBits)
  r[N1-1] = r[N1-1] and (MaxWord shr excessBits)

  # hi *= 5, with overflow stored in carry
  let hi4 = hi shl 2                   # Cannot overflow as we have 2 spare bits
  addC(carry2, hi, hi, hi4, Carry(0))  # Use the carry bit for storing a 63/31 bit result

  # Process with actual fold
  addC(carry, r[0], r[0], hi, Carry(0))
  addC(carry, r[1], r[1], SecretWord(carry2), carry)
  staticFor i, 2, N1:
    addC(carry, r[i], r[i], Zero, carry)

func finalReduce_1305[N: static int](a: var Limbs[N]) =
  ## Maps an input in redundant representation [0, 2¹³¹-10)
  ## to the canonical representation in [0, 2¹³⁰-5)
  # Algorithm:
  # 1. substract p = 2¹³⁰-5
  # 2. if borrow, add back p.
  when UseASM_X86_64 and a.len <= 6:
    submod_asm(a, a, P1305.limbs, P1305.limbs)
  else:
    let underflowed = SecretBool sub(a, P1305.limbs)
    discard cadd(a, P1305.limbs, underflowed)

const BlockSize = 16

type Poly1305_CTX = object
  acc: BigInt[130+1] # After an unreduced sum, up to 131 bit may be used
  r: BigInt[124]     # r is 124-bit after clamping
  s: BigInt[128]
  buf: array[BlockSize, byte]
  msgLen: uint64
  bufIdx: uint8

type poly1305* = Poly1305_CTX

func macMessageBlocks(
       acc: var BigInt[130+1],
       r: BigInt[124],
       message: openArray[byte],
       blockSize = BlockSize): uint =
  ## Authenticate a message block by block
  ## Poly1305 block size is 16 bytes.
  ## Return the number of bytes processed.
  ##
  ## If hashing one partial block,
  ## set blocksize to the remaining bytes to process

  result = 0
  let numBlocks = int(message.len.uint div BlockSize)
  if numBlocks == 0:
    return 0

  var input {.noInit.}: BigInt[130+1]
  # r is 124-bit after clambing
  var t{.noInit.}: BigInt[130+1+124]

  for curBlock in 0 ..< numBlocks:
    # range [0, 2¹²⁸-1)
    input.unmarshal(
      message.toOpenArray(curBlock*BlockSize, curBlock*BlockSize + BlockSize - 1),
      littleEndian)
    input.setBit(8*blockSize) # range [2¹²⁸, 2¹²⁸+2¹²⁸-1)
    acc += input              # range [2¹²⁸, 2¹³⁰-1+2¹²⁸+2¹²⁸-1)
    t.prod(acc, r)            # range [2²⁵⁶, (2¹²⁴-1)(2¹³⁰+2(2¹²⁸-1)))

    acc.limbs.partialReduce_1305(t.limbs)

  return BlockSize * numBlocks.uint

func macBuffer(ctx: var Poly1305_CTX, blockSize: int) =
  discard ctx.acc.macMessageBlocks(
    ctx.r, ctx.buf, blockSize
  )
  ctx.buf.setZero()
  ctx.bufIdx = 0

# Public API
# ----------------------------------------------------------------

func init*(ctx: var Poly1305_CTX, nonReusedKey: array[32, byte]) =
  ## Initialize Poly1305 MAC (Message Authentication Code) context.
  ## nonReusedKey is an unique not-reused pre-shared key
  ## between the parties that want to authenticate messages between each other
  ctx.acc.setZero()

  const clamp = BigInt[128].fromHex"0x0ffffffc0ffffffc0ffffffc0fffffff"
  ctx.r.unmarshal(nonReusedKey.toOpenArray(0, 15), littleEndian)
  staticFor i, 0, ctx.r.limbs.len:
    ctx.r.limbs[i] = ctx.r.limbs[i] and clamp.limbs[i]

  ctx.s.unmarshal(nonReusedKey.toOpenArray(16, 31), littleEndian)
  ctx.buf.setZero()
  ctx.msgLen = 0
  ctx.bufIdx = 0

func update*(ctx: var Poly1305_CTX, message: openArray[byte]) {.genCharAPI.} =
  ## Append a message to a Poly1305 authentication context.
  ## for incremental Poly1305 computation
  ##
  ## Security note: the tail of your message might be stored
  ## in an internal buffer.
  ## if sensitive content is used, ensure that
  ## `ctx.finish(...)` and `ctx.clear()` are called as soon as possible.
  ## Additionally ensure that the message(s) passed were stored
  ## in memory considered secure for your threat model.

  debug:
    doAssert: 0 <= ctx.bufIdx and ctx.bufIdx.int < ctx.buf.len
    for i in ctx.bufIdx ..< ctx.buf.len:
      doAssert ctx.buf[i] == 0

  if message.len == 0:
    return

  var # Message processing state machine
    cur = 0'u
    bytesLeft = message.len.uint

  ctx.msgLen += bytesLeft

  if ctx.bufIdx != 0: # Previous partial update
    let bufIdx = ctx.bufIdx.uint
    let free = ctx.buf.sizeof().uint - bufIdx

    if free > bytesLeft:
      # Enough free space, store in buffer
      ctx.buf.rawCopy(dStart = bufIdx, message, sStart = 0, len = bytesLeft)
      ctx.bufIdx += bytesLeft.uint8
      return
    else:
      # Fill the buffer and do one Poly1305 MAC
      ctx.buf.rawCopy(dStart = bufIdx, message, sStart = 0, len = free)
      ctx.macBuffer(blockSize = BlockSize)

      # Update message state for further processing
      cur = free
      bytesLeft -= free

  # Process n blocks (16 bytes each)
  let consumed = ctx.acc.macMessageBlocks(
    ctx.r,
    message.toOpenArray(int cur, message.len-1),
    blockSize = BlockSize
  )
  cur += consumed
  bytesLeft -= consumed

  if bytesLeft != 0:
    # Store the tail in buffer
    debug: # TODO: state machine formal verification - https://nim-lang.org/docs/drnim.html
      doAssert ctx.bufIdx == 0
      doAssert cur + bytesLeft == message.len.uint

    ctx.buf.rawCopy(dStart = 0'u, message, sStart = cur, len = bytesLeft)
    ctx.bufIdx = uint8 bytesLeft

func finish*(ctx: var Poly1305_CTX, tag: var array[16, byte]) =
  ## Finalize a Poly1305 authentication
  ## and output an authentication tag to the `tag` buffer
  ##
  ## Security note: this does not clear the internal context.
  ## if sensitive content is used, use "ctx.clear()"
  ## and also make sure that the message(s) passed were stored
  ## in memory considered secure for your threat model.

  debug:
    doAssert: 0 <= ctx.bufIdx and ctx.bufIdx.int < ctx.buf.len
    for i in ctx.bufIdx ..< ctx.buf.len:
      doAssert ctx.buf[i] == 0

  if ctx.bufIdx != 0:
    ctx.macBuffer(blockSize = ctx.bufIdx.int)

  # Input is only partially reduced to [0, 2¹³⁰)
  # Map it to [0, 2¹³⁰-5)
  ctx.acc.limbs.finalReduce_1305()

  # Starting from now, we only care about the 128 least significant bits
  var acc128{.noInit.}: BigInt[128]
  acc128.copyTruncatedFrom(ctx.acc)
  acc128 += ctx.s

  tag.marshal(acc128, littleEndian)

  debug:
    doAssert ctx.bufIdx == 0
    for i in 0 ..< ctx.buf.len:
      doAssert ctx.buf[i] == 0

func clear*(ctx: var Poly1305_CTX) =
  ## Clear the context internal buffers
  # TODO: ensure compiler cannot optimize the code away
  ctx.acc.setZero()
  ctx.r.setZero()
  ctx.s.setZero()
  ctx.buf.setZero()
  ctx.msgLen = 0
  ctx.bufIdx = 0

func mac*(
       _: type poly1305,
       tag: var array[16, byte],
       message: openArray[byte],
       nonReusedKey: array[32, byte],
       clearMem = false) {.genCharAPI.} =
  ## Produce an authentication tag from a message
  ## and a preshared unique non-reused secret key

  var ctx {.noInit.}: poly1305
  ctx.init(nonReusedKey)
  ctx.update(message)
  ctx.finish(tag)

  if clearMem:
    ctx.clear()

func mac*(
       _: type poly1305,
       message: openArray[byte],
       nonReusedKey: array[32, byte],
       clearMem = false): array[16, byte]{.noInit, genCharAPI.}=
  ## Produce an authentication tag from a message
  ## and a preshared unique non-reused secret key
  poly1305.mac(result, message, nonReusedKey, clearMem)
