packageName   = "constantine"
version       = "0.1.0"
author        = "Mamy Ratsimbazafy"
description   = "This library provides thoroughly tested and highly-optimized implementations of cryptography protocols."
license       = "MIT or Apache License 2.0"

# Dependencies
# ----------------------------------------------------------------

requires "nim >= 1.6.12"

when (NimMajor, NimMinor) >= (2, 0): # Task-level dependencies
  taskRequires "make_zkalc", "jsony"
  taskRequires "make_zkalc", "cliche"

  taskRequires "test", "jsony"
  taskRequires "test", "yaml"
  taskRequires "test", "gmp#head"

  taskRequires "test_parallel", "jsony"
  taskRequires "test_parallel", "yaml"
  taskRequires "test_parallel", "gmp#head"

  taskRequires "test_no_gmp", "jsony"
  taskRequires "test_no_gmp", "yaml"

  taskRequires "test_parallel_no_gmp", "jsony"
  taskRequires "test_parallel_no_gmp", "yaml"

# Nimscript imports
# ----------------------------------------------------------------

import std/[strformat, strutils, os]

# Environment variables
# ----------------------------------------------------------------
#
# Compile-time environment variables
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# - CC="clang" or "nim c --cc:clang ..."
#       Specify the compiler.
#       Clang is recommended for fastest performance.
#
# - CTT_ASM=0 or "nim c -d:CTT_ASM=0 ..."
#        Disable assembly backend. Otherwise use ASM for supported CPUs and fallback to generic code otherwise.
#
# - CTT_LTO=1 or "nim c -d:lto ..." or "nim c -d:lto_incremental ..."
#        Enable LTO builds.
#        By default this is:
#        - Disabled for binaries
#        - Enabled for dynamic libraries, unless on MacOS or iOS
#        - Disabled for static libraries
#
# Runtime environment variables
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# - CTT_NUM_THREADS=N
#        Set the threadpool to N threads. Currently this is only supported in some tests/benchmarks.
#        Autodetect the number of threads (including siblings from hyperthreading)
#
# Developer, debug, profiling and metrics environment variables
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# - CTT_32 or "nim c -d:CTT_32 ..."
#        Compile Constantine with 32-bit backend. Otherwise autodetect.
#
# - "nim c -d:CTT_DEBUG ..."
#        Add preconditions, invariants and post-conditions checks.
#        This may leak the erroring data. Do not use with secrets.
#
# - "nim c -d:CTT_GENERATE_HEADERS ..."
# - "nim c -d:CTT_TEST_CURVES ..."
#
# - "nim c -d:CTT_THREADPOOL_ASSERTS ..."
# - "nim c -d:CTT_THREADPOOL_METRICS ..."
# - "nim c -d:CTT_THREADPOOL_PROFILE ..."
#
# - "nim c -d:CTT_THREADPOOL_DEBUG"
# - "nim c -d:CTT_THREADPOOL_DEBUG_SPLIT"
# - "nim c -d:CTT_THREADPOOL_DEBUG_TERMINATION"

proc getEnvVars(): tuple[useAsmIfAble, force32, forceLto, useLtoDefault: bool] =
  if existsEnv"CTT_ASM":
    result.useAsmIfAble = parseBool(getEnv"CTT_ASM")
  else:
    result.useAsmIfAble = true
  if existsEnv"CTT_32":
    result.force32 = parseBool(getEnv"CTT_32")
  else:
    result.force32 = false
  if existsEnv"CTT_LTO":
    result.forceLto = parseBool(getEnv"CTT_LTO")
    result.useLtoDefault = false
  else:
    result.forceLto = false
    result.useLtoDefault = true

# Library compilation
# ----------------------------------------------------------------

func compilerFlags(): string =
  # -d:danger --opt:size
  #           to avoid boundsCheck and overflowChecks that would trigger exceptions or allocations in a crypto library.
  #           Those are internally guaranteed at compile-time by fixed-sized array
  #           and checked at runtime with an appropriate error code if any for user-input.
  #
  #           Furthermore we may optimize for size, the performance critical procedures
  #           either use assembly or are unrolled manually with staticFor,
  #           Optimizations at -O3 deal with loops and branching
  #           which we mostly don't have.
  #           Hence optimizing for instructions cache may pay off.
  #
  # --panics:on -d:noSignalHandler
  #           Even with `raises: []`, Nim still has an exception path
  #           for defects, for example array out-of-bound accesses (though deactivated with -d:danger)
  #           This turns them into panics, removing exceptions from the library.
  #           We also remove signal handlers as it's not our business.
  #
  # -mm:arc -d:useMalloc
  #           Constantine stack allocates everything (except for multithreading).
  #           Inputs are through unmanaged ptr+len. So we don't want any runtime.
  #           Combined with -d:useMalloc, sanitizers and valgrind work as in C,
  #           even for test cases that needs to allocate (json inputs).
  #
  # -fno-semantic-interposition
  #           https://fedoraproject.org/wiki/Changes/PythonNoSemanticInterpositionSpeedup
  #           Default in Clang, not default in GCC, prevents optimizations, not portable to non-Linux.
  #           Also disabling this prevents overriding symbols which might actually be wanted in a cryptographic library
  #
  # -falign-functions=64
  #           Reduce instructions cache misses.
  #           https://lkml.org/lkml/2015/5/21/443
  #           Our non-inlined functions are large so size cost is minimal.
  #
  # -fmerge-all-constants
  #           Merge identical constants and variables, in particular
  #           field and curve arithmetic constant arrays.

  " -d:danger " &
  # " --opt:size " &
  " --panics:on -d:noSignalHandler " &
  " --mm:arc -d:useMalloc " &
  " --verbosity:0 --hints:off --warnings:off " &
  " --passC:-fno-semantic-interposition " &
  " --passC:-falign-functions=64 " &
  " --passC:-fmerge-all-constants"

type BuildMode = enum
  bmBinary
  bmStaticLib
  bmDynamicLib

