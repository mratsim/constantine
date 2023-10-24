# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ../loadtime_functions

# CPU Query
# ----------------------------------------------------------------------

proc cpuidX86(eaxi, ecxi: int32): tuple[eax, ebx, ecx, edx: int32] =
  ## Query the CPU
  ##
  ## CPUID is a very slow operation, 27-70 cycles, ~120 latency
  ##   - https://uops.info/table.html
  ##   - https://www.agner.org/optimize/instruction_tables.pdf
  ##
  ## and need to be cached if CPU capabilities are needed in a hot path
  when defined(vcc):
    # limited inline asm support in MSVC, so intrinsics, here we go:
    proc cpuidMSVC(cpuInfo: ptr int32; functionID, subFunctionID: int32)
      {.noconv, importc: "__cpuidex", header: "intrin.h".}
    cpuidMSVC(addr result.eax, eaxi, ecxi)
  else:
    # Note: https://bugs.llvm.org/show_bug.cgi?id=17907
    # AddressSanitizer + -mstackrealign might not respect RBX clobbers.
    var (eaxr, ebxr, ecxr, edxr) = (0'i32, 0'i32, 0'i32, 0'i32)
    asm """
      cpuid
      :"=a"(`eaxr`), "=b"(`ebxr`), "=c"(`ecxr`), "=d"(`edxr`)
      :"a"(`eaxi`), "c"(`ecxi`)"""
    (eaxr, ebxr, ecxr, edxr)

# CPU Name
# ----------------------------------------------------------------------

