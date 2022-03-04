# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../platforms/abstractions,
  ../math/arithmetic/bigints,
  ../math/arithmetic/limbs_extmul,
  ../math/arithmetic/assembly/limbs_asm_modular_x86,
  ../math/io/io_bigints


import # debug
  ../math/arithmetic/[limbs_division, limbs],
  ../math/config/type_bigint

# ############################################################
#
#               Poly1305 Message Authentication Code
#
# ############################################################

const P1305 = BigInt[130].fromHex"0x3fffffffffffffffffffffffffffffffb"

# # TODO: fast reduction
# func partialReduce_1305[N1, N2: static int](r: var Limbs[N1], a: Limbs[N2]) =
#   ## The prime 2¹³⁰-5 has a special form 2ᵐ-c
#   ## called "Crandall prime" or Pseudo-Mersenne Prime
#   ## in the litterature
#   ## which allows fast reduction from the fact that
#   ##        2ᵐ-c ≡  0     (mod p)
#   ##   <=>  2ᵐ   ≡  c     (mod p)   [1]
#   ##   <=> a2ᵐ+b ≡ ac + b (mod p)
#   ## 
#   ## This partially reduces the input in range [0, 2¹³⁰)
#   ##
#   ## Assuming 64-bit words,
#   ##   N1 = 3 words (192-bit necessary for 2¹³⁰-5)
#   ##   N2 = 5 words (320-bit necessary for 2²⁶⁰-5*2¹³⁰+25)
#   ## Assuming 32-bit words,
#   ##   N1 = 5 words (160-bit necessary for 2¹³⁰-5)
#   ##   N2 = 9 words (288-bit necessary for 2²⁶⁰-5*2¹³⁰+25)
#   ## 
#   ## from 64-bit, starting from [1]
#   ##   2ᵐ      ≡  c     (mod p)
#   ##   2¹³⁰    ≡  5     (mod p)
#   ## 2¹³⁰.2⁶²  ≡  5.2⁶² (mod p)
#   ##   2¹⁹²    ≡  5.2⁶² (mod p)
#   ## 
#   ## Hence if we call a the [2¹⁹², 2²⁶⁰) range
#   ## and b the [0, 2¹⁹²) range
#   ## we have
#   ## a2¹⁹²+b ≡ a.5.2⁶² + b (mod p)
#   ## 
#   ## Then we can handle the highest word which has
#   ## 62 bits that should be folded back as well
#   ## 
#   ## Similarly for 32-bit
#   ##   2¹⁶⁰    ≡  5.2³⁰ (mod p)
#   ## and we need to fold back the top 30 bits
#   const bits = 130
#   const c = SecretWord 5
#   const excessBits = wordsRequired(bits)*WordBitWidth - bits
#   const cExcess = c shl excessBits # Unfortunately on 64-bit 5.2⁶² requires 65-bit :/ 

#   static: doAssert excessBits == 62

#   r.setZero() # debug
#   var hi: SecretWord

#   # First reduction pass, fold everything greater than 2¹⁹² (or 2¹⁶⁰)
#   # into the lower bits
#   muladd1(hi, r[0], a[N1], cExcess, a[0])
#   staticFor i, 1, N2-N1:
#     muladd2(hi, r[i], a[i+N1], cExcess, a[i], hi)


#   # Since for Poly1305 N2 < 2*N1, there is no carry for the last limb
#   static: doAssert N2 < 2*N1
#   hi += a[N1-1]
#   # Now `hi` stores a'.2¹³⁰ + b'.
#   # a' should be folded back to the lower bits
#   # After folding, the result is in range [0, 2¹³⁰)

#   # b': Mask out the top bits that will be folded
#   r[N1-1] = hi and (MaxWord shr excessBits)
#   # a': Fold the top bits into lower bits
#   hi = hi shr (WordBitwidth - excessBits)
#   hi *= c # Cannot overflow

