packageName   = "constantine"
version       = "0.0.1"
author        = "Status Research & Development GmbH"
description   = "This library provides thoroughly tested and highly-optimized implementations of cryptography protocols."
license       = "MIT or Apache License 2.0"

# Dependencies
# ----------------------------------------------------------------

requires "nim >= 1.6.12"

# Nimscript imports
# ----------------------------------------------------------------

import std/strformat

# Library compilation
# ----------------------------------------------------------------

proc releaseBuildOptions(useASM, useLTO = true): string =
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
  #           This turns them into panics, removing exceptiosn from the library.
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
  let compiler = if existsEnv"CC": " --cc:" & getEnv"CC"
                 else: ""

  let noASM = if not useASM: " -d:CttASM=false "
              else: ""

  let lto = if useLTO: " --passC:-flto=auto --passL:-flto=auto "
            else: ""

  compiler &
  noASM &
  lto &
  " -d:danger " &
  # " --opt:size " &
  " --panics:on -d:noSignalHandler " &
  " --mm:arc -d:useMalloc " &
  " --verbosity:0 --hints:off --warnings:off " &
  " --passC:-fno-semantic-interposition " &
  " --passC:-falign-functions=64 "

type BindingsKind = enum
  kCurve
  kProtocol

proc genDynamicBindings(bindingsKind: BindingsKind, bindingsName, prefixNimMain: string, useASM = true) =
  proc compile(libName: string, flags = "") =
    echo "Compiling dynamic library: lib/" & libName

    exec "nim c " &
         flags &
         releaseBuildOptions(useASM, useLTO = true) &
         " --noMain --app:lib " &
         &" --nimMainPrefix:{prefixNimMain} " &
         &" --out:{libName} --outdir:lib " &
         (block:
           case bindingsKind
           of kCurve:
             &" --nimcache:nimcache/bindings_curves/{bindingsName}" &
             &" bindings_generators/{bindingsName}.nim"
           of kProtocol:
             &" --nimcache:nimcache/bindings_protocols/{bindingsName}" &
             &" constantine/{bindingsName}.nim")

  let bindingsName = block:
    case bindingsKind
    of kCurve: bindingsName
    of kProtocol: "constantine_" & bindingsName

  when defined(windows):
    compile bindingsName & ".dll"

  elif defined(macosx):
    compile "lib" & bindingsName & ".dylib.arm", "--cpu:arm64 -l:'-target arm64-apple-macos11' -t:'-target arm64-apple-macos11'"
    compile "lib" & bindingsName & ".dylib.x64", "--cpu:amd64 -l:'-target x86_64-apple-macos10.12' -t:'-target x86_64-apple-macos10.12'"
    exec "lipo lib/lib" & bindingsName & ".dylib.arm " &
             " lib/lib" & bindingsName & ".dylib.x64 " &
             " -output lib/lib" & bindingsName & ".dylib -create"

  else:
    compile "lib" & bindingsName & ".so"

proc genStaticBindings(bindingsKind: BindingsKind, bindingsName, prefixNimMain: string, useASM = true) =
  proc compile(libName: string, flags = "") =
    echo "Compiling static library:  lib/" & libName

    exec "nim c " &
         flags &
         releaseBuildOptions(useASM, useLTO = false) &
         " --noMain --app:staticLib " &
         &" --nimMainPrefix:{prefixNimMain} " &
         &" --out:{libName} --outdir:lib " &
         (block:
           case bindingsKind
           of kCurve:
             &" --nimcache:nimcache/bindings_curves/{bindingsName}" &
             &" bindings_generators/{bindingsName}.nim"
           of kProtocol:
             &" --nimcache:nimcache/bindings_protocols/{bindingsName}" &
             &" constantine/{bindingsName}.nim")

  let bindingsName = block:
    case bindingsKind
    of kCurve: bindingsName
    of kProtocol: "constantine_" & bindingsName

  when defined(windows):
    compile bindingsName & ".lib"

  elif defined(macosx):
    compile "lib" & bindingsName & ".a.arm", "--cpu:arm64 -l:'-target arm64-apple-macos11' -t:'-target arm64-apple-macos11'"
    compile "lib" & bindingsName & ".a.x64", "--cpu:amd64 -l:'-target x86_64-apple-macos10.12' -t:'-target x86_64-apple-macos10.12'"
    exec "lipo lib/lib" & bindingsName & ".a.arm " &
             " lib/lib" & bindingsName & ".a.x64 " &
             " -output lib/lib" & bindingsName & ".a -create"

  else:
    compile "lib" & bindingsName & ".a"

proc genHeaders(bindingsName: string) =
  echo "Generating header:         include/" & bindingsName & ".h"
  exec "nim c -d:CttGenerateHeaders " &
       " -d:release " &
       " --out:" & bindingsName & "_gen_header.exe --outdir:build " &
       " --nimcache:nimcache/bindings_curves_headers/" & bindingsName & "_header" &
       " bindings_generators/" & bindingsName & ".nim"
  exec "build/" & bindingsName & "_gen_header.exe include"