proc cpuName_x86*(): string =
  let leaves = cast[array[48, char]]([
    cpuidX86(eaxi = 0x80000002'i32, ecxi = 0),
    cpuidX86(eaxi = 0x80000003'i32, ecxi = 0),
    cpuidX86(eaxi = 0x80000004'i32, ecxi = 0)])
  result = $cast[cstring](unsafeAddr leaves[0])

# CPU Features
# ----------------------------------------------------------------------
#
# Design considerations
# - An enum might feel natural to organize all x86 features,
#   however new features regularly come
#   and this means all switches over the enum need to be updated
#   and code recompiled if the enum is part of the public API.
#   see also the "expression problem".
# - Caching CPUID calls
# - Dead-code elimination via LTO
#   with individual bools, if none are used except at initialization
#   LTO can eliminate the bools (unlike with an object)
# - If heterogenous systems have ISA differences between cores
#   like PPU/SPU on IBM Cell/Playstation 3
#   or Alder Lake temporary AVX512 on Performance cores but not on Efficiency cores
#   we can more easily extend procedures with a core ID (+ getCurrentCoreID())
#   and a sensible default parameter to avoid refactoring all call sites.
# - Documentation. The docgen is focused on documenting functions.
# - We keep only useful functions rather than aim for exhaustiveness
#   - for example "prefetch" is covered by compiler ``builtin_prefetch()``.
#   - Deprecated sets like 3DNow, SSE4a, ABM, FMA4, XOP, TSX, MPX, ... aren't listed.
#   - Trusted enclave features like SGX, TDX or TEE should be managed at a higher level.
#   - Xeon Phi instructions are not listed.

var
  # 1999 - Pentium 3, 2001 - Athlon XP
  hasSseImpl: bool
  # 2000 - Pentium 4 Willamette
  hasSse2Impl: bool
  # 2002 - Pentium 4 Northwood
  hasSimultaneousMultithreadingImpl: bool
  # 2004 - Pentium 4 Prescott
  hasSse3Impl: bool
  hasCas16BImpl: bool
  # 2006 - Core 2 Merom
  hasSsse3Impl: bool
  # 2007 - Core 2 Penryn
  hasSse41Impl: bool
  # 2007 - Core iX-XXX Nehalem
  hasSse42Impl: bool
  hasPopcntImpl: bool
  # 2010 - Core iX-XXX Westmere
  hasAesImpl: bool
  hasClMulImpl: bool           # Carry-less multiplication
  # 2011 - Core iX-2XXX Sandy Bridge
  hasAvxImpl: bool
  # 2012 - Core iX-3XXX Ivy Bridge
  hasRdrandImpl: bool
  # fs/gs access for thread-local memory through assembly
  # 2013 - Core iX-4XXX Haswell
  hasAvx2Impl: bool
  hasFma3Impl: bool
  hasBmi1Impl: bool            # LZCNT, TZCNT
  hasBmi2Impl: bool            # MULX, RORX, SARX, SHRX, SHLX
  # 2014 - Core iX-5XXX Broadwell
  hasAdxImpl: bool             # ADCX, ADOX                AMD: Zen 1st gen - 2017
  hasRdseedImpl: bool
  # 2017 - Core iX-7XXXX Skylake-X
  hasAvx512fImpl: bool         # AVX512 Foundation
  hasAvx512bwImpl: bool        # AVX512 Byte and Word
  hasAvx512dqImpl: bool        # AVX512 DoubleWord and QuadWord
  hasAvx512vlImpl: bool        # AVX512 Vector Length Extension (AVX512 instructions ported to SSE and AVX)
  # 2019 - Ice-Lake & Core iX-10XXX Comet Lake
  hasShaImpl: bool             #                           AMD: Zen 1st gen - 2017
  hasGfniImpl: bool            # Galois Field New Instruction (SSE, AVX, AVX512)
  hasVectorAesImpl: bool       # Vector AES
  hasVectorClMulImpl: bool     # Vector Carry-Less Multiplication
  hasAvx512ifmaImpl: bool      # AVX512 Integer Fused-Multiply-Add
  hasAvx512PopcountImpl: bool  # AVX512 Vector Popcount double and quadword
  hasAvx512vnniImpl: bool      # AVX512 Vector Neural Network Instruction (Note: They multiply-accumulate bytes or integers, https://en.wikichip.org/wiki/x86/avx512_vnni)
  hasAvx512vbmiImpl: bool      # AVX512 Bit Manipulation 1
  hasAvx512vbmi2Impl: bool     # AVX512 Bit Manipulation 2
  hasAvx512bitalgImpl: bool    # AVX512 Bit ALgorithm

proc detectCpuFeaturesX86() {.loadTime.} =
  proc test(input, bit: int): bool =
    ((1 shl bit) and input) != 0

  let
    leaf1 = cpuidX86(eaxi = 1, ecxi = 0)
    leaf7 = cpuidX86(eaxi = 7, ecxi = 0)
    # leaf8 = cpuidX86(eaxi = 0x80000001'i32, ecxi = 0)

  # see: https://en.wikipedia.org/wiki/CPUID#Calling_CPUID
  # see: Intel® Architecture Instruction Set Extensions and Future Features Programming Reference
  #      2023-09: https://cdrdv2-public.intel.com/790021/architecture-instruction-set-extensions-programming-reference.pdf

  # leaf 1, ecx
  hasSse3Impl             = leaf1.ecx.test(0)
  hasSsse3Impl            = leaf1.ecx.test(9)
  hasFma3Impl             = leaf1.ecx.test(12)
  hasCas16BImpl           = leaf1.ecx.test(13)
  hasSse41Impl            = leaf1.ecx.test(19)
  hasSse42Impl            = leaf1.ecx.test(20)
  hasPopcntImpl           = leaf1.ecx.test(23)
  hasAesImpl              = leaf1.ecx.test(25)
  hasAvxImpl              = leaf1.ecx.test(28)
  hasRdrandImpl           = leaf1.ecx.test(30)

  # leaf 1, EDX
  hasSseImpl                        = leaf1.edx.test(25)
  hasSse2Impl                       = leaf1.edx.test(26)
  hasSimultaneousMultithreadingImpl = leaf1.edx.test(28)

  # leaf 7, eax
  # hasSha512Impl        = leaf7.eax.test(0)    # SHA512 - 2024 Intel Arrow Lake and Lunar Lake processor
  # hasSm3Impl           = leaf7.eax.test(1)    # SM3 Cryptographic hash function
  # hasSm4Impl           = leaf7.eax.test(2)    # SM4 Cryptographic hash function
  # hasAvxIfmaImpl       = leaf7.eax.test(23)

  # leaf 7, ebx
  # hasSgxImpl        = leaf7.ebx.test(2)
  hasBmi1Impl       = leaf7.ebx.test(3)
  hasAvx2Impl       = leaf7.ebx.test(5)
  hasBmi2Impl       = leaf7.ebx.test(8)
  hasAvx512fImpl    = leaf7.ebx.test(16)
  hasAvx512dqImpl   = leaf7.ebx.test(17)
  hasRdseedImpl     = leaf7.ebx.test(18)
  hasAdxImpl        = leaf7.ebx.test(19)
  hasAvx512ifmaImpl = leaf7.ebx.test(21)
  hasShaImpl        = leaf7.ebx.test(29)
  hasAvx512bwImpl   = leaf7.ebx.test(30)
  hasAvx512vlImpl   = leaf7.ebx.test(31)

  # leaf 7, ecx
  hasAvx512vbmiImpl      = leaf7.ecx.test(1)
  hasAvx512vbmi2Impl     = leaf7.ecx.test(6)
  hasGfniImpl            = leaf7.ecx.test(8)
  hasVectorAesImpl       = leaf7.ecx.test(9)
  hasVectorClMulImpl     = leaf7.ecx.test(10)
  hasAvx512vnniImpl      = leaf7.ecx.test(11)
  hasAvx512bitalgImpl    = leaf7.ecx.test(12)
  hasAvx512PopcountImpl  = leaf7.ecx.test(14)

  # leaf 7, edx
  # hasAvx512vp2intersectImpl = leaf7.edx.test(8)

  # leaf 8, ecx
  # AMD specific deprecated instructions

  # leaf 8, edx
  # hasSimultaneousMultithreadingImpl = hasSimultaneousMultithreadingImpl and
  #                                     not leaf8.edx.test(1) # AMD core multi-processing legacy mode


# 1999 - Pentium 3, 2001 - Athlon XP
# ------------------------------------------
proc hasSse*(): bool {.inline.} =
  return hasSseImpl

# 2000 - Pentium 4 Willamette
# ------------------------------------------
proc hasSse2*(): bool {.inline.} =
  return hasSse2Impl

# 2002 - Pentium 4 Northwood
# ------------------------------------------
proc hasSimultaneousMultithreading*(): bool {.inline.} =
  return hasSimultaneousMultithreadingImpl

# 2004 - Pentium 4 Prescott
# ------------------------------------------
proc hasSse3*(): bool {.inline.} =
  return hasSse3Impl
proc hasCas16B*(): bool {.inline.} =
  ## Compare-and-swap 128-bit (16 bytes) support
  return hasCas16BImpl

# 2006 - Core 2 Merom
# ------------------------------------------
proc hasSsse3*(): bool {.inline.} =
  return hasSsse3Impl

# 2007 - Core 2 Penryn
# ------------------------------------------
proc hasSse41*(): bool {.inline.} =
  return hasSse41Impl

# 2007 - Core iX-XXX Nehalem
# ------------------------------------------
proc hasSse42*(): bool {.inline.} =
  return hasSse42Impl
proc hasPopcnt*(): bool {.inline.} =
  return hasPopcntImpl

# 2010 - Core iX-XXX Westmere
# ------------------------------------------
proc hasAes*(): bool {.inline.} =
  return hasAesImpl
proc hasCLMUL*(): bool {.inline.} =
  ## Carry-less multiplication support
  return hasClMulImpl

# 2011 - Core iX-2XXX Sandy Bridge
# ------------------------------------------
proc hasAvx*(): bool {.inline.} =
  return hasAvxImpl

# 2012 - Core iX-3XXX Ivy Bridge
# ------------------------------------------
# fs/gs access for thread-local memory through assembly
proc hasRdrand*(): bool {.inline.} =
  return hasRdrandImpl

# 2013 - Core iX-4XXX Haswell
# ------------------------------------------
proc hasAvx2*(): bool {.inline.} =
  return hasAvx2Impl
proc hasFma3*(): bool {.inline.} =
  return hasFma3Impl
proc hasBmi1*(): bool {.inline.} =
  ## LZCNT, TZCNT support
  return hasBmi1Impl
proc hasBmi2*(): bool {.inline.} =
  ## MULX, RORX, SARX, SHRX, SHLX
  return hasBmi2Impl

# 2014 - Core iX-5XXX Broadwell
# ------------------------------------------
proc hasAdx*(): bool {.inline.} =
  ## ADCX, ADOX support
  # 2017 for AMD Zen 1st Gen
  return hasAdxImpl
proc hasRdseed*(): bool {.inline.} =
  return hasRdseedImpl

# 2017 - Core iX-7XXXX Skylake-X
# ------------------------------------------
proc hasAvx512f*(): bool {.inline.} =
  ## AVX512 Foundation support
  return hasAvx512fImpl
proc hasAvx512bw*(): bool {.inline.} =
  ## AVX512 Byte-and-Word support
  return hasAvx512bwImpl
proc hasAvx512dq*(): bool {.inline.} =
  ## AVX512 DoubleWord and QuadWord support
  return hasAvx512dqImpl
proc hasAvx512vl*(): bool {.inline.} =
  ## AVX512  Vector Length Extension (AVX512 instructions ported to SSE and AVX)
  return hasAvx512dqImpl

# 2019 - Ice-Lake & Core iX-10XXX Comet Lake
# ------------------------------------------
proc hasSha*(): bool {.inline.} =
  ## SHA hash function primitive
  # 2017 for AMD Zen 1st Gen
  return hasShaImpl
proc hasGfni*(): bool {.inline.} =
  ## Galois Field New Instruction support
  return hasGfniImpl
proc hasVectorAes*(): bool {.inline.} =
  return hasVectorAesImpl
proc hasVectorClMul*(): bool {.inline.} =
  ## Vector Carry-Less Multiplication support
  return hasVectorClMulImpl
proc hasAvx512Ifma*(): bool {.inline.} =
  ## AVX512 Integer Fused-Multiply-Add support
  return hasAvx512ifmaImpl
proc hasAvx512Popcount*(): bool {.inline.} =
  return hasAvx512PopcountImpl
proc hasAvx512vnni*(): bool {.inline.} =
  ## AVX512 Vector Neural Network Instruction
  ## Note: They multiply-accumulate bytes or integers
  ##   https://en.wikichip.org/wiki/x86/avx512_vnni
  return hasAvx512vnniImpl
proc hasAvx512vbmi*(): bool {.inline.} =
  return hasAvx512vbmiImpl
proc hasAvx512vbmi2*(): bool {.inline.} =
  return hasAvx512vbmi2Impl
proc hasAvx512bitalg*(): bool {.inline.} =
  ## AVX512 Bit ALgorithm
  return hasAvx512bitalgImpl
