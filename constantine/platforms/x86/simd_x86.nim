# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

{.push used.} # Some SIMDs are implemented but not exported.

static: doAssert defined(i386) or defined(amd64)

# SIMD throughput and latency:
#   - https://software.intel.com/sites/landingpage/IntrinsicsGuide/
#   - https://www.agner.org/optimize/instruction_tables.pdf

# Reminder: x86 is little-endian, order is [low part, high part]
# Documentation at https://software.intel.com/sites/landingpage/IntrinsicsGuide/

when defined(vcc):
  {.pragma: x86_type, byCopy, header:"<intrin.h>".}
  {.pragma: x86, noDecl, header:"<intrin.h>".}
else:
  {.pragma: x86_type, byCopy, header:"<x86intrin.h>".}
  {.pragma: x86, noDecl, header:"<x86intrin.h>".}

type
  m128* {.importc: "__m128", x86_type.} = object
    raw: array[4, float32]
  m128d* {.importc: "__m128d", x86_type.} = object
    raw: array[2, float64]
  m128i* {.importc: "__m128i", x86_type.} = object
    raw: array[16, byte]
  m256* {.importc: "__m256", x86_type.} = object
    raw: array[8, float32]
  m256d* {.importc: "__m256d", x86_type.} = object
    raw: array[4, float64]
  m256i* {.importc: "__m256i", x86_type.} = object
    raw: array[32, byte]
  m512* {.importc: "__m512", x86_type.} = object
    raw: array[16, float32]
  m512d* {.importc: "__m512d", x86_type.} = object
    raw: array[8, float64]
  m512i* {.importc: "__m512i", x86_type.} = object
    raw: array[64, byte]
  mmask8* {.importc: "__mmask8", x86_type.} = uint8
  mmask16* {.importc: "__mmask16", x86_type.} = uint16
  mmask64* {.importc: "__mmask64", x86_type.} = uint64

# ############################################################
#
#                    SSE2 - integer - packed
#
# ############################################################

func mm_setzero_si128(): m128i {.importc: "_mm_setzero_si128", x86.}
func mm_set1_epi8(a: int8 or uint8): m128i {.importc: "_mm_set1_epi8", x86.}
func mm_set1_epi16(a: int16 or uint16): m128i {.importc: "_mm_set1_epi16", x86.}
func mm_set1_epi32(a: int32 or uint32): m128i {.importc: "_mm_set1_epi32", x86.}
func mm_set1_epi64x(a: int64 or uint64): m128i {.importc: "_mm_set1_epi64x", x86.}
func mm_set_epi64x(e1, e0: int64 or uint64): m128i {.importc: "_mm_set_epi64x", x86.}
func mm_load_si128(mem_addr: ptr m128i): m128i {.importc: "_mm_load_si128", x86.}
func mm_loadu_si128(mem_addr: ptr m128i): m128i {.importc: "_mm_loadu_si128", x86.}
func mm_store_si128(mem_addr: ptr m128i, a: m128i) {.importc: "_mm_store_si128", x86.}
func mm_storeu_si128(mem_addr: ptr m128i, a: m128i) {.importc: "_mm_storeu_si128", x86.}

func mm_set_epi32(e3, e2, e1, e0: int32 or uint32): m128i {.importc: "_mm_set_epi32", x86.}
  ## Initialize m128i with {e3, e2, e1, e0} (big endian order)
  ## in order [e0, e1, e2, e3]
func mm_setr_epi32(e3, e2, e1, e0: int32 or uint32): m128i {.importc: "_mm_setr_epi32", x86.}
  ## Initialize m128i with {e3, e2, e1, e0} (big endian order)
  ## in order [e3, e2, e1, e0]

func mm_xor_si128(a, b: m128i): m128i {.importc: "_mm_xor_si128", x86.}

func mm_add_epi8(a, b: m128i): m128i {.importc: "_mm_add_epi8", x86.}
func mm_add_epi16(a, b: m128i): m128i {.importc: "_mm_add_epi16", x86.}
func mm_add_epi32(a, b: m128i): m128i {.importc: "_mm_add_epi32", x86.}
func mm_add_epi64(a, b: m128i): m128i {.importc: "_mm_add_epi64", x86.}

func mm_slli_epi64(a: m128i, imm8: int32 or uint32): m128i {.importc: "_mm_slli_epi64", x86.}
  ## Shift 2xint64 left
func mm_srli_epi64(a: m128i, imm8: int32 or uint32): m128i {.importc: "_mm_srli_epi64", x86.}
  ## Shift 2xint64 right
func mm_srli_epi32(a: m128i, imm8: int32 or uint32): m128i {.importc: "_mm_srli_epi32", x86.}
  ## Shift 4xint32 left
