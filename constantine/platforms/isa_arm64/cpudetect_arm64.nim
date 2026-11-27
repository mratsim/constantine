# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ../loadtime_functions

# ARM64 CPU Features
# ----------------------------------------------------------------------
#
# Unlike x86 CPUID, the ARM64 feature registers (ID_AA64ISAR0_EL1, ...)
# can only be read from EL1 (kernel) on most OSes, so we ask the OS.
#
# - Apple Silicon: every core implements the cryptographic extensions,
#   the features are compile-time constants.
# - Linux and Android: getauxval(AT_HWCAP)
#   https://docs.kernel.org/arch/arm64/elf_hwcaps.html
# - Other OSes: features are reported as absent and callers use their portable fallback.
#
# We keep only useful functions rather than aim for exhaustiveness.

when defined(macosx) or defined(ios):
  # All Apple Silicon support the AES, PMULL, SHA1, SHA2 and SHA3 extensions.
  const hasPmullImpl = true

elif defined(linux) or defined(android):
  var hasPmullImpl: bool

  proc getauxval(kind: culong): culong {.importc, header: "<sys/auxv.h>".}

  const
    AT_HWCAP = 16
    HWCAP_PMULL = 1'u64 shl 4

  proc detectCpuFeaturesArm64() {.loadTime.} =
    let hwcap = uint64 getauxval(AT_HWCAP)
    hasPmullImpl = (hwcap and HWCAP_PMULL) != 0

else:
  const hasPmullImpl = false

proc hasPmull*(): bool {.inline.} =
  ## Polynomial (carry-less) multiplication of 64-bit lanes,
  ## FEAT_PMULL, part of the AES extension.
  ## Used for binary field arithmetic and GHASH.
  return hasPmullImpl