proc releaseBuildOptions(buildMode = bmBinary): string =

  let compiler = if existsEnv"CC": " --cc:" & getEnv"CC"
                 else: ""

  let (useAsmIfAble, force32, forceLTO, useLtoDefault) = getEnvVars()
  let envASM = if not useAsmIfAble: " -d:CTT_ASM=false "
               else: ""
  let env32 = if force32: " -d:CTT_32 "
              else: ""

  # LTO config
  # -------------------------------------------------------------------------------
  # This is impacted by:
  # - LTO: LTO requires Intel Assembly for Clang
  # - MacOS / iOS: Default Apple Clang does not support Intel Assembly
  # - Rust backend:
  #     Using Clang, we can do Nim<->Rust cross-language LTO
  #     - https://blog.llvm.org/2019/09/closing-gap-cross-language-lto-between.html
  #     - https://github.com/rust-lang/rust/pull/58057
  #     - https://doc.rust-lang.org/rustc/linker-plugin-lto.html
  # - Ergonomics of LTO for static libraries
  #   LTO on static libraries requires proper match on compiler
  #   and even on compiler versions,
  #   for example LLVM 17 uses opaque pointers while LLVM 14 does not
  #   and in CI when combining default Rust (LLVM 17) and Clang/LLD (LLVM 14)
  #   we get failures.
  #
  # Hence:
  # - for binaries, LTO defaults to none and is left to the application discretion.
  #   for Constantine testing, LTO is used on non-Apple platforms.
  # - for dynamic libraries, LTO is used on non-Apple platforms.
  # - for static libraries, including Rust backend
  #   LTO is disabled.
  #
  #   To retain performance partial linking can used via
  #   "-s -flinker-output=nolto-rel"
  #   with an extra C compiler call
  #   to consolidate all objects into one.
  let ltoFlags = " -d:lto " & # " -d:UseAsmSyntaxIntel --passC:-flto=auto --passL:-flto=auto "
                 # With LTO, the GCC linker produces lots of spurious warnings when copying into openArrays/strings
                 " --passC:-Wno-stringop-overflow --passL:-Wno-stringop-overflow " &
                 " --passC:-Wno-alloc-size-larger-than --passL:-Wno-alloc-size-larger-than "

  let apple = defined(macos) or defined(macosx) or defined(ios)
  let ltoOptions = if useLtoDefault:
                     if apple: ""
                     elif buildMode == bmStaticLib: ""
                     else: ltoFlags
                   elif forceLto: ltoFlags
                   else: ""

  let osSpecific =
    if defined(windows): "" # " --passC:-mno-stack-arg-probe "
      # Remove the auto __chkstk, which are: 1. slower, 2. not supported on Rust "stable-gnu" channel.
      # However functions that uses a large stack like `sum_reduce_vartime` become incorrect.
      # Hence deactivated by default.
    else: ""

  let threadLocalStorage = " --tlsEmulation=off "

  compiler &
    envASM & env32 &
    ltoOptions &
    osSpecific &
    threadLocalStorage &
    compilerFlags()

proc genDynamicLib(outdir, nimcache: string) =
  proc compile(libName: string, flags = "") =
    echo &"Compiling dynamic library: {outdir}/" & libName

    let config = flags &
                 releaseBuildOptions(bmDynamicLib)
    echo &"  compiler config: {config}"

    exec "nim c " &
         config &
         " --threads:on " &
         " --noMain --app:lib " &
         &" --nimMainPrefix:ctt_init_ " & # Constantine is designed so that NimMain isn't needed, provided --mm:arc -d:useMalloc --panics:on -d:noSignalHandler
         &" --out:{libName} --outdir:{outdir} " &
         &" --nimcache:{nimcache}/libconstantine_dynamic" &
         &" bindings/lib_constantine.nim"

  when defined(windows):
    compile "constantine.dll"

  elif defined(macosx) or defined(macos):
    compile "libconstantine.dylib.arm", "--cpu:arm64 -l:'-target arm64-apple-macos11' -t:'-target arm64-apple-macos11'"
    compile "libconstantine.dylib.x64", "--cpu:amd64 -l:'-target x86_64-apple-macos10.12' -t:'-target x86_64-apple-macos10.12'"
    exec &"lipo {outdir}/libconstantine.dylib.arm " &
             &" {outdir}/libconstantine.dylib.x64 " &
             &" -output {outdir}/libconstantine.dylib -create"

  else:
    compile "libconstantine.so"

proc genStaticLib(outdir, nimcache: string, extFlags = "") =
  proc compile(libName: string, flags = "") =
    echo &"Compiling static library:  {outdir}/" & libName

    let config = flags &
                 extFlags &
                 releaseBuildOptions(bmStaticLib)

    echo &"  compiler config: {config}"

    exec "nim c " &
         config &
         " --threads:on " &
         " --noMain --app:staticlib " &
         &" --nimMainPrefix:ctt_init_ " & # Constantine is designed so that NimMain isn't needed, provided --mm:arc -d:useMalloc --panics:on -d:noSignalHandler
         &" --out:{libName} --outdir:{outdir} " &
         &" --nimcache:{nimcache}/libconstantine_static" &
         &" bindings/lib_constantine.nim"

  when defined(windows):
    compile "constantine.lib"

  elif defined(macosx) or defined(macos):
    compile "libconstantine.a.arm", "--cpu:arm64 -l:'-target arm64-apple-macos11' -t:'-target arm64-apple-macos11'"
    compile "libconstantine.a.x64", "--cpu:amd64 -l:'-target x86_64-apple-macos10.12' -t:'-target x86_64-apple-macos10.12'"
    exec &"lipo {outdir}/libconstantine.a.arm " &
             &" {outdir}/libconstantine.a.x64 " &
             &" -output {outdir}/libconstantine.a -create"

  else:
    compile "libconstantine.a"

task make_headers, "Regenerate Constantine headers":
  exec "nim c -r -d:CTT_MAKE_HEADERS " &
       " -d:release " &
       " --threads:on " &
       " --verbosity:0 --hints:off --warnings:off " &
       " --outdir:build/make " &
       " --nimcache:nimcache/libcurves_headers " &
       " bindings/lib_headers.nim"

task make_lib, "Build Constantine library":
  genStaticLib("lib", "nimcache")
  genDynamicLib("lib", "nimcache")