#   # Second pass, fold everything greater than 2¹³⁰-1
#   # into the lower bits
#   var carry: Carry
#   addC(carry, r[0], r[0], hi, Carry(0))
#   staticFor i, 1, N1:
#     addC(carry, r[i], r[i], Zero, carry)

# func finalReduce_1305[N: static int](a: var Limbs[N]) =
#   ## Maps an input in redundant representation [0, 2¹³¹-10)
#   ## to the canonical representation in [0, 2¹³⁰-5)
#   # Algorithm:
#   # 1. substract p = 2¹³⁰-5
#   # 2. if borrow, add back p.
#   when UseASM_X86_32 and a.len <= 6:
#     submod_asm(a, a, P1305.limbs, P1305.limbs)
#   else:
#     let underflowed = sub(a, P1305.limbs)
#     discard cadd(a, P1305.limbs, underflowed)

const BlockSize = 16

type Poly1305_CTX = object
  acc: BigInt[130]
  r, s: BigInt[128]
  buf: array[BlockSize, byte]
  msgLen: uint64
  bufIdx: uint8

type poly1305* = Poly1305_CTX

func macMessageBlocks[T: byte|char](
       acc: var BigInt[130],
       r: BigInt[128],
       message: openArray[T],
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

  # Ensure there is a spare bit to handle carries when adding 2 numbers
  const bits = 130
  const excessBits = wordsRequired(bits)*WordBitWidth - bits
  
   # acc+input can use up to 131-bit
  static: doAssert excessBits >= 1

  var input {.noInit.}: BigInt[130]
  # r is 128-bit
  var t{.noInit.}: BigInt[131+128]

  for curBlock in 0 ..< numBlocks:
    # range [0, 2¹²⁸-1)
    when T is byte:
      input.unmarshal(
        message.toOpenArray(curBlock*BlockSize, curBlock*BlockSize + BlockSize - 1),
        littleEndian
      )
    else:
      input.unmarshal(
        message.toOpenArrayByte(curBlock*BlockSize, curBlock*BlockSize + BlockSize - 1),
        littleEndian
      )
    input.setBit(8*blockSize) # range [2¹²⁸, 2¹²⁸+2¹²⁸-1)
    acc += input              # range [2¹²⁸, 2¹³⁰-1+2¹²⁸+2¹²⁸-1)
    t.prod(acc, r)            # range [2²⁵⁶, (2¹²⁸-1)(2¹³⁰+2(2¹²⁸-1)))
    
    # TODO: fast reduction
    acc.limbs.reduce(t.limbs, 131+128, P1305.limbs, 130)

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

func update*[T: char|byte](ctx: var Poly1305_CTX, message: openArray[T]) =
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
      ctx.buf.copy(dStart = bufIdx, message, sStart = 0, len = bytesLeft)
      ctx.bufIdx += bytesLeft.uint8
      return
    else:
      # Fill the buffer and do one sha256 hash
      ctx.buf.copy(dStart = bufIdx, message, sStart = 0, len = free)
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

    ctx.buf.copy(dStart = 0'u, message, sStart = cur, len = bytesLeft)
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

func authenticate*[T: char, byte](
       _: type poly1305,
       tag: var array[16, byte],
       message: openArray[T],
       nonReusedKey: array[32, byte],
       clearMem = false) =
  ## Produce an authentication tag from a message
  ## and a preshared unique non-reused secret key
  
  var ctx {.noInit.}: poly1305
  ctx.init(nonReusedKey)
  ctx.update(message)
  ctx.finish(tag)

  if clearMem:
    ctx.clear()

func authenticate*[T: char, byte](
       _: type poly1305,
       message: openArray[T],
       nonReusedKey: array[32, byte],
       clearMem = false): array[16, byte]{.noInit.}=
  ## Produce an authentication tag from a message
  ## and a preshared unique non-reused secret key
  poly1305.authenticate(result, message, nonReusedKey, clearMem)