task bindings, "Generate Constantine bindings (no assembly)":
  # Curve arithmetic
  genStaticBindings(kCurve, "constantine_bls12_381", "ctt_bls12381_init_")
  genDynamicBindings(kCurve, "constantine_bls12_381", "ctt_bls12381_init_")
  genHeaders("constantine_bls12_381")
  echo ""
  genStaticBindings(kCurve, "constantine_pasta", "ctt_pasta_init_")
  genDynamicBindings(kCurve, "constantine_pasta", "ctt_pasta_init_")
  genHeaders("constantine_pasta")
  echo ""

  # Protocols
  genStaticBindings(kProtocol, "ethereum_bls_signatures", "ctt_eth_bls_init_")
  genDynamicBindings(kProtocol, "ethereum_bls_signatures", "ctt_eth_bls_init_")
  echo ""

task bindings_no_asm, "Generate Constantine bindings (no assembly)":
  # Curve arithmetic
  genStaticBindings(kCurve, "constantine_bls12_381", "ctt_bls12381_init_", useASM = false)
  genDynamicBindings(kCurve, "constantine_bls12_381", "ctt_bls12381_init_", useASM = false)
  genHeaders("constantine_bls12_381")
  echo ""
  genStaticBindings(kCurve, "constantine_pasta", "ctt_pasta_init_", useASM = false)
  genDynamicBindings(kCurve, "constantine_pasta", "ctt_pasta_init_", useASM = false)
  genHeaders("constantine_pasta")
  echo ""

  # Protocols
  genStaticBindings(kProtocol, "ethereum_bls_signatures", "ctt_eth_bls_init_", useASM = false)
  genDynamicBindings(kProtocol, "ethereum_bls_signatures", "ctt_eth_bls_init_", useASM = false)
  echo ""

proc testLib(path, testName, libName: string, useGMP: bool) =
  let dynlibName = if defined(windows): libName & ".dll"
                   elif defined(macosx): "lib" & libName & ".dylib"
                   else: "lib" & libName & ".so"
  let staticlibName = if defined(windows): libName & ".lib"
                      else: "lib" & libName & ".a"

  let cc = if existsEnv"CC": getEnv"CC"
           else: "gcc"

  echo &"\n[Bindings: {path}/{testName}.c] Testing dynamically linked library {dynlibName}"
  exec &"{cc} -Iinclude -Llib -o build/testbindings/{testName}_dynlink.exe {path}/{testName}.c -l{libName} " & (if useGMP: "-lgmp" else: "")
  when defined(windows):
    # Put DLL near the exe as LD_LIBRARY_PATH doesn't work even in a POSIX compatible shell
    exec &"./build/testbindings/{testName}_dynlink.exe"
  else:
    exec &"LD_LIBRARY_PATH=lib ./build/testbindings/{testName}_dynlink.exe"
  echo ""

  echo &"\n[Bindings: {path}/{testName}.c] Testing statically linked library: {staticlibName}"
  # Beware MacOS annoying linker with regards to static libraries
  # The following standard way cannot be used on MacOS
  # exec "gcc -Iinclude -Llib -o build/t_libctt_bls12_381_sl.exe examples_c/t_libctt_bls12_381.c -lgmp -Wl,-Bstatic -lconstantine_bls12_381 -Wl,-Bdynamic"
  exec &"{cc} -Iinclude -o build/testbindings/{testName}_staticlink.exe {path}/{testName}.c lib/{staticlibName} " & (if useGMP: "-lgmp" else: "")
  exec &"./build/testbindings/{testName}_staticlink.exe"
  echo ""

task test_bindings, "Test C bindings":
  exec "mkdir -p build/testbindings"
  testLib("examples_c", "t_libctt_bls12_381", "constantine_bls12_381", useGMP = true)
  testLib("examples_c", "ethereum_bls_signatures", "constantine_ethereum_bls_signatures", useGMP = false)

# Test config
# ----------------------------------------------------------------

const buildParallel = "test_parallel.txt"