func mm_slli_epi32(a: m128i, imm8: int32 or uint32): m128i {.importc: "_mm_slli_epi32", x86.}
  ## Shift 4xint32 right

func mm_shuffle_epi32(a: m128i, imm8: int32 or uint32): m128i {.importc: "_mm_shuffle_epi32", x86.}
  ## Shuffle 32-bit integers in a according to the control in imm8
  ## Formula is in big endian representation
  ## a = {a3, a2, a1, a0}
  ## dst = {d3, d2, d1, d0}
  ## imm8 = {bits[7:6], bits[5:4], bits[3:2], bits[1:0]}
  ## d0 will refer a[bits[1:0]]
  ## d1            a[bits[3:2]]

# ############################################################
#
#                    SSSE3 - integer - packed
#
# ############################################################

func mm_alignr_epi8(a, b: m128i, imm8: int32 or uint32): m128i {.importc: "_mm_alignr_epi8", x86.}
  ## Concatenate 16-byte blocks in a and b into a 32-byte temporary result,
  ## shift the result right by imm8 bytes, and return the low 16 bytes
  ## Input:
  ##   a[127:0], b[127:0]
  ## Result:
  ##   tmp[255:128] = a
  ##   tmp[127:0]   = b
  ##   tmp[255:0]   = tmp[255:0] >> (imm8*8)
  ##   dst[127:0]   = tmp[127:0]

func mm_shuffle_epi8(a, b: m128i): m128i {.importc: "_mm_shuffle_epi8", x86.}
  ## Shuffle 8-bit integers in a according to the control mask in b
  ## Formula is in big endian representation
  ## a =   {a15, a14, a13, a12, a11, a10, a9, a8, a7, a6, a5, a4, a3, a2, a1, a0}
  ## b =   {b15, b14, b13, b12, b11, b10, b9, b8, b7, b6, b5, b4, b3, b2, b1, b0}
  ## dst = {d15, d14, d13, d12, d11, d10, d9, d8, d7, d6, d5, d4, d3, d2, d1, d0}
  ##
  ## The control mask b0 ... b15 have the shape:
  ## bits z000uvwx
  ## if z is set, the corresponding d is set to zero.
  ## otherwise uvwx represents a binary number in 0..15,
  ##           the corresponding d will be set to a(uvwx)
  ##
  ## for i in 0 ..< 16:
  ##  if bitand(b[i], 0x80) != 0:
  ##   dst[i] = 0
  ##  else:
  ##   dst[i] = a[bitand(b[i], 0x0F)]

# ############################################################
#
#                    SSE4.1 - integer - packed
#
# ############################################################

func mm_blend_epi16(a, b: m128i, imm8: int32 or uint32): m128i {.importc: "_mm_blend_epi16", x86.}
  ## Blend packed 16-bit integers from a and b using control mask imm8,
  ## and store the results in dst.
  ##
  ## FOR j := 0 to 7
  ## i := j*16
  ## IF imm8[j]
  ##   dst[i+15:i] := b[i+15:i]
  ## ELSE
  ##   dst[i+15:i] := a[i+15:i]

# ############################################################
#
#                  AVX512F - integer - packed
#
# ############################################################

func mm_ror_epi32(a: m128i, imm8: int32 or uint32): m128i {.importc: "_mm_ror_epi32", x86.}
  ## Rotate 4xint32 right

func mm_mask_add_epi32(src: m128i, mask: mmask8, a, b: m128i): m128i {.importc: "_mm_mask_add_epi32", x86.}
  ## Add packed 32-bit integers in a and b, and store the results in dst using writemask mask
  ## (elements are copied from src when the corresponding mask bit is not set).
  ## for j in 0 ..< 4:
  ##   let i = j*32
  ##   if k[j]:
  ##     dst[i+31:i] := a[i+31:i] + b[i+31:i]
  ##   else:
  ##     dst[i+31:i] := src[i+31:i]

# ############################################################
#
#                  SHA extensions
#
# ############################################################

func mm_sha256msg1_epu32(a, b: m128i): m128i {.importc: "_mm_sha256msg1_epu32", x86.}
  ## Perform an intermediate calculation for the next four SHA256 message values (unsigned 32-bit integers)
  ## using previous message values from a and b, and store the result in dst.
  ##
  ## W4 := b[31:0]
  ## W3 := a[127:96]
  ## W2 := a[95:64]
  ## W1 := a[63:32]
  ## W0 := a[31:0]
  ## dst[127:96] := W3 + sigma0(W4)
  ## dst[95:64] := W2 + sigma0(W3)
  ## dst[63:32] := W1 + sigma0(W2)
  ## dst[31:0] := W0 + sigma0(W1)