task make_lib_rust, "Build Constantine library (use within a Rust build.rs script)":
  doAssert existsEnv"OUT_DIR", "Cargo needs to set the \"OUT_DIR\" environment variable"
  let rustOutDir = getEnv"OUT_DIR"
  # Compile as position independent, since rust does the same by default
  let extflags = if defined(windows): "" # Windows is fully position independent, flag is a no-op or on error depending on compiler.
                 else: "--passC:-fPIC"
  genStaticLib(rustOutDir, rustOutDir/"nimcache", extflags)

task make_zkalc, "Build a benchmark executable for zkalc (with Clang)":
  exec "nim c --cc:clang " &
       releaseBuildOptions(bmBinary) &
       " --threads:on " &
       " --out:bin/constantine-bench-zkalc " &
       " --nimcache:nimcache/bench_zkalc " &
       " benchmarks/zkalc.nim"

proc testLib(path, testName: string, useGMP: bool) =
  let dynlibName = if defined(windows): "constantine.dll"
                   elif defined(macosx) or defined(macos): "libconstantine.dylib"
                   else: "libconstantine.so"
  let staticlibName = if defined(windows): "constantine.lib"
                      else: "libconstantine.a"

  let cc = if existsEnv"CC": getEnv"CC"
           else: "gcc"

  echo &"\n[Test: {path}/{testName}.c] Testing dynamic library {dynlibName}"
  exec &"{cc} -Iinclude -Llib -o build/test_lib/{testName}_dynlink.exe {path}/{testName}.c -lconstantine " & (if useGMP: "-lgmp" else: "")
  when defined(windows):
    # Put DLL near the exe as LD_LIBRARY_PATH doesn't work even in a POSIX compatible shell
    exec &"./build/test_lib/{testName}_dynlink.exe"
  else:
    exec &"LD_LIBRARY_PATH=lib ./build/test_lib/{testName}_dynlink.exe"
  echo ""

  echo &"\n[Test: {path}/{testName}.c] Testing static library: {staticlibName}"
  # Beware MacOS annoying linker with regards to static libraries
  # The following standard way cannot be used on MacOS
  # exec "gcc -Iinclude -Llib -o build/t_libctt_bls12_381_sl.exe examples-c/t_libctt_bls12_381.c -lgmp -Wl,-Bstatic -lconstantine -Wl,-Bdynamic"
  exec &"{cc} -Iinclude -o build/test_lib/{testName}_staticlink.exe {path}/{testName}.c lib/{staticlibName} " & (if useGMP: "-lgmp" else: "")
  exec &"./build/test_lib/{testName}_staticlink.exe"
  echo ""

task test_lib, "Test C library":
  exec "mkdir -p build/test_lib"
  testLib("examples-c", "t_libctt_bls12_381", useGMP = true)
  testLib("examples-c", "ethereum_bls_signatures", useGMP = false)
  testLib("tests"/"c_api", "t_threadpool", useGMP = false)

# Test config
# ----------------------------------------------------------------

const buildParallel = "build/test_suite_parallel.txt"