# Testing strategy: to reduce CI time we test leaf functionality
#   and skip testing codepath that would be exercised by leaves.
#   While debugging, relevant unit-test can be reactivated.
#   New features should stay on.
#   Code refactoring requires re-enabling the full suite.
#   Basic primitives should stay on to catch compiler regressions.
const testDesc: seq[tuple[path: string, useGMP: bool]] = @[

  # Hashing vs OpenSSL
  # ----------------------------------------------------------
  ("tests/t_hash_sha256_vs_openssl.nim", true), # skip OpenSSL tests on Windows

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
  # ("tests/math_bigints/t_bigints_mod_vs_gmp.nim", true),
  # ("tests/math_bigints/t_bigints_mul_vs_gmp.nim", true),
  # ("tests/math_bigints/t_bigints_mul_high_words_vs_gmp.nim", true),

  # Field
  # ----------------------------------------------------------
  ("tests/math_fields/t_io_fields", false),
  # ("tests/math_fields/t_finite_fields.nim", false),
  # ("tests/math_fields/t_finite_fields_conditional_arithmetic.nim", false),
  # ("tests/math_fields/t_finite_fields_mulsquare.nim", false),
  # ("tests/math_fields/t_finite_fields_sqrt.nim", false),
  # ("tests/math_fields/t_finite_fields_powinv.nim", false),
  # ("tests/math_fields/t_finite_fields_vs_gmp.nim", true),
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
  # ("tests/math_elliptic_curves/t_ec_conversion.nim", false),

  # Elliptic curve arithmetic G1
  # ----------------------------------------------------------
  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g1_add_double.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g1_mul_sanity.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g1_mul_distri.nim", false),
  ("tests/math_elliptic_curves/t_ec_shortw_prj_g1_mul_vs_ref.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_prj_g1_mixed_add.nim", false),

  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g1_add_double.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g1_mul_sanity.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g1_mul_distri.nim", false),
  ("tests/math_elliptic_curves/t_ec_shortw_jac_g1_mul_vs_ref.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g1_mixed_add.nim", false),

  ("tests/math_elliptic_curves/t_ec_shortw_jacext_g1_add_double.nim", false),
  ("tests/math_elliptic_curves/t_ec_shortw_jacext_g1_mixed_add.nim", false),

  # ("tests/math_elliptic_curves/t_ec_twedwards_prj_add_double", false),
  # ("tests/math_elliptic_curves/t_ec_twedwards_prj_mul_sanity", false),
  # ("tests/math_elliptic_curves/t_ec_twedwards_prj_mul_distri", false),


  # Elliptic curve arithmetic G2
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
  ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_mul_vs_ref_bn254_snarks.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_mixed_add_bn254_snarks.nim", false),

  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_add_double_bls12_381.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_mul_sanity_bls12_381.nim", false),
  # ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_mul_distri_bls12_381.nim", false),
  ("tests/math_elliptic_curves/t_ec_shortw_jac_g2_mul_vs_ref_bls12_381.nim", false),
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

  # Elliptic curve arithmetic vs Sagemath
  # ----------------------------------------------------------
  ("tests/math_elliptic_curves/t_ec_frobenius.nim", false),
  ("tests/math_elliptic_curves/t_ec_sage_bn254_nogami.nim", false),
  ("tests/math_elliptic_curves/t_ec_sage_bn254_snarks.nim", false),
  ("tests/math_elliptic_curves/t_ec_sage_bls12_377.nim", false),
  ("tests/math_elliptic_curves/t_ec_sage_bls12_381.nim", false),
  ("tests/math_elliptic_curves/t_ec_sage_pallas.nim", false),
  ("tests/math_elliptic_curves/t_ec_sage_vesta.nim", false),

  # Edge cases highlighted by past bugs
  # ----------------------------------------------------------
  ("tests/math_elliptic_curves/t_ec_shortw_prj_edge_cases.nim", false),

  # Elliptic curve arithmetic - batch computation
  # ----------------------------------------------------------
  ("tests/math_elliptic_curves/t_ec_shortw_prj_g1_sum_reduce.nim", false),
  ("tests/math_elliptic_curves/t_ec_shortw_jac_g1_sum_reduce.nim", false),
  ("tests/math_elliptic_curves/t_ec_shortw_jacext_g1_sum_reduce.nim", false),
  ("tests/math_elliptic_curves/t_ec_shortw_prj_g1_msm.nim", false),
  ("tests/math_elliptic_curves/t_ec_shortw_jac_g1_msm.nim", false),

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

  # Pairing
  # ----------------------------------------------------------
  # ("tests/math_pairings/t_pairing_bls12_377_line_functions.nim", false),
  # ("tests/math_pairings/t_pairing_bls12_381_line_functions.nim", false),
  # ("tests/math_pairings/t_pairing_mul_fp12_by_lines.nim", false),
  ("tests/math_pairings/t_pairing_cyclotomic_subgroup.nim", false),
  ("tests/math_pairings/t_pairing_bn254_nogami_optate.nim", false),
  ("tests/math_pairings/t_pairing_bn254_snarks_optate.nim", false),
  ("tests/math_pairings/t_pairing_bls12_377_optate.nim", false),
  ("tests/math_pairings/t_pairing_bls12_381_optate.nim", false),

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
  ("tests/t_hash_to_field.nim", false),
  # ("tests/t_hash_to_curve_random.nim", false),
  ("tests/t_hash_to_curve.nim", false),

  # Protocols
  # ----------------------------------------------------------
  ("tests/t_ethereum_evm_precompiles.nim", false),
  ("tests/t_ethereum_bls_signatures.nim", false),
  ("tests/t_ethereum_eip2333_bls12381_key_derivation.nim", false),
]

