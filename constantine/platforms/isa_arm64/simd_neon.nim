# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

{.push used.} # Some SIMDs are implemented but not exported.

static: doAssert defined(arm) or defined(arm64)

# See documentation: https://github.com/ARM-software/acle/releases

{.pragma: neon_type, importc, byCopy, header:"<arm_neon.h>".}
{.pragma: neon, importc, cdecl, header:"<arm_neon.h>".}

type
  # See <arm_vector_types.h>
  # uint8x16_t*{.importc: "__attribute__((neon_vector_type(16))) uint8_t", byCopy.} = object
  # uint32x4_t*{.importc: "__attribute__((neon_vector_type(4))) uint32_t", byCopy.} = object

  uint8x16_t*{.importc, byCopy.} = object
  uint32x4_t*{.importc, byCopy.} = object

  uint8x16x4_t* {.importc, byCopy.} = object
    val*{.importc.}: array[4, uint8x16_t]

  uint32x4x2_t* {.importc, byCopy.} = object
    val*{.importc.}: array[2, uint32x4_t]

# See https://arm-software.github.io/acle/neon_intrinsics/advsimd.html
# and PDFs at https://github.com/ARM-software/acle/releases/tag/r2024Q3

func vld1q_u32*(data: pointer): uint32x4_t {.neon.}
  ## Vector load

func vld1q_u32_x2*(data: pointer): uint32x4x2_t {.neon.}
  ## Vector load

func vld1q_u8_x4*(data: pointer): uint8x16x4_t {.neon.}
  ## Vector load

func vst1q_u32_x2*(dst: pointer, src: uint32x4x2_t) {.neon.}
  ## Vector store

func vrev32q_u8*(vec: uint8x16_t): uint8x16_t {.neon.}
  ## Reverse bytes for 32-bit words, i.e. swap 32-bit int endianness

func vreinterpretq_u32_u8*(a: uint8x16_t): uint32x4_t {.neon.}
  ## Vector cast from 16 uint8 to 4 uint32

func vaddq_u32*(a, b: uint32x4_t): uint32x4_t {.neon.}
  ## Vector addition


# ############################################################
#
#                  SHA2 extensions
#
# ############################################################

func vsha256su0q_u32*(w0_3, w4_7: uint32x4_t): uint32x4_t {.neon.} =
  ## SHA256 (message) schedule update 0
  ##
  ## With a = w0_3, b = w4_7
  ## This computes
  ##   T = [b₀, a₃, a₂, a₁]
  ##
  ##   σ₀(T) = ror(T, 7) xor ror(T, 18) xor (T >> 3)
  ##   returns a + σ₀(T)
  ##
  ## https://developer.arm.com/architectures/instruction-sets/intrinsics/vsha256su0q_u32

  # Spec
  # AArch64.CheckFPAdvSIMDEnabled();
  #
  # bits(128) operand1 = V[d];
  # bits(128) operand2 = V[n];
  # bits(128) result;
  # bits(128) T = operand2<31:0> : operand1<127:32>;
  # bits(32) elt;
  #
  # for e = 0 to 3
  #     elt = Elem[T, e, 32];
  #     elt = ROR(elt, 7) EOR ROR(elt, 18) EOR LSR(elt, 3);
  #     Elem[result, e, 32] = elt + Elem[operand1, e, 32];
  # V[d] = result;