# Testing strategy: to reduce CI time we test leaf functionality
#   and skip testing codepath that would be exercised by leaves.
#   While debugging, relevant unit-test can be reactivated.
#   New features should stay on.
#   Code refactoring requires re-enabling the full suite.
#   Basic primitives should stay on to catch compiler regressions.
const testDesc: seq[tuple[path: string, useGMP: bool]] = @[

  # CSPRNG
  # ----------------------------------------------------------
  ("tests/t_csprngs.nim", false),

  # Hashing vs OpenSSL
  # ----------------------------------------------------------
  ("tests/t_hash_sha256_vs_openssl.nim", false), # skip OpenSSL tests on Windows

  # Ciphers
  # ----------------------------------------------------------
  ("tests/t_cipher_chacha20.nim", false),

  # Message Authentication Code
  # ----------------------------------------------------------
  ("tests/t_mac_poly1305.nim", false),
  ("tests/t_mac_hmac_sha256.nim", false),

  # KDF
  # ----------------------------------------------------------
  ("tests/t_kdf_hkdf.nim", false),

  # Primitives
  # ----------------------------------------------------------
  ("tests/primitives/t_primitives.nim", false),
  ("tests/primitives/t_primitives_extended_precision.nim", false),
  ("tests/primitives/t_io_unsaturated.nim", false),

  # Big ints
  # ----------------------------------------------------------
  ("tests/math_bigints/t_io_bigints.nim", false),
  # ("tests/math_bigints/t_bigints.nim", false),
  # ("tests/math_bigints/t_bigints_multimod.nim", false),
  ("tests/math_bigints/t_bigints_mul_vs_gmp.nim", true),
  # ("tests/math_bigints/t_bigints_mul_high_words_vs_gmp.nim", true),

  # Big ints - arbitrary precision
  # ----------------------------------------------------------
  ("tests/math_arbitrary_precision/t_bigints_mod.nim", false),
  ("tests/math_arbitrary_precision/t_bigints_mod_vs_gmp.nim", true),
  ("tests/math_arbitrary_precision/t_bigints_powmod_vs_gmp.nim", true),

  # Field
  # ----------------------------------------------------------
  ("tests/math_fields/t_io_fields", false),
  # ("tests/math_fields/t_finite_fields.nim", false),
  # ("tests/math_fields/t_finite_fields_conditional_arithmetic.nim", false),
  ("tests/math_fields/t_finite_fields_mulsquare.nim", false),
  ("tests/math_fields/t_finite_fields_sqrt.nim", false),
  ("tests/math_fields/t_finite_fields_powinv.nim", false),
  ("tests/math_fields/t_finite_fields_vs_gmp.nim", true),
  # ("tests/math_fields/t_fp_cubic_root.nim", false),

  # Double-precision finite fields
  # ----------------------------------------------------------
  # ("tests/math_fields/t_finite_fields_double_precision.nim", false),

  # Towers of extension fields
  # ----------------------------------------------------------
  # ("tests/math_extension_fields/t_fp2.nim", false),
  # ("tests/math_extension_fields/t_fp2_sqrt.nim", false),
  # ("tests/math_extension_fields/t_fp4.nim", false),
  # ("tests/math_extension_fields/t_fp6_bn254_nogami.nim", false),
  # ("tests/math_extension_fields/t_fp6_bn254_snarks.nim", false),
  # ("tests/math_extension_fields/t_fp6_bls12_377.nim", false),
  # ("tests/math_extension_fields/t_fp6_bls12_381.nim", false),
  # ("tests/math_extension_fields/t_fp6_bw6_761.nim", false),
  # ("tests/math_extension_fields/t_fp12_bn254_nogami.nim", false),
  # ("tests/math_extension_fields/t_fp12_bn254_snarks.nim", false),
  # ("tests/math_extension_fields/t_fp12_bls12_377.nim", false),
  # ("tests/math_extension_fields/t_fp12_bls12_381.nim", false),
  # ("tests/math_extension_fields/t_fp12_exponentiation.nim", false),
  ("tests/math_extension_fields/t_fp12_anti_regression.nim", false),

  # ("tests/math_extension_fields/t_fp4_frobenius.nim", false),
  # ("tests/math_extension_fields/t_fp6_frobenius.nim", false),
  # ("tests/math_extension_fields/t_fp12_frobenius.nim", false),

  # Elliptic curve arithmetic
  # ----------------------------------------------------------
  ("tests/math_elliptic_curves/t_ec_conversion.nim", false),

  # Elliptic curve arithmetic 𝔾₁
  # ----------------------------------------------------------
  ("tests/math_elliptic_curves/t_ec_shortw_prj_g1_add_double.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g1_mul_sanity.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g1_mul_distri.nim", false),
  ("tests/math_elliptic_curves/t_ec_shortw_prj_g1_mul_vs_ref.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g1_mixed_add.nim", false),

  ("tests/math_elliptic_curves/t_ec_shortw_jac_g1_add_double.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g1_mul_sanity.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g1_mul_distri.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g1_mul_vs_ref.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g1_mixed_add.nim", false),

  ("tests/math_elliptic_curves/t_ec_shortw_jacext_g1_add_double.nim", false),
  ("tests/math_elliptic_curves/t_ec_shortw_jacext_g1_mixed_add.nim", false),

  # ("tests/math_elliptic_curves/t_ec_twedw_prj_add_double", false),
  # ("tests/math_elliptic_curves/t_ec_twedw_prj_mul_sanity", false),
  ("tests/math_elliptic_curves/t_ec_twedw_prj_mul_distri", false),

  ("tests/math_elliptic_curves/t_ec_shortw_jac_g1_mul_endomorphism_bls12_381", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g1_mul_endomorphism_bls12_381", false),
  ("tests/math_elliptic_curves/t_ec_shortw_jac_g1_mul_endomorphism_bn254_snarks", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g1_mul_endomorphism_bn254_snarks", false),
  ("tests/math_elliptic_curves/t_ec_twedwards_mul_endomorphism_bandersnatch", false),


  # Elliptic curve arithmetic 𝔾₂
  # ----------------------------------------------------------
  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g2_add_double_bn254_snarks.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g2_mul_sanity_bn254_snarks.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g2_mul_distri_bn254_snarks.nim", false),
  ("tests/math_elliptic_curves/t_ec_shortw_prj_g2_mul_vs_ref_bn254_snarks.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g2_mixed_add_bn254_snarks.nim", false),

  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g2_add_double_bls12_381.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g2_mul_sanity_bls12_381.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g2_mul_distri_bls12_381.nim", false),
  ("tests/math_elliptic_curves/t_ec_shortw_prj_g2_mul_vs_ref_bls12_381.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g2_mixed_add_bls12_381.nim", false),

  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g2_add_double_bls12_377.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g2_mul_sanity_bls12_377.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g2_mul_distri_bls12_377.nim", false),
  ("tests/math_elliptic_curves/t_ec_shortw_prj_g2_mul_vs_ref_bls12_377.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g2_mixed_add_bls12_377.nim", false),

  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g2_add_double_bw6_761.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g2_mul_sanity_bw6_761.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g2_mul_distri_bw6_761.nim", false),
  ("tests/math_elliptic_curves/t_ec_shortw_prj_g2_mul_vs_ref_bw6_761.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g2_mixed_add_bw6_761.nim", false),

  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_add_double_bn254_snarks.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_mul_sanity_bn254_snarks.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_mul_distri_bn254_snarks.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_mul_vs_ref_bn254_snarks.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_mixed_add_bn254_snarks.nim", false),

  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_add_double_bls12_381.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_mul_sanity_bls12_381.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_mul_distri_bls12_381.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_mul_vs_ref_bls12_381.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_mixed_add_bls12_381.nim", false),

  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_add_double_bls12_377.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_mul_sanity_bls12_377.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_mul_distri_bls12_377.nim", false),
  ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_mul_vs_ref_bls12_377.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_mixed_add_bls12_377.nim", false),

  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_add_double_bw6_761.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_mul_sanity_bw6_761.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_mul_distri_bw6_761.nim", false),
  ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_mul_vs_ref_bw6_761.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_mixed_add_bw6_761.nim", false),

  ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_mul_endomorphism_bls12_381", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g2_mul_endomorphism_bls12_381", false),
  ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_mul_endomorphism_bn254_snarks", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g2_mul_endomorphism_bn254_snarks", false),

  # Elliptic curve arithmetic vs Sagemath
  # ----------------------------------------------------------
  ("tests/math_elliptic_curves/t_ec_frobenius.nim", false),
  ("tests/math_elliptic_curves/t_ec_sage_bn254_nogami.nim", false),
  ("tests/math_elliptic_curves/t_ec_sage_bn254_snarks.nim", false),
  ("tests/math_elliptic_curves/t_ec_sage_bls12_377.nim", false),
  ("tests/math_elliptic_curves/t_ec_sage_bls12_381.nim", false),
  ("tests/math_elliptic_curves/t_ec_sage_pallas.nim", false),
  ("tests/math_elliptic_curves/t_ec_sage_vesta.nim", false),
  ("tests/math_elliptic_curves/t_ec_sage_secp256k1.nim", false),

  # Edge cases highlighted by past bugs
  # ----------------------------------------------------------
  ("tests/math_elliptic_curves/t_ec_shortw_prj_edge_cases.nim", false),
  ("tests/math_elliptic_curves/t_ec_shortw_prj_edge_case_345.nim", false),

  # Elliptic curve arithmetic - batch computation
  # ----------------------------------------------------------
  ("tests/math_elliptic_curves/t_ec_shortw_prj_g1_sum_reduce.nim", false),
  ("tests/math_elliptic_curves/t_ec_shortw_jac_g1_sum_reduce.nim", false),
  ("tests/math_elliptic_curves/t_ec_shortw_jacext_g1_sum_reduce.nim", false),
  ("tests/math_elliptic_curves/t_ec_shortw_prj_g1_msm.nim", false),
  ("tests/math_elliptic_curves/t_ec_shortw_jac_g1_msm.nim", false),
  ("tests/math_elliptic_curves/t_ec_twedw_prj_msm.nim", false),
  ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_msm_bug_366.nim", false),

  # Subgroups and cofactors
  # ----------------------------------------------------------
  # ("tests/math_elliptic_curves/t_ec_subgroups_bn254_nogami.nim", false),
  # ("tests/math_elliptic_curves/t_ec_subgroups_bn254_snarks.nim", false),
  # ("tests/math_elliptic_curves/t_ec_subgroups_bls12_377.nim", false),
  # ("tests/math_elliptic_curves/t_ec_subgroups_bls12_381.nim", false),

  # ("tests/math_pairings/t_pairing_bn254_nogami_gt_subgroup.nim", false),
  # ("tests/math_pairings/t_pairing_bn254_snarks_gt_subgroup.nim", false),
  # ("tests/math_pairings/t_pairing_bls12_377_gt_subgroup.nim", false),
  # ("tests/math_pairings/t_pairing_bls12_381_gt_subgroup.nim", false),
  # ("tests/math_pairings/t_pairing_bw6_761_gt_subgroup.nim", false),

  # Pairing &
  # ----------------------------------------------------------
  # ("tests/math_pairings/t_pairing_bls12_377_line_functions.nim", false),
  # ("tests/math_pairings/t_pairing_bls12_381_line_functions.nim", false),
  # ("tests/math_pairings/t_pairing_mul_fp12_by_lines.nim", false),
  ("tests/math_pairings/t_pairing_cyclotomic_subgroup.nim", false),
  # ("tests/math_pairings/t_pairing_bn254_nogami_optate.nim", false),
  # ("tests/math_pairings/t_pairing_bn254_snarks_optate.nim", false),
  # ("tests/math_pairings/t_pairing_bls12_377_optate.nim", false),
  # ("tests/math_pairings/t_pairing_bls12_381_optate.nim", false),

  ("tests/math_pairings/t_pairing_bn254_snarks_gt_exp.nim", false),
  ("tests/math_pairings/t_pairing_bls12_381_gt_exp.nim", false),

  # Multi-Pairing
  # ----------------------------------------------------------
  ("tests/math_pairings/t_pairing_bn254_nogami_multi.nim", false),
  ("tests/math_pairings/t_pairing_bn254_snarks_multi.nim", false),
  ("tests/math_pairings/t_pairing_bls12_377_multi.nim", false),
  ("tests/math_pairings/t_pairing_bls12_381_multi.nim", false),

  # Prime order fields
  # ----------------------------------------------------------
  ("tests/math_fields/t_fr.nim", false),

  # Hashing to elliptic curves
  # ----------------------------------------------------------
  # ("tests/t_hash_to_field.nim", false),
  ("tests/t_hash_to_curve_random.nim", false),
  ("tests/t_hash_to_curve.nim", false),

  # Polynomials
  # ----------------------------------------------------------
  ("tests/math_polynomials/t_polynomials.nim", false),

  # Protocols
  # ----------------------------------------------------------
  ("tests/t_ethereum_evm_modexp.nim", false),
  ("tests/t_ethereum_evm_precompiles.nim", false),
  ("tests/t_ethereum_bls_signatures.nim", false),
  ("tests/t_ethereum_eip2333_bls12381_key_derivation.nim", false),
  ("tests/t_ethereum_eip4844_deneb_kzg.nim", false),
  ("tests/t_ethereum_eip4844_deneb_kzg_parallel.nim", false),
  ("tests/t_ethereum_verkle_primitives.nim", false),
  ("tests/t_ethereum_verkle_ipa_primitives.nim", false),

  # Proof systems
  # ----------------------------------------------------------
  ("tests/proof_systems/t_r1cs_parser.nim", false),
  ("tests/interactive_proofs/t_multilinear_extensions.nim", false),
]