const testDescNvidia: seq[string] = @[
  "tests/gpu/t_nvidia_fp.nim",
]

const testDescThreadpool: seq[string] = @[
  "constantine/platforms/threadpool/examples/e01_simple_tasks.nim",
  "constantine/platforms/threadpool/examples/e02_parallel_pi.nim",
  "constantine/platforms/threadpool/examples/e03_parallel_for.nim",
  "constantine/platforms/threadpool/examples/e04_parallel_reduce.nim",
  # "constantine/platforms/threadpool/benchmarks/bouncing_producer_consumer/threadpool_bpc.nim", # Need timing not implemented on Windows
  "constantine/platforms/threadpool/benchmarks/dfs/threadpool_dfs.nim",
  "constantine/platforms/threadpool/benchmarks/fibonacci/threadpool_fib.nim",
  "constantine/platforms/threadpool/benchmarks/heat/threadpool_heat.nim",
  # "constantine/platforms/threadpool/benchmarks/matmul_cache_oblivious/threadpool_matmul_co.nim",
  "constantine/platforms/threadpool/benchmarks/nqueens/threadpool_nqueens.nim",
  # "constantine/platforms/threadpool/benchmarks/single_task_producer/threadpool_spc.nim", # Need timing not implemented on Windows
  # "constantine/platforms/threadpool/benchmarks/black_scholes/threadpool_black_scholes.nim", # Need input file
  "constantine/platforms/threadpool/benchmarks/matrix_transposition/threadpool_transposes.nim",
  "constantine/platforms/threadpool/benchmarks/histogram_2D/threadpool_histogram.nim",
  "constantine/platforms/threadpool/benchmarks/logsumexp/threadpool_logsumexp.nim",
]

const testDescMultithreadedCrypto: seq[string] = @[
  "tests/parallel/t_ec_shortw_jac_g1_batch_add_parallel.nim",
  "tests/parallel/t_ec_shortw_prj_g1_batch_add_parallel.nim",
  "tests/parallel/t_ec_shortw_jac_g1_msm_parallel.nim",
  "tests/parallel/t_ec_shortw_prj_g1_msm_parallel.nim",
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
  "bench_ec_g1_msm_bn254_snarks",
  "bench_ec_g1_msm_bls12_381",
  "bench_ec_g2",
  "bench_ec_g2_scalar_mul",
  "bench_pairing_bls12_377",
  "bench_pairing_bls12_381",
  "bench_pairing_bn254_nogami",
  "bench_pairing_bn254_snarks",
  "bench_summary_bls12_377",
  "bench_summary_bls12_381",
  "bench_summary_bn254_nogami",
  "bench_summary_bn254_snarks",
  "bench_summary_pasta",
  "bench_poly1305",
  "bench_sha256",
  "bench_hash_to_curve",
  "bench_ethereum_bls_signatures"
]

# For temporary (hopefully) investigation that can only be reproduced in CI
const useDebug = [
  "tests/math_bigints/t_bigints.nim",
  "tests/t_hash_sha256_vs_openssl.nim",
]

# Skip sanitizers for specific tests
const skipSanitizers = [
  "tests/t_"
]

when defined(windows):
  # UBSAN is not available on mingw
  # https://github.com/libressl-portable/portable/issues/54
  const sanitizers = ""
else:
  const sanitizers =

    " --passC:-fstack-protector-strong " &

    # Fortify source wouldn't help us detect errors in cosntantine
    # because everything is stack allocated
    # except with the threadpool:
    # - https://developers.redhat.com/blog/2021/04/16/broadening-compiler-checks-for-buffer-overflows-in-_fortify_source#what_s_next_for__fortify_source
    # - https://developers.redhat.com/articles/2023/02/06/how-improve-application-security-using-fortifysource3#how_to_improve_application_fortification
    # We also don't use memcpy as it is not constant-time and our copy is compile-time sized.

    " --passC:-D_FORTIFY_SOURCE=3 " &

    # Sanitizers are incompatible with nim default GC
    # The conservative stack scanning of Nim default GC triggers, alignment UB and stack-buffer-overflow check.
    # Address sanitizer requires free registers and needs to be disabled for some inline assembly files.
    # Ensure you use --mm:arc -d:useMalloc
    #
    # Sanitizers are deactivated by default as they slow down CI by at least 6x

    # " --passC:-fsanitize=undefined --passL:-fsanitize=undefined" &
    # " --passC:-fsanitize=address --passL:-fsanitize=address" &
    # " --passC:-fno-sanitize-recover" # Enforce crash on undefined behaviour
    ""

# Tests & Benchmarks helper functions
# ----------------------------------------------------------------

proc clearParallelBuild() =
  # Support clearing from non POSIX shell like CMD, Powershell or MSYS2
  if fileExists(buildParallel):
    rmFile(buildParallel)

