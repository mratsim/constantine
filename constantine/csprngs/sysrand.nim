# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                  Operating System provided
#   Cryptographically Secure Pseudo-Random Number Generator
#
# ############################################################

# We use Nim effect system to track RNG subroutines
type
  CSPRNG    = object

when defined(windows):
  # There are several Windows CSPRNG APIs:
  # - CryptGenRandom
  # - RtlGenRandom
  # - BCryptGenRandom
  #
  # CryptGenRandom is Intel CPU only.
  # RtlGenRandom is deprecated, in particular it doesn't work for Windows UWP
  #  (Universal Windows Platform, single source for PC, mobile, Xbox, ...)
  #  It is the API used by Chromium, Firefox, libsodium, Rust, Go, ...
  # BCryptGenRandom is supposedly the recommended API,
  # however it has sandbox issues (it tries to read the user config in registry)
  # and random crashes when trying to force an algorithm to avoid reading user config.
  #
  # So we pick RtlGenRandom.
  #
  # - https://github.com/rust-random/getrandom/issues/65#issuecomment-753634074
  # - https://stackoverflow.com/questions/48875929/rtlgenrandom-cryptgenrandom-or-other-winapi-to-generate-cryptographically-secure
  # - https://github.com/rust-random/getrandom/issues/314
  # - https://learn.microsoft.com/en-us/archive/blogs/michael_howard/cryptographically-secure-random-number-on-windows-without-using-cryptoapi

  proc RtlGenRandom(pbuffer: pointer, len: culong): bool {.importc: "SystemFunction036", stdcall, dynlib: "advapi32.dll", sideeffect, tags: [CSPRNG].}
    #https://learn.microsoft.com/en-us/archive/blogs/michael_howard/cryptographically-secure-random-number-on-windows-without-using-cryptoapi
    # https://learn.microsoft.com/en-us/windows/win32/api/ntsecapi/nf-ntsecapi-rtlgenrandom
    #
    # BOOLEAN RtlGenRandom(
    #   [out] PVOID RandomBuffer,
    #   [in]  ULONG RandomBufferLength
    # );
    #
    # https://learn.microsoft.com/en-US/windows/win32/winprog/windows-data-types
    # BOOLEAN (to not be confused with winapi BOOL)
    # is `typedef BYTE BOOLEAN;` and so has the same representation as Nim bools.

  proc sysrand*[T](buffer: var T): bool {.inline.} =
    ## Fills the buffer with cryptographically secure random data
    return RtlGenRandom(buffer.addr, culong sizeof(T))

elif defined(linux):
  proc syscall(sysno: clong): cint {.importc, header:"<unistd.h>", varargs.}

  let
    SYS_getrandom {.importc, header: "<sys/syscall.h>".}: clong
    EAGAIN {.importc, header: "<errno.h>".}: cint
    EINTR {.importc, header: "<errno.h>".}: cint

  var errno {.importc, header: "<errno.h>".}: cint

  # https://man7.org/linux/man-pages/man2/getrandom.2.html
  #
  # ssize_t getrandom(void buf[.buflen], size_t buflen, unsigned int flags);
  #
  # For buffer <= 256 bytes, getrandom is uninterruptible
  # otherwise it can be interrupted by signals.
  # So either we read by chunks of 256 or we handle partial buffer fills after signals interruption
  #
  # We choose to handle partial buffer fills to limit the number of syscalls

  proc urandom(pbuffer: pointer, len: int): bool {.sideeffect, tags: [CSPRNG].} =

    var cur = 0
    while cur < len:
      let bytesRead = syscall(SYS_getrandom, pbuffer, len-cur, 0)
      if bytesRead > 0:
        cur += bytesRead
      elif bytesRead == 0:
        # According to documentation this should never happen,
        # either we read a positive number of bytes, or we have a negative error code
        return false
      elif errno == EAGAIN or errno == EINTR:
        # No entropy yet or interrupted by signal => retry
        discard
      else:
        # EFAULT The address referred to by buf is outside the accessible address space.
        # EINVAL An invalid flag was specified in flags.
        return false

    return true

  proc sysrand*[T](buffer: var T): bool {.inline.} =
    ## Fills the buffer with cryptographically secure random data
    return urandom(buffer.addr, sizeof(T))

elif defined(ios) or defined(macosx):
  # There are 4 APIs we can use
  # - The getentropy(2) system call (similar to OpenBSD)
  # - The random device (/dev/random)
  # - SecRandomCopyBytes
  # - CCRandomGenerateBytes
  #
  # SecRandomCopyBytes (https://opensource.apple.com/source/Security/Security-55471/sec/Security/SecFramework.c.auto.html)
  # requires linking with the Security framework,
  # uses pthread_once (so initializes Grand Central Dispatch)
  # and opens /dev/random
  # This is heavy https://github.com/rust-random/getrandom/issues/38#issuecomment-505629378
  # - It makes linking more complex
  # - It incurs a notable startup cost
  #
  # getentropy is private on IOS and can lead to appstore rejection: https://github.com/openssl/openssl/pull/15924
  # the random device can be subject to file descriptor exhaustion
  #
  # CCRandomGenerateBytes adds a DRBG on top of the raw system RNG, but it's fast
  # - https://github.com/dotnet/runtime/pull/51526
  # - https://github.com/aws/aws-lc/pull/300

  type CCRNGStatus {.importc, header: "<CommonCrypto/CommonRandom.h>".} = distinct int32

  let kCCSuccess {.importc, header: "<CommonCrypto/CommonCryptoError.h>".}: CCRNGStatus
    # https://opensource.apple.com/source/CommonCrypto/CommonCrypto-60061.30.1/include/CommonCryptoError.h.auto.html

  func `==`(x, y: CCRNGStatus): bool {.borrow.}

  proc CCRandomGenerateBytes(pbuffer: pointer, len: int): CCRNGStatus {.sideeffect, tags: [CSPRNG], importc, header: "<CommonCrypto/CommonRandom.h>".}
    # https://opensource.apple.com/source/CommonCrypto/CommonCrypto-60178.40.2/include/CommonRandom.h.auto.html

  proc sysrand*[T](buffer: var T): bool {.inline.} =
    ## Fills the buffer with cryptographically secure random data
    if kCCSuccess == CCRandomGenerateBytes(buffer.addr, sizeof(T)):
      return true
    return false

else:
  {.error: "The OS '" & $hostOS & "' has no CSPRNG configured.".}