const testDescNvidia: seq[string] = @[
  "tests/gpu/t_nvidia_fp.nim",
]

const testDescThreadpool: seq[string] = @[
  "examples-threadpool/e01_simple_tasks.nim",
  "examples-threadpool/e02_parallel_pi.nim",
  "examples-threadpool/e03_parallel_for.nim",
  "examples-threadpool/e04_parallel_reduce.nim",
  # "benchmarks-threadpool/bouncing_producer_consumer/threadpool_bpc.nim", # Need timing not implemented on Windows
  "benchmarks-threadpool/dfs/threadpool_dfs.nim",
  "benchmarks-threadpool/fibonacci/threadpool_fib.nim",
  "benchmarks-threadpool/heat/threadpool_heat.nim",
  # "benchmarks-threadpool/matmul_cache_oblivious/threadpool_matmul_co.nim",
  "benchmarks-threadpool/nqueens/threadpool_nqueens.nim",
  # "benchmarks-threadpool/single_task_producer/threadpool_spc.nim", # Need timing not implemented on Windows
  # "benchmarks-threadpool/black_scholes/threadpool_black_scholes.nim", # Need input file
  "benchmarks-threadpool/matrix_transposition/threadpool_transposes.nim",
  "benchmarks-threadpool/histogram_2D/threadpool_histogram.nim",
  "benchmarks-threadpool/logsumexp/threadpool_logsumexp.nim",
]

const testDescMultithreadedCrypto: seq[string] = @[
  "tests/parallel/t_ec_shortw_jac_g1_batch_add_parallel.nim",
  "tests/parallel/t_ec_shortw_prj_g1_batch_add_parallel.nim",
  "tests/parallel/t_ec_shortw_jac_g1_msm_parallel.nim",
  "tests/parallel/t_ec_shortw_prj_g1_msm_parallel.nim",
  "tests/parallel/t_ec_twedwards_prj_msm_parallel.nim",
  "tests/parallel/t_pairing_bls12_381_gt_multiexp_parallel.nim",
]