proc setupTestCommand(flags, path: string, useASM: bool): string =
  var lang = "c"
  if existsEnv"TEST_LANG":
    lang = getEnv"TEST_LANG"

  return "nim " & lang &
    " -r " &
    flags &
    releaseBuildOptions(useASM) &
    " --outdir:build/testsuite " &
    &" --nimcache:nimcache/{path} " &
    path

proc test(cmd: string) =
  echo "\n=============================================================================================="
  echo "Running '", cmd, "'"
  echo "=============================================================================================="
  exec cmd

proc testBatch(commands: var string, flags, path: string, useASM = true) =
  # With LTO, the linker produces lots of spurious warnings when copying into openArrays/strings

  let flags = if defined(gcc): flags & " --passC:-Wno-stringop-overflow --passL:-Wno-stringop-overflow "
              else: flags

  commands = commands & setupTestCommand(flags, path, useASM) & '\n'

proc setupBench(benchName: string, run: bool, useAsm: bool): string =
  var runFlags = " "
  if run: # Beware of https://github.com/nim-lang/Nim/issues/21704
    runFlags = runFlags & " -r "

  let asmStatus = if useASM: "useASM"
                  else: "noASM"

  if defined(gcc):
    # With LTO, the linker produces lots of spurious warnings when copying into openArrays/strings
    runFlags = runFlags & " --passC:-Wno-stringop-overflow --passL:-Wno-stringop-overflow "

  let cc = if existsEnv"CC": getEnv"CC"
           else: "defaultcompiler"

  return "nim c " &
       runFlags &
       releaseBuildOptions(useASM) &
       &" -o:build/bench/{benchName}_{cc}_{asmStatus}" &
       &" --nimcache:nimcache/benches/{benchName}_{cc}_{asmStatus}" &
       &" benchmarks/{benchName}.nim"

proc runBench(benchName: string, useAsm = true) =
  if not dirExists "build":
    mkDir "build"
  let command = setupBench(benchName, run = true, useAsm)
  exec command

proc buildBenchBatch(commands: var string, benchName: string, useAsm = true) =
  let command = setupBench(benchName, run = false, useAsm)
  commands = commands & command & '\n'

proc addTestSet(cmdFile: var string, requireGMP: bool, test32bit = false, useASM = true) =
  if not dirExists "build":
    mkDir "build"
  echo "Found " & $testDesc.len & " tests to run."

  for td in testDesc:
    if not(td.useGMP and not requireGMP):
      var flags = "" # Beware of https://github.com/nim-lang/Nim/issues/21704
      if test32bit:
        flags = flags & " -d:Ctt32 "
      if td.path in useDebug:
        flags = flags & " -d:CttDebug "
      if td.path notin skipSanitizers:
        flags = flags & sanitizers

      cmdFile.testBatch(flags, td.path, useASM)

proc addTestSetNvidia(cmdFile: var string) =
  if not dirExists "build":
    mkDir "build"
  echo "Found " & $testDescNvidia.len & " tests to run."

  for path in testDescNvidia:
    var flags = "" # Beware of https://github.com/nim-lang/Nim/issues/21704
    if path notin skipSanitizers:
      flags = flags & sanitizers
    cmdFile.testBatch(flags, path)

proc addTestSetThreadpool(cmdFile: var string) =
  if not dirExists "build":
    mkDir "build"
  echo "Found " & $testDescThreadpool.len & " tests to run."

  for path in testDescThreadpool:
    var flags = " --threads:on --debugger:native "
    if path notin skipSanitizers:
      flags = flags & sanitizers
    cmdFile.testBatch(flags, path)

proc addTestSetMultithreadedCrypto(cmdFile: var string, test32bit = false, useASM = true) =
  if not dirExists "build":
    mkDir "build"
  echo "Found " & $testDescMultithreadedCrypto.len & " tests to run."

  for td in testDescMultithreadedCrypto:
    var flags = " --threads:on --debugger:native"
    if test32bit:
      flags = flags & " -d:Ctt32 "
    if td in useDebug:
      flags = flags & " -d:CttDebug "
    if td notin skipSanitizers:
      flags = flags & sanitizers

    cmdFile.testBatch(flags, td, useASM)

proc addBenchSet(cmdFile: var string, useAsm = true) =
  if not dirExists "build":
    mkDir "build"
  echo "Found " & $benchDesc.len & " benches to compile. (compile-only to ensure they stay relevant)"
  for bd in benchDesc:
    cmdFile.buildBenchBatch(bd, useASM = useASM)

proc genParallelCmdRunner() =
  exec "nim c --verbosity:0 --hints:off --warnings:off -d:release --out:build/pararun --nimcache:nimcache/pararun helpers/pararun.nim"

# Tasks
# ----------------------------------------------------------------

