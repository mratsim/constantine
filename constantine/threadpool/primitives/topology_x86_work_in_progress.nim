# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# TODO: This is Work-in-Progress
import strutils # debug-only import

type
  CpuX86Vendor = enum
    kUnknown
    kAMD
    kIntel
    # TODO: virtualization vendor

  CpuIdRegs = object
    eax, ebx, ecx, edx: uint32

  CpuX86Socket = object
    phys_cores: int32
    logi_cores: int32
    perf_cores: int32
    effi_cores: int32

  CpuTopology = object
    sockets: array[32, CpuX86Socket] # HP SuperDome motherboards can support up to 32 sockets
    num_sockets: int8
    vendor: CpuX86Vendor
    max_leaf: uint32
    max_leaf_ext: uint32

# CPU Query
# ----------------------------------------------------------------------

proc cpuid(eax: uint32, ecx = 0'u32): CpuIdRegs =
  ## Query the CPU
  ##
  ## CPUID is a very slow operation, 27-70 cycles, ~120 latency
  ##   - https://uops.info/table.html
  ##   - https://www.agner.org/optimize/instruction_tables.pdf
  ##
  ## and need to be cached if CPU capabilities are needed in a hot path
  when defined(vcc):
    # limited inline asm support in MSVC, so intrinsics, here we go:
    proc cpuidMSVC(cpuInfo: ptr uint32; functionID, subFunctionID: uint32)
      {.noconv, importc: "__cpuidex", header: "intrin.h".}
    cpuidMSVC(addr result, eax, ecx)
  else:
    # Note: https://bugs.llvm.org/show_bug.cgi?id=17907
    # AddressSanitizer + -mstackrealign might not respect RBX clobbers.
    asm """
      cpuid
      :"=a"(`result.eax`), "=b"(`result.ebx`), "=c"(`result.ecx`), "=d"(`result.edx`)
      :"a"(`eax`), "c"(`ecx`)"""

# Topology detection
# ----------------------------------------------------------------------

proc leaf(id, maxLeaf: uint32): CpuIdRegs =
  if id <= maxLeaf:
    result = cpuid(id)

proc test(input, bit: uint32): bool =
  ((1'u32 shl bit) and input) != 0

proc getU8(input, pos: uint32): uint8 =
  uint8((input shr pos) and 0xFF'u32)

proc detectVendor(leaf0: CpuIdRegs): CpuX86Vendor =
  # Avoid string alloc by using compile-time strings only,

  var vendorString {.noInit.}: array[12, char]
  copyMem(vendorString[0].addr, leaf0.ebx.unsafeAddr, 4)
  copyMem(vendorString[4].addr, leaf0.edx.unsafeAddr, 4)
  copyMem(vendorString[8].addr, leaf0.ecx.unsafeAddr, 4)

  if vendorString == "AuthenticAMD":
    kAMD
  elif vendorString == "GenuineIntel":
    kIntel
  else:
    kUnknown

# TODO:
# Use enums and make detectAMD / detectIntel stateless so they can be fed synthetic / raw CPUID dumps for testing.

proc detectAmd(topo: var CpuTopology, maxLeaf, maxLeafExt: uint32) =
  # https://patchwork.kernel.org/project/kvm/patch/1523402169-113351-8-git-send-email-babu.moger@amd.com/
  #
  # AMD64 Architecture Programmer's Manual Volume 3: General-Purpose and System Instructions
  # June 2023
  # https://www.amd.com/content/dam/amd/en/documents/processor-tech-docs/programmer-references/24594.pdf
  # p645, section E.5 Multiple Procesor Calculation

  let leaf1 = leaf(1, maxLeaf)
  let leaf_0x8000_0008 = leaf(0x8000_0008'u32, maxLeafExt)
  let leaf_0x8000_0001 = leaf(0x8000_0001'u32, maxLeafExt)

  let topoext = leaf_0x8000_0001.ecx.test(22)

  let leaf_0x8000_001E = leaf(0x8000_001E'u32, maxLeafExt)

  let maxApicId = leaf1.ebx.getU8(16) # Beware of ApicID gaps

  # pick Extended Topology or Legacy method
  let apicIdSize = leaf_0x8000_0008.ecx.getU8(12) and 0xF
    # Tells if we need to use legacy methods for detecting logical processor
    # or tells the max number of logical core supported 1 shl apicidSize

  # New (?) undocumented method
  let threadsPerComputeUnit = leaf_0x8000_001E.ebx.getU8(8) + 1

  # Legacy detection method
  let htt = leaf1.edx.test(28)
  let cmp_legacy = leaf_0x8000_0001.ecx.test(1) # Legacy core multi-processing
  let logicalProcessorCount = leaf1.ebx.getU8(16)
  let numThreads = leaf_0x8000_0008.ecx.getU8(0) + 1
    # This is named NT and confusingly described as "number of physical threads"
    # but later referred as NC as the number of logical processor per package.

  debugEcho "apicIdSize: ", apicIdSize
  debugEcho "----"
  debugEcho "max_apic_id: ", maxApicId # Beware of ApicID gaps
  debugEcho "threadsPerComputeUnit: ", threadsPerComputeUnit
  debugEcho "----"
  debugEcho "htt: ", htt
  debugEcho "cmp_legacy: ", cmp_legacy
  debugEcho "logicalProcessorCount: ", logicalProcessorCount
  debugEcho "numThreads: ", numThreads

  # TODO: multi-socket detection via leaf 0x8000_0026

proc detectPlatform(): CpuTopology =
  let leaf0 = cpuid(0)
  let maxLeaf = leaf0.eax
  let vendor = leaf0.detectVendor()

  let leaf_0x8000_0000 = cpuid(0x8000_0000'u32)
  let maxLeafExt = if leaf_0x8000_0000.eax < 0x8000_0000'u32: 0'u32
                   elif leaf_0x8000_0000.eax >= 0x9000_0000'u32: 0'u32
                   else: leaf_0x8000_0000.eax

  debugEcho "maxLeaf: ", maxLeaf.toHex()
  debugEcho "maxLeafExt: ", maxLeafExt.toHex()

  result.detectAmd(maxLeaf, maxLeafExt)

# Sanity
# ----------------------------------------------------------------------

proc main() =
  discard detectPlatform()

main()