const benchDesc = [
  "bench_fp",
  "bench_fp_double_precision",
  "bench_fp2",
  "bench_fp4",
  "bench_fp6",
  "bench_fp12",
  "bench_ec_g1",
  "bench_ec_g1_scalar_mul",
  "bench_ec_g1_batch",
  "bench_ec_msm_bandersnatch",
  "bench_ec_msm_bn254_snarks_g1",
  "bench_ec_msm_bls12_381_g1",
  "bench_ec_msm_bls12_381_g2",
  "bench_ec_msm_pasta",
  "bench_ec_g2",
  "bench_ec_g2_scalar_mul",
  "bench_pairing_bls12_377",
  "bench_pairing_bls12_381",
  "bench_pairing_bn254_nogami",
  "bench_pairing_bn254_snarks",
  "bench_gt",
  "bench_gt_multiexp_bls12_381",
  "bench_summary_bls12_377",
  "bench_summary_bls12_381",
  "bench_summary_bn254_nogami",
  "bench_summary_bn254_snarks",
  "bench_summary_pasta",
  "bench_poly1305",
  "bench_sha256",
  "bench_hash_to_curve",
  "bench_gmp_modexp",
  "bench_gmp_modmul",
  "bench_eth_bls_signatures",
  "bench_eth_eip4844_kzg",
  "bench_eth_evm_modexp_dos",
  "bench_eth_eip2537_subgroup_checks_impact",
  "bench_verkle_primitives",
  "bench_eth_evm_precompiles",
  "bench_multilinear_extensions",
  # "zkalc", # Already tested through make_zkalc
]

# For temporary (hopefully) investigation that can only be reproduced in CI
const useDebug = [
  "tests/math_bigints/t_bigints.nim",
  "tests/t_hash_sha256_vs_openssl.nim",
]

# Skip stack hardening for specific tests
const skipStackHardening = [
  "tests/t_"
]
# use sanitizers for specific tests
const useSanitizers = [
  "tests/math_arbitrary_precision/t_bigints_powmod_vs_gmp.nim",
  "tests/t_ethereum_evm_modexp.nim",
  "tests/t_etherem_evm_precompiles.nim",
]

when defined(windows):
  # UBSAN is not available on mingw
  # https://github.com/libressl-portable/portable/issues/54
  const sanitizers = ""
  const stackHardening = ""
else:
  const stackHardening =

    " --passC:-fstack-protector-strong " &

    # Fortify source wouldn't help us detect errors in Constantine
    # because everything is stack allocated
    # except with the threadpool:
    # - https://developers.redhat.com/blog/2021/04/16/broadening-compiler-checks-for-buffer-overflows-in-_fortify_source#what_s_next_for__fortify_source
    # - https://developers.redhat.com/articles/2023/02/06/how-improve-application-security-using-fortifysource3#how_to_improve_application_fortification
    # We also don't use memcpy as it is not constant-time and our copy is compile-time sized.

    " --passC:-D_FORTIFY_SOURCE=3 "

  const sanitizers =

    # Sanitizers are incompatible with nim default GC
    # The conservative stack scanning of Nim default GC triggers, alignment UB and stack-buffer-overflow check.
    # Address sanitizer requires free registers and needs to be disabled for some inline assembly files.
    # Ensure you use --mm:arc -d:useMalloc
    #
    # Sanitizers are deactivated by default as they slow down CI by at least 6x

    " --mm:arc -d:useMalloc" &
    " --passC:-fsanitize=undefined --passL:-fsanitize=undefined" &
    " --passC:-fsanitize=address --passL:-fsanitize=address" &
    " --passC:-fno-sanitize-recover" # Enforce crash on undefined behaviour

# Tests & Benchmarks helper functions
# ----------------------------------------------------------------

proc clearParallelBuild() =
  # Support clearing from non POSIX shell like CMD, Powershell or MSYS2
  if fileExists(buildParallel):
    rmFile(buildParallel)

proc setupTestCommand(flags, path: string): string =
  var lang = "c"
  if existsEnv"TEST_LANG":
    lang = getEnv"TEST_LANG"

  return "nim " & lang &
    " -r " &
    flags &
    releaseBuildOptions() &
    " --outdir:build/test_suite " &
    &" --nimcache:nimcache/{path} " &
    path

proc test(cmd: string) =
  echo "\n=============================================================================================="
  echo "Running '", cmd, "'"
  echo "=============================================================================================="
  exec cmd

proc testBatch(commands: var string, flags, path: string) =
  commands = commands & setupTestCommand(flags, path) & '\n'

proc setupBench(benchName: string, run: bool): string =
  var runFlags = " "
  if run: # Beware of https://github.com/nim-lang/Nim/issues/21704
    runFlags = runFlags & " -r "

  let asmStatus = if getEnvVars().useAsmIfAble: "asmIfAvailable" else: "noAsm"

  let cc = if existsEnv"CC": getEnv"CC"
           else: "defaultcompiler"

  return "nim c " &
       runFlags &
       releaseBuildOptions() &
       &" -o:build/bench/{benchName}_{cc}_{asmStatus}" &
       &" --nimcache:nimcache/benches/{benchName}_{cc}_{asmStatus}" &
       &" benchmarks/{benchName}.nim"

proc runBench(benchName: string) =
  if not dirExists "build":
    mkDir "build"
  let command = setupBench(benchName, run = true)
  exec command

proc buildBenchBatch(commands: var string, benchName: string) =
  let command = setupBench(benchName, run = false)
  commands = commands & command & '\n'

proc addTestSet(cmdFile: var string, requireGMP: bool) =
  if not dirExists "build":
    mkDir "build"
  echo "Found " & $testDesc.len & " tests to run."

  for td in testDesc:
    if not(td.useGMP and not requireGMP):
      var flags = "" # Beware of https://github.com/nim-lang/Nim/issues/21704
      if td.path in useDebug:
        flags = flags & " -d:CTT_DEBUG "
      if td.path notin skipStackHardening:
        flags = flags & stackHardening
      if td.path in useSanitizers:
        flags = flags & sanitizers

      cmdFile.testBatch(flags, td.path)