task test, "Run all tests":
  # -d:testingCurves is configured in a *.nim.cfg for convenience
  var cmdFile: string
  cmdFile.addTestSet(requireGMP = true, useASM = true)
  cmdFile.addBenchSet(useASM = true)    # Build (but don't run) benches to ensure they stay relevant
  cmdFile.addTestSetThreadpool()
  cmdFile.addTestSetMultithreadedCrypto()
  for cmd in cmdFile.splitLines():
    if cmd != "": # Windows doesn't like empty commands
      exec cmd

task test_no_asm, "Run all tests (no assembly)":
  # -d:testingCurves is configured in a *.nim.cfg for convenience
  var cmdFile: string
  cmdFile.addTestSet(requireGMP = true, useASM = false)
  cmdFile.addBenchSet(useASM = false)    # Build (but don't run) benches to ensure they stay relevant
  cmdFile.addTestSetThreadpool()
  cmdFile.addTestSetMultithreadedCrypto(useASM = false)
  for cmd in cmdFile.splitLines():
    if cmd != "": # Windows doesn't like empty commands
      exec cmd

task test_no_gmp, "Run tests that don't require GMP":
  # -d:testingCurves is configured in a *.nim.cfg for convenience
  var cmdFile: string
  cmdFile.addTestSet(requireGMP = false, useASM = true)
  cmdFile.addBenchSet(useASM = true)    # Build (but don't run) benches to ensure they stay relevant
  cmdFile.addTestSetThreadpool()
  cmdFile.addTestSetMultithreadedCrypto()
  for cmd in cmdFile.splitLines():
    if cmd != "": # Windows doesn't like empty commands
      exec cmd

task test_no_gmp_no_asm, "Run tests that don't require GMP using a pure Nim backend":
  # -d:testingCurves is configured in a *.nim.cfg for convenience
  var cmdFile: string
  cmdFile.addTestSet(requireGMP = false, useASM = false)
  cmdFile.addBenchSet(useASM = false)    # Build (but don't run) benches to ensure they stay relevant
  cmdFile.addTestSetThreadpool()
  cmdFile.addTestSetMultithreadedCrypto(useASM = false)
  for cmd in cmdFile.splitLines():
    if cmd != "": # Windows doesn't like empty commands
      exec cmd

task test_parallel, "Run all tests in parallel":
  # -d:testingCurves is configured in a *.nim.cfg for convenience
  clearParallelBuild()
  genParallelCmdRunner()

  var cmdFile: string
  cmdFile.addTestSet(requireGMP = true, useASM = true)
  cmdFile.addBenchSet(useASM = true)    # Build (but don't run) benches to ensure they stay relevant
  writeFile(buildParallel, cmdFile)
  exec "build/pararun " & buildParallel

  # Threadpool tests done serially
  cmdFile = ""
  cmdFile.addTestSetThreadpool()
  cmdFile.addTestSetMultithreadedCrypto()
  for cmd in cmdFile.splitLines():
    if cmd != "": # Windows doesn't like empty commands
      exec cmd

task test_parallel_no_asm, "Run all tests (without macro assembler) in parallel":
  # -d:testingCurves is configured in a *.nim.cfg for convenience
  clearParallelBuild()
  genParallelCmdRunner()

  var cmdFile: string
  cmdFile.addTestSet(requireGMP = true, useASM = false)
  cmdFile.addBenchSet(useASM = false)
  writeFile(buildParallel, cmdFile)
  exec "build/pararun " & buildParallel

  # Threadpool tests done serially
  cmdFile = ""
  cmdFile.addTestSetThreadpool()
  cmdFile.addTestSetMultithreadedCrypto(useASM = false)
  for cmd in cmdFile.splitLines():
    if cmd != "": # Windows doesn't like empty commands
      exec cmd

task test_parallel_no_gmp, "Run all tests in parallel":
  # -d:testingCurves is configured in a *.nim.cfg for convenience
  clearParallelBuild()
  genParallelCmdRunner()

  var cmdFile: string
  cmdFile.addTestSet(requireGMP = false, useASM = true)
  cmdFile.addBenchSet(useASM = true)    # Build (but don't run) benches to ensure they stay relevant
  writeFile(buildParallel, cmdFile)
  exec "build/pararun " & buildParallel

  # Threadpool tests done serially
  cmdFile = ""
  cmdFile.addTestSetThreadpool()
  cmdFile.addTestSetMultithreadedCrypto()
  for cmd in cmdFile.splitLines():
    if cmd != "": # Windows doesn't like empty commands
      exec cmd

task test_parallel_no_gmp_no_asm, "Run all tests in parallel":
  # -d:testingCurves is configured in a *.nim.cfg for convenience
  clearParallelBuild()
  genParallelCmdRunner()

  var cmdFile: string
  cmdFile.addTestSet(requireGMP = false, useASM = false)
  cmdFile.addBenchSet(useASM = false)    # Build (but don't run) benches to ensure they stay relevant
  writeFile(buildParallel, cmdFile)
  exec "build/pararun " & buildParallel

  # Threadpool tests done serially
  cmdFile = ""
  cmdFile.addTestSetThreadpool()
  cmdFile.addTestSetMultithreadedCrypto(useASM = false)
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