func vsha256su1q_u32*(tw0_3, w8_11, w12_15: uint32x4_t): uint32x4_t {.neon.} =
  ## SHA256 (message) schedule update 1
  ##
  ## With a = tw0_3, b = w8_11, c = w12_15
  ## This computes
  ##   T₀ = [c₀, b₃, b₂, b₁]
  ##   T₁ = [c₃, c₂]
  ##   σ₁(T₁) = ror(T₁, 17) xor ror(T₁, 19) xor (T₁ >> 10)
  ##   r = σ₁(T₁) + a[0..1] + T₀[0..1]
  ##
  ##   T₁ = [r₁, r₀]
  ##   σ₁(T₁) = ror(T₁, 17) xor ror(T₁, 19) xor (T₁ >> 10)
  ##   r = σ₁(T₁) + a[2..3] + T₀[2..3]
  ##
  ## https://developer.arm.com/architectures/instruction-sets/intrinsics/vsha256su1q_u32

  # Spec
  # AArch64.CheckFPAdvSIMDEnabled();
  #
  # bits(128) operand1 = V[d];
  # bits(128) operand2 = V[n];
  # bits(128) operand3 = V[m];
  # bits(128) result;
  # bits(128) T0 = operand3<31:0> : operand2<127:32>;
  # bits(64) T1;
  # bits(32) elt;
  #
  # T1 = operand3<127:64>;
  # for e = 0 to 1
  #     elt = Elem[T1, e, 32];
  #     elt = ROR(elt, 17) EOR ROR(elt, 19) EOR LSR(elt, 10);
  #     elt = elt + Elem[operand1, e, 32] + Elem[T0, e, 32];
  #     Elem[result, e, 32] = elt;
  #
  # T1 = result<63:0>;
  # for e = 2 to 3
  #     elt = Elem[T1, e - 2, 32];
  #     elt = ROR(elt, 17) EOR ROR(elt, 19) EOR LSR(elt, 10);
  #     elt = elt + Elem[operand1, e, 32] + Elem[T0, e, 32];
  #     Elem[result, e, 32] = elt;
  #
  # V[d] = result;

func vsha256hq_u32*(abcd, efgh, wk: uint32x4_t): uint32x4_t {.neon.} =
  ## SHA256 hash update (part 1)
  ##
  ## https://developer.arm.com/architectures/instruction-sets/intrinsics/vsha256hq_u32
  ## https://developer.arm.com/documentation/ddi0596/2021-03/Shared-Pseudocode/Shared-Functions?lang=en#impl-shared.SHA256hash.4

  # Spec
  # https://developer.arm.com/documentation/ddi0596/2021-03/Shared-Pseudocode/Shared-Functions?lang=en#impl-shared.SHA256hash.4
  #
  # bits(128) SHA256hash(bits (128) X, bits(128) Y, bits(128) W, boolean part1)
  #     bits(32) chs, maj, t;
  #
  #     for e = 0 to 3
  #         chs = SHAchoose(Y<31:0>, Y<63:32>, Y<95:64>);
  #         maj = SHAmajority(X<31:0>, X<63:32>, X<95:64>);
  #         t = Y<127:96> + SHAhashSIGMA1(Y<31:0>) + chs + Elem[W, e, 32];
  #         X<127:96> = t + X<127:96>;
  #         Y<127:96> = t + SHAhashSIGMA0(X<31:0>) + maj;
  #         <Y, X> = ROL(Y : X, 32);
  #     return (if part1 then X else Y);
  #
  # bits(32) SHAchoose(bits(32) x, bits(32) y, bits(32) z)
  #     return (((y EOR z) AND x) EOR z);
  #
  # bits(32) SHAhashSIGMA0(bits(32) x)
  #     return ROR(x, 2) EOR ROR(x, 13) EOR ROR(x, 22);
  #
  # bits(32) SHAhashSIGMA1(bits(32) x)
  #     return ROR(x, 6) EOR ROR(x, 11) EOR ROR(x, 25);
  #
  # bits(32) SHAmajority(bits(32) x, bits(32) y, bits(32) z)
  #     return ((x AND y) OR ((x OR y) AND z));
  #
  # bits(32) SHAparity(bits(32) x, bits(32) y, bits(32) z)
  #     return (x EOR y EOR z);

func vsha256h2q_u32*(efgh, abcd, wk: uint32x4_t): uint32x4_t {.neon.} =
  ## SHA256 hash update (part 2)
  ##
  ## https://developer.arm.com/architectures/instruction-sets/intrinsics/vsha256h2q_u32
  ## https://developer.arm.com/documentation/ddi0596/2021-03/Shared-Pseudocode/Shared-Functions?lang=en#impl-shared.SHA256hash.4