proc addTestSetNvidia(cmdFile: var string) =
  if not dirExists "build":
    mkDir "build"
  echo "Found " & $testDescNvidia.len & " tests to run."

  for path in testDescNvidia:
    var flags = "" # Beware of https://github.com/nim-lang/Nim/issues/21704
    if path notin skipStackHardening:
      flags = flags & stackHardening
    if path in useSanitizers:
      flags = flags & sanitizers
    cmdFile.testBatch(flags, path)

proc addTestSetThreadpool(cmdFile: var string) =
  if not dirExists "build":
    mkDir "build"
  echo "Found " & $testDescThreadpool.len & " tests to run."

  for path in testDescThreadpool:
    var flags = " --threads:on --debugger:native "
    if path notin skipStackHardening:
      flags = flags & stackHardening
    if path in useSanitizers:
      flags = flags & sanitizers
    cmdFile.testBatch(flags, path)

proc addTestSetMultithreadedCrypto(cmdFile: var string) =
  if not dirExists "build":
    mkDir "build"
  echo "Found " & $testDescMultithreadedCrypto.len & " tests to run."

  for td in testDescMultithreadedCrypto:
    var flags = " --threads:on --debugger:native"
    if td in useDebug:
      flags = flags & " -d:CTT_DEBUG "
    if td notin skipStackHardening:
      flags = flags & stackHardening
    if td in useSanitizers:
      flags = flags & sanitizers
    cmdFile.testBatch(flags, td)

proc addBenchSet(cmdFile: var string) =
  if not dirExists "build":
    mkDir "build"
  echo "Found " & $benchDesc.len & " benches to compile. (compile-only to ensure they stay relevant)"
  for bd in benchDesc:
    cmdFile.buildBenchBatch(bd)

proc genParallelCmdRunner() =
  exec "nim c --verbosity:0 --hints:off --warnings:off -d:release --out:build/test_suite/pararun --nimcache:nimcache/test_suite/pararun helpers/pararun.nim"

# Tasks
# ----------------------------------------------------------------

task test, "Run all tests":
  # -d:CTT_TEST_CURVES is configured in a *.nim.cfg for convenience
  var cmdFile: string
  cmdFile.addTestSet(requireGMP = true)
  cmdFile.addBenchSet()    # Build (but don't run) benches to ensure they stay relevant
  cmdFile.addTestSetThreadpool()
  cmdFile.addTestSetMultithreadedCrypto()
  for cmd in cmdFile.splitLines():
    if cmd != "": # Windows doesn't like empty commands
      exec cmd

task test_no_gmp, "Run tests that don't require GMP":
  # -d:CTT_TEST_CURVES is configured in a *.nim.cfg for convenience
  var cmdFile: string
  cmdFile.addTestSet(requireGMP = false)
  cmdFile.addBenchSet()    # Build (but don't run) benches to ensure they stay relevant
  cmdFile.addTestSetThreadpool()
  cmdFile.addTestSetMultithreadedCrypto()
  for cmd in cmdFile.splitLines():
    if cmd != "": # Windows doesn't like empty commands
      exec cmd

task test_parallel, "Run all tests in parallel":
  # -d:CTT_TEST_CURVES is configured in a *.nim.cfg for convenience
  clearParallelBuild()
  genParallelCmdRunner()

  var cmdFile: string
  cmdFile.addTestSet(requireGMP = true)
  cmdFile.addBenchSet()    # Build (but don't run) benches to ensure they stay relevant
  writeFile(buildParallel, cmdFile)
  exec "build/test_suite/pararun " & buildParallel

  # Threadpool tests done serially
  cmdFile = ""
  cmdFile.addTestSetThreadpool()
  cmdFile.addTestSetMultithreadedCrypto()
  for cmd in cmdFile.splitLines():
    if cmd != "": # Windows doesn't like empty commands
      exec cmd

task test_parallel_no_gmp, "Run in parallel tests that don't require GMP":
  # -d:CTT_TEST_CURVES is configured in a *.nim.cfg for convenience
  clearParallelBuild()
  genParallelCmdRunner()

  var cmdFile: string
  cmdFile.addTestSet(requireGMP = false)
  cmdFile.addBenchSet()    # Build (but don't run) benches to ensure they stay relevant
  writeFile(buildParallel, cmdFile)
  exec "build/test_suite/pararun " & buildParallel

  # Threadpool tests done serially
  cmdFile = ""
  cmdFile.addTestSetThreadpool()
  cmdFile.addTestSetMultithreadedCrypto()
  for cmd in cmdFile.splitLines():
    if cmd != "": # Windows doesn't like empty commands
      exec cmd

task test_threadpool, "Run all tests for the builtin threadpool":
  var cmdFile: string
  cmdFile.addTestSetThreadpool()
  for cmd in cmdFile.splitLines():
    if cmd != "": # Windows doesn't like empty commands
      exec cmd

task test_multithreaded_crypto, "Run all tests for multithreaded cryptography":
  var cmdFile: string
  cmdFile.addTestSetMultithreadedCrypto()
  for cmd in cmdFile.splitLines():
    if cmd != "": # Windows doesn't like empty commands
      exec cmd

task test_nvidia, "Run all tests for Nvidia GPUs":
  var cmdFile: string
  cmdFile.addTestSetNvidia()
  for cmd in cmdFile.splitLines():
    if cmd != "": # Windows doesn't like empty commands
      exec cmd

# BigInt benchmark
# ------------------------------------------

task bench_powmod, "Run modular exponentiation benchmark with your CC compiler":
  runBench("bench_powmod")

task bench_gmp_modmul, "Run modular multiplication benchmarks vs GMP":
  runBench("bench_gmp_modmul")

task bench_gmp_modexp, "Run modular exponentiation benchmarks vs GMP":
  runBench("bench_gmp_modexp")

# Finite field 𝔽p
# ------------------------------------------

task bench_fp, "Run benchmark 𝔽p with your CC compiler":
  runBench("bench_fp")

# Double-precision field 𝔽pDbl
# ------------------------------------------

task bench_fpdbl, "Run benchmark 𝔽pDbl with your CC compiler":
  runBench("bench_fp_double_precision")

# Extension field 𝔽p2
# ------------------------------------------