# Finite field 𝔽p
# ------------------------------------------

task bench_fp, "Run benchmark 𝔽p with your CC compiler":
  runBench("bench_fp")

task bench_fp_noasm, "Run benchmark 𝔽p with your CC compiler - no Assembly":
  runBench("bench_fp", useAsm = false)

# Double-precision field 𝔽pDbl
# ------------------------------------------

task bench_fpdbl, "Run benchmark 𝔽pDbl with your CC compiler":
  runBench("bench_fp_double_precision")

task bench_fpdbl_noasm, "Run benchmark 𝔽p with CC compiler - no Assembly":
  runBench("bench_fp_double_precision", useAsm = false)


# Extension field 𝔽p2
# ------------------------------------------

task bench_fp2, "Run benchmark 𝔽p2 with your CC compiler":
  runBench("bench_fp2")

task bench_fp2_noasm, "Run benchmark 𝔽p2 with CC compiler - no Assembly":
  runBench("bench_fp2", useAsm = false)

# Extension field 𝔽p4
# ------------------------------------------

task bench_fp4, "Run benchmark 𝔽p4 with your CC compiler":
  runBench("bench_fp4")

task bench_fp4_noasm, "Run benchmark 𝔽p4 with CC compiler - no Assembly":
  runBench("bench_fp4", useAsm = false)


# Extension field 𝔽p6
# ------------------------------------------

task bench_fp6, "Run benchmark 𝔽p6 with your CC compiler":
  runBench("bench_fp6")

task bench_fp6_noasm, "Run benchmark 𝔽p6 with CC compiler - no Assembly":
  runBench("bench_fp6", useAsm = false)

# Extension field 𝔽p12
# ------------------------------------------

task bench_fp12, "Run benchmark 𝔽p12 with your CC compiler":
  runBench("bench_fp12")

task bench_fp12_noasm, "Run benchmark 𝔽p12 with CC compiler - no Assembly":
  runBench("bench_fp12", useAsm = false)

# Elliptic curve G1
# ------------------------------------------

task bench_ec_g1, "Run benchmark on Elliptic Curve group 𝔾1 - CC compiler":
  runBench("bench_ec_g1")

task bench_ec_g1_noasm, "Run benchmark on Elliptic Curve group 𝔾1 - CC compiler no Assembly":
  runBench("bench_ec_g1", useAsm = false)


# Elliptic curve G1 - batch operations
# ------------------------------------------

task bench_ec_g1_batch, "Run benchmark on Elliptic Curve group 𝔾1 (batch ops) - CC compiler":
  runBench("bench_ec_g1_batch")

task bench_ec_g1_batch_noasm, "Run benchmark on Elliptic Curve group 𝔾1 (batch ops) - CC compiler no Assembly":
  runBench("bench_ec_g1_batch", useAsm = false)


# Elliptic curve G1 - scalar multiplication
# ------------------------------------------

task bench_ec_g1_scalar_mul, "Run benchmark on Elliptic Curve group 𝔾1 (Scalar Multiplication) - CC compiler":
  runBench("bench_ec_g1_scalar_mul")

task bench_ec_g1_scalar_mul_noasm, "Run benchmark on Elliptic Curve group 𝔾1 (Scalar Multiplication) - CC compiler no Assembly":
  runBench("bench_ec_g1_scalar_mul", useAsm = false)

# Elliptic curve G1 - Multi-scalar-mul
# ------------------------------------------

task bench_ec_g1_msm_bn254_snarks, "Run benchmark on Elliptic Curve group 𝔾1 (Multi-Scalar-Mul) for BN254-Snarks - CC compiler":
  runBench("bench_ec_g1_msm_bn254_snarks")

task bench_ec_g1_msm_bn254_snarks_noasm, "Run benchmark on Elliptic Curve group 𝔾1 (Multi-Scalar-Mul) for BN254-Snarks - CC compiler no Assembly":
  runBench("bench_ec_g1_msm_bn254_snarks", useAsm = false)

task bench_ec_g1_msm_bls12_381, "Run benchmark on Elliptic Curve group 𝔾1 (Multi-Scalar-Mul) for BLS12-381 - CC compiler":
  runBench("bench_ec_g1_msm_bls12_381")

task bench_ec_g1_msm_bls12_381_noasm, "Run benchmark on Elliptic Curve group 𝔾1 (Multi-Scalar-Mul) for BLS12-381 - CC compiler no Assembly":
  runBench("bench_ec_g1_msm_bls12_381", useAsm = false)

# Elliptic curve G2
# ------------------------------------------

task bench_ec_g2, "Run benchmark on Elliptic Curve group 𝔾2 - CC compiler":
  runBench("bench_ec_g2")