func mm_sha256msg2_epu32(a, b: m128i): m128i {.importc: "_mm_sha256msg2_epu32", x86.}
  ## Perform the final calculation for the next four SHA256 message values (unsigned 32-bit integers)
  ## using previous message values from a and b, and store the result in dst.
  ##
  ## W14 := b[95:64]
  ## W15 := b[127:96]
  ## W16 := a[31:0] + sigma1(W14)
  ## W17 := a[63:32] + sigma1(W15)
  ## W18 := a[95:64] + sigma1(W16)
  ## W19 := a[127:96] + sigma1(W17)
  ## dst[127:96] := W19
  ## dst[95:64] := W18
  ## dst[63:32] := W17
  ## dst[31:0] := W16

func mm_sha256rnds2_epu32(cdgh, abef, k: m128i): m128i {.importc: "_mm_sha256rnds2_epu32", x86.}
  ## Perform 2 rounds of SHA256 operation using
  ##   an initial SHA256 state (C,D,G,H) from a,
  ##   an initial SHA256 state (A,B,E,F) from b,
  ##   and a pre-computed sum of the next 2 round message values (unsigned 32-bit integers)
  ##     and the corresponding round constants from k,
  ## and store the updated SHA256 state (A,B,E,F) in dst.
  ##
  ## A[0] := b[127:96]
  ## B[0] := b[95:64]
  ## C[0] := a[127:96]
  ## D[0] := a[95:64]
  ## E[0] := b[63:32]
  ## F[0] := b[31:0]
  ## G[0] := a[63:32]
  ## H[0] := a[31:0]
  ## W_K[0] := k[31:0]
  ## W_K[1] := k[63:32]
  ## FOR i := 0 to 1
  ##   A[i+1] := Ch(E[i], F[i], G[i]) + sum1(E[i]) + W_K[i] + H[i] + Maj(A[i], B[i], C[i]) + sum0(A[i])
  ##   B[i+1] := A[i]
  ##   C[i+1] := B[i]
  ##   D[i+1] := C[i]
  ##   E[i+1] := Ch(E[i], F[i], G[i]) + sum1(E[i]) + W_K[i] + H[i] + D[i]
  ##   F[i+1] := E[i]
  ##   G[i+1] := F[i]
  ##   H[i+1] := G[i]
  ## ENDFOR
  ## dst[127:96] := A[2]
  ## dst[95:64] := B[2]
  ## dst[63:32] := E[2]
  ## dst[31:0] := F[2]

# Aliases
# ------------------------------------------------

template set_u64x2*(e1, e0: int64 or uint64): m128i =
  mm_set_epi64x(e1, e0)
template setr_u32x4*(e3, e2, e1, e0: int32 or uint32): m128i =
  mm_setr_epi32(e3, e2, e1, e0)
template loada_u128*(data: pointer): m128i =
  mm_load_si128(cast[ptr m128i](data))
template loadu_u128*(data: pointer): m128i =
  mm_loadu_si128(cast[ptr m128i](data))
template storea_u128*(mem_addr: pointer, a: m128i) =
  mm_store_si128(cast[ptr m128i](mem_addr), a)

template xor_u128*(a, b: m128i): m128i =
  mm_xor_si128(a, b)

template add_u32x4*(a, b: m128i): m128i =
  mm_add_epi32(a, b)
template shl_u32x4*(a: m128i, imm8: int32 or uint32): m128i =
  mm_slli_epi32(a, imm8)
template shr_u32x4*(a: m128i, imm8: int32 or uint32): m128i =
  mm_srli_epi32(a, imm8)
template shr_u64x2*(a: m128i, imm8: int32 or uint32): m128i =
  mm_srli_epi64(a, imm8)

template alignr_u128*(a, b: m128i, shiftRightByBytes: int32 or uint32): m128i =
  mm_alignr_epi8(a, b, shiftRightByBytes)
template shuf_u8x16*(a: m128i, mask: m128i): m128i =
  mm_shuffle_epi8(a, mask)
template shuf_u32x4*(a: m128i, mask: int32 or uint32): m128i =
  mm_shuffle_epi32(a, mask)
template blend_u16x8*(a, b: m128i, mask: int32 or uint32): m128i =
  mm_blend_epi16(a, b, mask)

template sha256_msg1*(a, b: m128i): m128i =
  mm_sha256msg1_epu32(a, b)
template sha256_msg2*(a, b: m128i): m128i =
  mm_sha256msg2_epu32(a, b)
template sha256_2rounds*(cdgh, abef, k: m128i): m128i =
  mm_sha256rnds2_epu32(cdgh, abef, k)