task bench_fp2, "Run benchmark 𝔽p2 with your CC compiler":
  runBench("bench_fp2")

# Extension field 𝔽p4
# ------------------------------------------

task bench_fp4, "Run benchmark 𝔽p4 with your CC compiler":
  runBench("bench_fp4")

# Extension field 𝔽p6
# ------------------------------------------

task bench_fp6, "Run benchmark 𝔽p6 with your CC compiler":
  runBench("bench_fp6")

# Extension field 𝔽p12
# ------------------------------------------

task bench_fp12, "Run benchmark 𝔽p12 with your CC compiler":
  runBench("bench_fp12")

# Elliptic curve 𝔾₁
# ------------------------------------------

task bench_ec_g1, "Run benchmark on Elliptic Curve group 𝔾1 - CC compiler":
  runBench("bench_ec_g1")

# Elliptic curve 𝔾₁ - batch operations
# ------------------------------------------

task bench_ec_g1_batch, "Run benchmark on Elliptic Curve group 𝔾1 (batch ops) - CC compiler":
  runBench("bench_ec_g1_batch")

# Elliptic curve 𝔾₁ - scalar multiplication
# ------------------------------------------

task bench_ec_g1_scalar_mul, "Run benchmark on Elliptic Curve group 𝔾1 (Scalar Multiplication) - CC compiler":
  runBench("bench_ec_g1_scalar_mul")

# Elliptic curve 𝔾₁ - Multi-scalar-mul
# ------------------------------------------

task bench_ec_msm_pasta, "Run benchmark: Multi-Scalar-Mul for Pasta curves - CC compiler":
  runBench("bench_ec_msm_pasta")

task bench_ec_msm_bn254_snarks_g1, "Run benchmark: Multi-Scalar-Mul for BN254-Snarks 𝔾1 - CC compiler":
  runBench("bench_ec_msm_bn254_snarks_g1")

task bench_ec_msm_bls12_381_g1, "Run benchmark: Multi-Scalar-Mul for BLS12-381 𝔾1 - CC compiler":
  runBench("bench_ec_msm_bls12_381_g1")

task bench_ec_msm_bls12_381_g2, "Run benchmark: Multi-Scalar-Mul for BLS12-381 𝔾2 - CC compiler":
  runBench("bench_ec_msm_bls12_381_g2")

task bench_ec_msm_bandersnatch, "Run benchmark: Multi-Scalar-Mul for Bandersnatch - CC compiler":
  runBench("bench_ec_msm_bandersnatch")


# Elliptic curve 𝔾₂
# ------------------------------------------

task bench_ec_g2, "Run benchmark on Elliptic Curve group 𝔾2 - CC compiler":
  runBench("bench_ec_g2")

# Elliptic curve 𝔾₂ - scalar multiplication
# ------------------------------------------

task bench_ec_g2_scalar_mul, "Run benchmark on Elliptic Curve group 𝔾2 (Multi-Scalar-Mul) - CC compiler":
  runBench("bench_ec_g2_scalar_mul")

# 𝔾ₜ
# ------------------------------------------

task bench_gt, "Run 𝔾ₜ benchmarks - CC compiler":
  runBench("bench_gt")

# 𝔾ₜ - multi-exponentiation
# ------------------------------------------

task bench_gt_multiexp_bls12_381, "Run 𝔾ₜ multiexponentiation benchmarks for BLS12-381 - CC compiler":
  runBench("bench_gt_multiexp_bls12_381")

# Pairings
# ------------------------------------------

task bench_pairing_bls12_377, "Run pairings benchmarks for BLS12-377 - CC compiler":
  runBench("bench_pairing_bls12_377")

# --

task bench_pairing_bls12_381, "Run pairings benchmarks for BLS12-381 - CC compiler":
  runBench("bench_pairing_bls12_381")

# --

task bench_pairing_bn254_nogami, "Run pairings benchmarks for BN254-Nogami - CC compiler":
  runBench("bench_pairing_bn254_nogami")

# --

task bench_pairing_bn254_snarks, "Run pairings benchmarks for BN254-Snarks - CC compiler":
  runBench("bench_pairing_bn254_snarks")

# Curve summaries
# ------------------------------------------

task bench_summary_bls12_377, "Run summary benchmarks for BLS12-377 - CC compiler":
  runBench("bench_summary_bls12_377")

# --

task bench_summary_bls12_381, "Run summary benchmarks for BLS12-381 - CC compiler":
  runBench("bench_summary_bls12_381")

# --

task bench_summary_bn254_nogami, "Run summary benchmarks for BN254-Nogami - CC compiler":
  runBench("bench_summary_bn254_nogami")

# --

task bench_summary_bn254_snarks, "Run summary benchmarks for BN254-Snarks - CC compiler":
  runBench("bench_summary_bn254_snarks")

# --

task bench_summary_pasta, "Run summary benchmarks for the Pasta curves - CC compiler":
  runBench("bench_summary_pasta")

# Hashes
# ------------------------------------------

task bench_sha256, "Run SHA256 benchmarks":
  runBench("bench_sha256")

# Hash-to-curve
# ------------------------------------------
task bench_hash_to_curve, "Run Hash-to-Curve benchmarks":
  runBench("bench_hash_to_curve")

# BLS signatures
# ------------------------------------------
task bench_eth_bls_signatures, "Run Ethereum BLS signatures benchmarks - CC compiler":
  runBench("bench_eth_bls_signatures")

# EIP 4844 - KZG Polynomial Commitments
# ------------------------------------------
task bench_eth_eip4844_kzg, "Run Ethereum EIP4844 KZG Polynomial commitment - CC compiler":
  runBench("bench_eth_eip4844_kzg")

task bench_verkle, "Run benchmarks for Banderwagon":
  runBench("bench_verkle_primitives")

# EIP 2537 - BLS12-381 precompiles
# ------------------------------------------
task bench_eth_eip2537_subgroup_checks_impact, "Run EIP2537 subgroup checks impact benchmark - CC compiler":
  runBench("bench_eth_eip2537_subgroup_checks_impact")

# EVM
# ------------------------------------------
task bench_eth_evm_precompiles, "Run Ethereum EVM precompiles - CC compiler":
  runBench("bench_eth_evm_precompiles")