task bench_ec_g2_noasm, "Run benchmark on Elliptic Curve group 𝔾2 - CC compiler no Assembly":
  runBench("bench_ec_g2", useAsm = false)

# Elliptic curve G2 - scalar multiplication
# ------------------------------------------

task bench_ec_g2_scalar_mul, "Run benchmark on Elliptic Curve group 𝔾2 (Multi-Scalar-Mul) - CC compiler":
  runBench("bench_ec_g2_scalar_mul")


task bench_ec_g2_scalar_mul_noasm, "Run benchmark on Elliptic Curve group 𝔾2 (Multi-Scalar-Mul) - CC compiler no Assembly":
  runBench("bench_ec_g2_scalar_mul", useAsm = false)

# Pairings
# ------------------------------------------

task bench_pairing_bls12_377, "Run pairings benchmarks for BLS12-377 - CC compiler":
  runBench("bench_pairing_bls12_377")

task bench_pairing_bls12_377_noasm, "Run pairings benchmarks for BLS12-377 - CC compiler no Assembly":
  runBench("bench_pairing_bls12_377", useAsm = false)

# --

task bench_pairing_bls12_381, "Run pairings benchmarks for BLS12-381 - CC compiler":
  runBench("bench_pairing_bls12_381")

task bench_pairing_bls12_381_noasm, "Run pairings benchmarks for BLS12-381 - CC compiler no Assembly":
  runBench("bench_pairing_bls12_381", useAsm = false)

# --

task bench_pairing_bn254_nogami, "Run pairings benchmarks for BN254-Nogami - CC compiler":
  runBench("bench_pairing_bn254_nogami")

task bench_pairing_bn254_nogami_noasm, "Run pairings benchmarks for BN254-Nogami - CC compiler no Assembly":
  runBench("bench_pairing_bn254_nogami", useAsm = false)

# --

task bench_pairing_bn254_snarks, "Run pairings benchmarks for BN254-Snarks - CC compiler":
  runBench("bench_pairing_bn254_snarks")

task bench_pairing_bn254_snarks_noasm, "Run pairings benchmarks for BN254-Snarks - CC compiler no Assembly":
  runBench("bench_pairing_bn254_snarks", useAsm = false)


# Curve summaries
# ------------------------------------------

task bench_summary_bls12_377, "Run summary benchmarks for BLS12-377 - CC compiler":
  runBench("bench_summary_bls12_377")


task bench_summary_bls12_377_noasm, "Run summary benchmarks for BLS12-377 - CC compiler no Assembly":
  runBench("bench_summary_bls12_377", useAsm = false)

# --

task bench_summary_bls12_381, "Run summary benchmarks for BLS12-381 - CC compiler":
  runBench("bench_summary_bls12_381")

task bench_summary_bls12_381_noasm, "Run summary benchmarks for BLS12-381 - CC compiler no Assembly":
  runBench("bench_summary_bls12_381", useAsm = false)

# --

task bench_summary_bn254_nogami, "Run summary benchmarks for BN254-Nogami - CC compiler":
  runBench("bench_summary_bn254_nogami")

task bench_summary_bn254_nogami_noasm, "Run summary benchmarks for BN254-Nogami - CC compiler no Assembly":
  runBench("bench_summary_bn254_nogami", useAsm = false)

# --

task bench_summary_bn254_snarks, "Run summary benchmarks for BN254-Snarks - CC compiler":
  runBench("bench_summary_bn254_snarks")


task bench_summary_bn254_snarks_noasm, "Run summary benchmarks for BN254-Snarks - CC compiler no Assembly":
  runBench("bench_summary_bn254_snarks", useAsm = false)

# --

task bench_summary_pasta, "Run summary benchmarks for the Pasta curves - CC compiler":
  runBench("bench_summary_pasta")


task bench_summary_pasta_noasm, "Run summary benchmarks for the Pasta curves - CC compiler no Assembly":
  runBench("bench_summary_pasta", useAsm = false)

# Hashes
# ------------------------------------------

task bench_sha256, "Run SHA256 benchmarks":
  runBench("bench_sha256")

# Hash-to-curve
# ------------------------------------------
task bench_hash_to_curve, "Run Hash-to-Curve benchmarks":
  runBench("bench_hash_to_curve")

task bench_hash_to_curve_noasm, "Run Hash-to-Curve benchmarks - No Assembly":
  runBench("bench_hash_to_curve", useAsm = false)

# BLS signatures
# ------------------------------------------
task bench_ethereum_bls_signatures, "Run Ethereum BLS signatures benchmarks - CC compiler":
  runBench("bench_ethereum_bls_signatures")

task bench_ethereum_bls_signatures_noasm, "Run Ethereum BLS signatures benchmarks - CC compiler no assembly":
  runBench("bench_ethereum_bls_signatures", useAsm = false)
