packageName   = "constantine"
version       = "0.0.1"
author        = "Status Research & Development GmbH"
description   = "This library provides thoroughly tested and highly-optimized implementations of cryptography protocols."
license       = "MIT or Apache License 2.0"

# Dependencies
# ----------------------------------------------------------------

requires "nim >= 1.1.0"

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
  # Primitives
  # ----------------------------------------------------------
  ("tests/math/t_primitives.nim", false),
  ("tests/math/t_primitives_extended_precision.nim", false),
  # Big ints
  # ----------------------------------------------------------
  ("tests/math/t_io_bigints.nim", false),
  ("tests/math/t_io_unsaturated.nim", false),
  ("tests/math/t_bigints.nim", false),
  ("tests/math/t_bigints_multimod.nim", false),
  ("tests/math/t_bigints_mod_vs_gmp.nim", true),
  ("tests/math/t_bigints_mul_vs_gmp.nim", true),
  ("tests/math/t_bigints_mul_high_words_vs_gmp.nim", true),
  # Field
  # ----------------------------------------------------------
  ("tests/math/t_io_fields", false),
  ("tests/math/t_finite_fields.nim", false),
  ("tests/math/t_finite_fields_conditional_arithmetic.nim", false),
  ("tests/math/t_finite_fields_mulsquare.nim", false),
  ("tests/math/t_finite_fields_sqrt.nim", false),
  ("tests/math/t_finite_fields_powinv.nim", false),
  ("tests/math/t_finite_fields_vs_gmp.nim", true),
  ("tests/math/t_fp_cubic_root.nim", false),
  # Double-precision finite fields
  # ----------------------------------------------------------
  ("tests/math/t_finite_fields_double_precision.nim", false),
  # Towers of extension fields
  # ----------------------------------------------------------
  ("tests/math/t_fp2.nim", false),
  ("tests/math/t_fp2_sqrt.nim", false),
  ("tests/math/t_fp4.nim", false),
  ("tests/math/t_fp6_bn254_snarks.nim", false),
  ("tests/math/t_fp6_bls12_377.nim", false),
  ("tests/math/t_fp6_bls12_381.nim", false),
  ("tests/math/t_fp6_bw6_761.nim", false),
  ("tests/math/t_fp12_bn254_snarks.nim", false),
  ("tests/math/t_fp12_bls12_377.nim", false),
  ("tests/math/t_fp12_bls12_381.nim", false),
  ("tests/math/t_fp12_exponentiation.nim", false),
  ("tests/math/t_fp12_anti_regression.nim", false),

  ("tests/math/t_fp4_frobenius.nim", false),
  ("tests/math/t_fp6_frobenius.nim", false),
  ("tests/math/t_fp12_frobenius.nim", false),

  # Elliptic curve arithmetic 
  # ----------------------------------------------------------
  ("tests/math/t_ec_conversion.nim", false),

  # Elliptic curve arithmetic G1
  # ----------------------------------------------------------
  # ("tests/math/t_ec_shortw_prj_g1_add_double.nim", false),
  # ("tests/math/t_ec_shortw_prj_g1_mul_sanity.nim", false),
  # ("tests/math/t_ec_shortw_prj_g1_mul_distri.nim", false),
  ("tests/math/t_ec_shortw_prj_g1_mul_vs_ref.nim", false),
  ("tests/math/t_ec_shortw_prj_g1_mixed_add.nim", false),

  # ("tests/math/t_ec_shortw_jac_g1_add_double.nim", false),
  # ("tests/math/t_ec_shortw_jac_g1_mul_sanity.nim", false),
  # ("tests/math/t_ec_shortw_jac_g1_mul_distri.nim", false),
  ("tests/math/t_ec_shortw_jac_g1_mul_vs_ref.nim", false),
  ("tests/math/t_ec_shortw_jac_g1_mixed_add.nim", false),

  ("tests/math/t_ec_twedwards_prj_add_double", false),
  ("tests/math/t_ec_twedwards_prj_mul_sanity", false),
  ("tests/math/t_ec_twedwards_prj_mul_distri", false),
 

  # Elliptic curve arithmetic G2
  # ----------------------------------------------------------
  # ("tests/math/t_ec_shortw_prj_g2_add_double_bn254_snarks.nim", false),
  # ("tests/math/t_ec_shortw_prj_g2_mul_sanity_bn254_snarks.nim", false),
  # ("tests/math/t_ec_shortw_prj_g2_mul_distri_bn254_snarks.nim", false),
  ("tests/math/t_ec_shortw_prj_g2_mul_vs_ref_bn254_snarks.nim", false),
  ("tests/math/t_ec_shortw_prj_g2_mixed_add_bn254_snarks.nim", false),

  # ("tests/math/t_ec_shortw_prj_g2_add_double_bls12_381.nim", false),
  # ("tests/math/t_ec_shortw_prj_g2_mul_sanity_bls12_381.nim", false),
  # ("tests/math/t_ec_shortw_prj_g2_mul_distri_bls12_381.nim", false),
  ("tests/math/t_ec_shortw_prj_g2_mul_vs_ref_bls12_381.nim", false),
  ("tests/math/t_ec_shortw_prj_g2_mixed_add_bls12_381.nim", false),

  # ("tests/math/t_ec_shortw_prj_g2_add_double_bls12_377.nim", false),
  # ("tests/math/t_ec_shortw_prj_g2_mul_sanity_bls12_377.nim", false),
  # ("tests/math/t_ec_shortw_prj_g2_mul_distri_bls12_377.nim", false),
  ("tests/math/t_ec_shortw_prj_g2_mul_vs_ref_bls12_377.nim", false),
  ("tests/math/t_ec_shortw_prj_g2_mixed_add_bls12_377.nim", false),

  # ("tests/math/t_ec_shortw_prj_g2_add_double_bw6_761.nim", false),
  # ("tests/math/t_ec_shortw_prj_g2_mul_sanity_bw6_761.nim", false),
  # ("tests/math/t_ec_shortw_prj_g2_mul_distri_bw6_761.nim", false),
  ("tests/math/t_ec_shortw_prj_g2_mul_vs_ref_bw6_761.nim", false),
  ("tests/math/t_ec_shortw_prj_g2_mixed_add_bw6_761.nim", false),

  # ("tests/math/t_ec_shortw_jac_g2_add_double_bn254_snarks.nim", false),
  # ("tests/math/t_ec_shortw_jac_g2_mul_sanity_bn254_snarks.nim", false),
  # ("tests/math/t_ec_shortw_jac_g2_mul_distri_bn254_snarks.nim", false),
  ("tests/math/t_ec_shortw_jac_g2_mul_vs_ref_bn254_snarks.nim", false),
  ("tests/math/t_ec_shortw_jac_g2_mixed_add_bn254_snarks.nim", false),

  # ("tests/math/t_ec_shortw_jac_g2_add_double_bls12_381.nim", false),
  # ("tests/math/t_ec_shortw_jac_g2_mul_sanity_bls12_381.nim", false),
  # ("tests/math/t_ec_shortw_jac_g2_mul_distri_bls12_381.nim", false),
  ("tests/math/t_ec_shortw_jac_g2_mul_vs_ref_bls12_381.nim", false),
  ("tests/math/t_ec_shortw_jac_g2_mixed_add_bls12_381.nim", false),

  # ("tests/math/t_ec_shortw_jac_g2_add_double_bls12_377.nim", false),
  # ("tests/math/t_ec_shortw_jac_g2_mul_sanity_bls12_377.nim", false),
  # ("tests/math/t_ec_shortw_jac_g2_mul_distri_bls12_377.nim", false),
  ("tests/math/t_ec_shortw_jac_g2_mul_vs_ref_bls12_377.nim", false),
  ("tests/math/t_ec_shortw_jac_g2_mixed_add_bls12_377.nim", false),

  # ("tests/math/t_ec_shortw_jac_g2_add_double_bw6_761.nim", false),
  # ("tests/math/t_ec_shortw_jac_g2_mul_sanity_bw6_761.nim", false),
  # ("tests/math/t_ec_shortw_jac_g2_mul_distri_bw6_761.nim", false),
  ("tests/math/t_ec_shortw_jac_g2_mul_vs_ref_bw6_761.nim", false),
  ("tests/math/t_ec_shortw_jac_g2_mixed_add_bw6_761.nim", false),

  # Elliptic curve arithmetic vs Sagemath
  # ----------------------------------------------------------
  ("tests/math/t_ec_frobenius.nim", false),
  ("tests/math/t_ec_sage_bn254_nogami.nim", false),
  ("tests/math/t_ec_sage_bn254_snarks.nim", false),
  ("tests/math/t_ec_sage_bls12_377.nim", false),
  ("tests/math/t_ec_sage_bls12_381.nim", false),
  ("tests/math/t_ec_sage_pallas.nim", false),
  ("tests/math/t_ec_sage_vesta.nim", false),
  # Edge cases highlighted by past bugs
  # ----------------------------------------------------------
  ("tests/math/t_ec_shortw_prj_edge_cases.nim", false),

  # Subgroups and cofactors
  # ----------------------------------------------------------
  ("tests/math/t_ec_subgroups_bn254_nogami.nim", false),
  ("tests/math/t_ec_subgroups_bn254_snarks.nim", false),
  ("tests/math/t_ec_subgroups_bls12_377.nim", false),
  ("tests/math/t_ec_subgroups_bls12_381.nim", false),

  ("tests/math/t_pairing_bn254_nogami_gt_subgroup.nim", false),
  ("tests/math/t_pairing_bn254_snarks_gt_subgroup.nim", false),
  ("tests/math/t_pairing_bls12_377_gt_subgroup.nim", false),
  ("tests/math/t_pairing_bls12_381_gt_subgroup.nim", false),
  ("tests/math/t_pairing_bw6_761_gt_subgroup.nim", false),

  # Pairing
  # ----------------------------------------------------------
  # ("tests/math/t_pairing_bls12_377_line_functions.nim", false),
  # ("tests/math/t_pairing_bls12_381_line_functions.nim", false),
  ("tests/math/t_pairing_mul_fp12_by_lines.nim", false),
  ("tests/math/t_pairing_cyclotomic_subgroup.nim", false),
  ("tests/math/t_pairing_bn254_nogami_optate.nim", false),
  ("tests/math/t_pairing_bn254_snarks_optate.nim", false),
  ("tests/math/t_pairing_bls12_377_optate.nim", false),
  ("tests/math/t_pairing_bls12_381_optate.nim", false),

  # Multi-Pairing
  # ----------------------------------------------------------
  ("tests/math/t_pairing_bn254_nogami_multi.nim", false),
  ("tests/math/t_pairing_bn254_snarks_multi.nim", false),
  ("tests/math/t_pairing_bls12_381_multi.nim", false),

  # Prime order fields
  # ----------------------------------------------------------
  ("tests/math/t_fr.nim", false),

  # Hashing vs OpenSSL
  # ----------------------------------------------------------
  ("tests/t_hash_sha256_vs_openssl.nim", true), # skip OpenSSL tests on Windows

  # Hashing to elliptic curves
  # ----------------------------------------------------------
  ("tests/t_hash_to_field.nim", false),
  ("tests/t_hash_to_curve_random.nim", false),
  ("tests/t_hash_to_curve.nim", false),

  # Ciphers
  # ----------------------------------------------------------
  ("tests/t_cipher_chacha20.nim", false),

  # Message Authentication Code
  # ----------------------------------------------------------
  ("tests/t_mac_poly1305.nim", false),

  # Protocols
  # ----------------------------------------------------------
  ("tests/t_ethereum_evm_precompiles.nim", false),
  ("tests/t_blssig_pop_on_bls12381_g2.nim", false),
]

# For temporary (hopefully) investigation that can only be reproduced in CI
const useDebug = [
  "tests/math/t_bigints.nim",
  "tests/math/t_hash_sha256_vs_openssl.nim",
]

# Tests that uses sequences require Nim GC, stack scanning and nil pointer passed to openarray
# In particular the tests that uses the json test vectors, don't sanitize them.
# we do use gc:none to help
const skipSanitizers = [
  "tests/math/t_ec_sage_bn254_nogami.nim",
  "tests/math/t_ec_sage_bn254_snarks.nim",
  "tests/math/t_ec_sage_bls12_377.nim",
  "tests/math/t_ec_sage_bls12_381.nim",
  "tests/t_hash_to_field.nim",
  "tests/t_hash_to_curve.nim",
  "tests/t_hash_to_curve_random.nim"
]

when defined(windows):
  # UBSAN is not available on mingw
  const sanitizers = ""
else:
  const sanitizers =
    " --passC:-fsanitize=undefined --passL:-fsanitize=undefined" &
    " --passC:-fno-sanitize-recover" & # Enforce crash on undefined behaviour
    " --gc:none" # The conservative stack scanning of Nim default GC triggers, alignment UB and stack-buffer-overflow check.
    # " --passC:-fsanitize=address --passL:-fsanitize=address" & # Requires too much stack for the inline assembly


# Helper functions
# ----------------------------------------------------------------

proc clearParallelBuild() =
  exec "> " & buildParallel

proc test(flags, path: string, commandFile = false) =
  # commandFile should be a "file" but Nimscript doesn't support IO
  if not dirExists "build":
    mkDir "build"
  # Compilation language is controlled by WEAVE_TEST_LANG
  var lang = "c"
  if existsEnv"TEST_LANG":
    lang = getEnv"TEST_LANG"

  var cc = ""
  if existsEnv"CC":
    cc = " --cc:" & getEnv"CC"

  var flags = flags
  when not defined(windows):
    # Not available in MinGW https://github.com/libressl-portable/portable/issues/54
    flags &= " --passC:-fstack-protector-all"
  let command = "nim " & lang & cc & " " & flags &
    " --verbosity:0 --outdir:build/testsuite -r --hints:off --warnings:off " &
    " --nimcache:nimcache/" & path & " " &
    path

  if not commandFile:
    echo "\n=============================================================================================="
    echo "Running [flags:", flags, "] ", path
    echo "=============================================================================================="
    exec command
  else:
    exec "echo \'" & command & "\' >> " & buildParallel
    exec "echo \"------------------------------------------------------\""

proc buildBench(benchName: string, compiler = "", useAsm = true, run = false) =
  if not dirExists "build":
    mkDir "build"

  let runFlag = if run: " -r "
            else: " "

  var cc = ""
  if compiler != "":
    cc = "--cc:" & compiler
  if not useAsm:
    cc &= " -d:CttASM=false"
  exec "nim c " & cc &
       " -d:danger --verbosity:0 -o:build/bench/" & benchName & "_" & compiler & "_" & (if useAsm: "useASM" else: "noASM") &
       " --nimcache:nimcache/" & benchName & "_" & compiler & "_" & (if useAsm: "useASM" else: "noASM") &
       runFlag & "--hints:off --warnings:off benchmarks/" & benchName & ".nim"

proc runBench(benchName: string, compiler = "", useAsm = true) =
  buildBench(benchName, compiler, useAsm, run = true)

proc runTests(requireGMP: bool, dumpCmdFile = false, test32bit = false, testASM = true) =
  for td in testDesc:
    if not(td.useGMP and not requireGMP):
      var flags = ""
      if not testASM:
        flags &= " -d:CttASM=false"
      if test32bit:
        flags &= " -d:Constantine32"
      if td.path in useDebug:
        flags &= " -d:debugConstantine"
      if td.path notin skipSanitizers:
        flags &= sanitizers
      test flags, td.path, dumpCmdFile

proc buildAllBenches(useAsm = true) =
  echo "\n\n------------------------------------------------------\n"
  echo "Building benchmarks to ensure they stay relevant ..."
  buildBench("bench_fp", useAsm = useAsm)
  buildBench("bench_fp_double_precision", useAsm = useAsm)
  buildBench("bench_fp2", useAsm = useAsm)
  buildBench("bench_fp6", useAsm = useAsm)
  buildBench("bench_fp12", useAsm = useAsm)
  buildBench("bench_ec_g1", useAsm = useAsm)
  buildBench("bench_ec_g2", useAsm = useAsm)
  buildBench("bench_pairing_bls12_377", useAsm = useAsm)
  buildBench("bench_pairing_bls12_381", useAsm = useAsm)
  buildBench("bench_pairing_bn254_nogami", useAsm = useAsm)
  buildBench("bench_pairing_bn254_snarks", useAsm = useAsm)
  buildBench("bench_summary_bls12_377", useAsm = useAsm)
  buildBench("bench_summary_bls12_381", useAsm = useAsm)
  buildBench("bench_summary_bn254_nogami", useAsm = useAsm)
  buildBench("bench_summary_bn254_snarks", useAsm = useAsm)
  buildBench("bench_sha256", useAsm = useAsm)
  buildBench("bench_hash_to_curve", useAsm = useAsm)
  echo "All benchmarks compile successfully."

proc genBindings(bindingsName, prefixNimMain: string) =
  proc compile(libName: string, flags = "") =
    # -d:danger to avoid boundsCheck, overflowChecks that would trigger exceptions or allocations in a crypto library.
    #           Those are internally guaranteed at compile-time by fixed-sized array
    #           and checked at runtime with an appropriate error code if any for user-input.
    # -gc:arc   Constantine stack allocates everything. Inputs are through unmanaged ptr+len.
    #           In the future, Constantine might use:
    #             - heap-allocated sequences and objects manually managed or managed by destructors for multithreading.
    #             - heap-allocated strings for hex-string or decimal strings
    exec "nim c -f " & flags & " --noMain -d:danger --app:lib --gc:arc " &
         " --nimMainPrefix:" & prefixNimMain &
         " --out:" & libName & " --outdir:bindings/generated " &
         " --nimcache:nimcache/bindings/" & bindingsName &
         " bindings/" & bindingsName & ".nim"

  when defined(windows):
    compile bindingsName & ".dll"

  elif defined(macosx):
    compile "lib" & bindingsName & ".dylib.arm", "--cpu:arm64 -l:'-target arm64-apple-macos11' -t:'-target arm64-apple-macos11'"
    compile "lib" & bindingsName & ".dylib.x64", "--cpu:amd64 -l:'-target x86_64-apple-macos10.12' -t:'-target x86_64-apple-macos10.12'"
    exec "lipo bindings/generated/lib" & bindingsName & ".dylib.arm " &
             " bindings/generated/lib" & bindingsName & ".dylib.x64 " &
             " -output bindings/generated/lib" & bindingsName & ".dylib -create"

  else:
    compile "lib" & bindingsName & ".so"

proc genHeaders(bindingsName: string) =
  exec "nim c -r -d:release -d:CttGenerateHeaders " &
       " --out:" & bindingsName & "_gen_header.exe --outdir:bindings/generated " &
       " --nimcache:nimcache/bindings/" & bindingsName & "_header" &
       " bindings/" & bindingsName & ".nim"

# Tasks
# ----------------------------------------------------------------

task bindings, "Generate Constantine bindings":
  genBindings("constantine_bls12_381", "ctt_bls12381_")
  genHeaders("constantine_bls12_381")

task test, "Run all tests":
  # -d:testingCurves is configured in a *.nim.cfg for convenience
  runTests(requireGMP = true)

  # if sizeof(int) == 8: # 32-bit tests on 64-bit arch
  #   runTests(requireGMP = true, test32bit = true)

  # Ensure benchmarks stay relevant. Ignore Windows 32-bit at the moment
  if not defined(windows) or not (existsEnv"UCPU" or getEnv"UCPU" == "i686"):
    buildAllBenches()

task test_no_assembler, "Run all tests":
  # -d:testingCurves is configured in a *.nim.cfg for convenience
  runTests(requireGMP = true, testASM = false)

  # if sizeof(int) == 8: # 32-bit tests on 64-bit arch
  #   runTests(requireGMP = true, test32bit = true)

  # Ensure benchmarks stay relevant. Ignore Windows 32-bit at the moment
  if not defined(windows) or not (existsEnv"UCPU" or getEnv"UCPU" == "i686"):
    buildAllBenches(useASM = false)

task test_no_gmp, "Run tests that don't require GMP":
  # -d:testingCurves is configured in a *.nim.cfg for convenience
  runTests(requireGMP = false)

  # if sizeof(int) == 8: # 32-bit tests on 64-bit arch
  #   runTests(requireGMP = true, test32bit = true)

  # Ensure benchmarks stay relevant. Ignore Windows 32-bit at the moment
  if not defined(windows) or not (existsEnv"UCPU" or getEnv"UCPU" == "i686"):
    buildAllBenches()

task test_no_gmp_no_assembler, "Run tests that don't require GMP using a pure Nim backend":
  # -d:testingCurves is configured in a *.nim.cfg for convenience
  runTests(requireGMP = false, testASM = false)

  # if sizeof(int) == 8: # 32-bit tests on 64-bit arch
  #   runTests(requireGMP = true, test32bit = true)

  # Ensure benchmarks stay relevant. Ignore Windows 32-bit at the moment
  if not defined(windows) or not (existsEnv"UCPU" or getEnv"UCPU" == "i686"):
    buildAllBenches()

task test_parallel, "Run all tests in parallel (via GNU parallel)":
  # -d:testingCurves is configured in a *.nim.cfg for convenience
  clearParallelBuild()
  runTests(requireGMP = true, dumpCmdFile = true)
  exec "parallel --keep-order --group < " & buildParallel

  # if sizeof(int) == 8: # 32-bit tests on 64-bit arch
  #   clearParallelBuild()
  #   runTests(requireGMP = true, dumpCmdFile = true, test32bit = true)
  #   exec "parallel --keep-order --group < " & buildParallel

  # Now run the benchmarks
  #
  # Benchmarks compile
  # ignore Windows 32-bit for the moment
  # Ensure benchmarks stay relevant. Ignore Windows 32-bit at the moment
  if not defined(windows) or not (existsEnv"UCPU" or getEnv"UCPU" == "i686"):
    buildAllBenches()

task test_parallel_no_assembler, "Run all tests (without macro assembler) in parallel (via GNU parallel)":
  # -d:testingCurves is configured in a *.nim.cfg for convenience
  clearParallelBuild()
  runTests(requireGMP = true, dumpCmdFile = true, testASM = false)
  exec "parallel --keep-order --group < " & buildParallel

  # if sizeof(int) == 8: # 32-bit tests on 64-bit arch
  #   clearParallelBuild()
  #   runTests(requireGMP = true, dumpCmdFile = true, test32bit = true, testASM = false)
  #   exec "parallel --keep-order --group < " & buildParallel

  # Now run the benchmarks
  #
  # Benchmarks compile
  # ignore Windows 32-bit for the moment
  # Ensure benchmarks stay relevant. Ignore Windows 32-bit at the moment
  if not defined(windows) or not (existsEnv"UCPU" or getEnv"UCPU" == "i686"):
    buildAllBenches(useASM = false)

task test_parallel_no_gmp, "Run all tests in parallel (via GNU parallel)":
  # -d:testingCurves is configured in a *.nim.cfg for convenience
  clearParallelBuild()
  runTests(requireGMP = false, dumpCmdFile = true)
  exec "parallel --keep-order --group < " & buildParallel

  # if sizeof(int) == 8: # 32-bit tests on 64-bit arch
  #   clearParallelBuild()
  #   runTests(requireGMP = false, dumpCmdFile = true, test32bit = true)
  #   exec "parallel --keep-order --group < " & buildParallel

  # Now run the benchmarks
  #
  # Benchmarks compile
  # ignore Windows 32-bit for the moment
  # Ensure benchmarks stay relevant. Ignore Windows 32-bit at the moment
  if not defined(windows) or not (existsEnv"UCPU" or getEnv"UCPU" == "i686"):
    buildAllBenches()

task test_parallel_no_gmp_no_assembler, "Run all tests in parallel (via GNU parallel)":
  # -d:testingCurves is configured in a *.nim.cfg for convenience
  clearParallelBuild()
  runTests(requireGMP = false, dumpCmdFile = true, testASM = false)
  exec "parallel --keep-order --group < " & buildParallel

  # if sizeof(int) == 8: # 32-bit tests on 64-bit arch
  #   clearParallelBuild()
  #   runTests(requireGMP = false, dumpCmdFile = true, test32bit = true, testASM = false)
  #   exec "parallel --keep-order --group < " & buildParallel

  # Now run the benchmarks
  #
  # Benchmarks compile
  # ignore Windows 32-bit for the moment
  # Ensure benchmarks stay relevant. Ignore Windows 32-bit at the moment
  if not defined(windows) or not (existsEnv"UCPU" or getEnv"UCPU" == "i686"):
    buildAllBenches(useASM = false)

# Finite field 𝔽p
# ------------------------------------------

task bench_fp, "Run benchmark 𝔽p with your default compiler":
  runBench("bench_fp")

task bench_fp_gcc, "Run benchmark 𝔽p with gcc":
  runBench("bench_fp", "gcc")

task bench_fp_clang, "Run benchmark 𝔽p with clang":
  runBench("bench_fp", "clang")

task bench_fp_gcc_noasm, "Run benchmark 𝔽p with gcc - no Assembly":
  runBench("bench_fp", "gcc", useAsm = false)

task bench_fp_clang_noasm, "Run benchmark 𝔽p with clang - no Assembly":
  runBench("bench_fp", "clang", useAsm = false)

# Double-precision field 𝔽pDbl
# ------------------------------------------

task bench_fpdbl, "Run benchmark 𝔽pDbl with your default compiler":
  runBench("bench_fp_double_precision")

task bench_fpdbl_gcc, "Run benchmark 𝔽p with gcc":
  runBench("bench_fp_double_precision", "gcc")

task bench_fpdbl_clang, "Run benchmark 𝔽p with clang":
  runBench("bench_fp_double_precision", "clang")

task bench_fpdbl_gcc_noasm, "Run benchmark 𝔽p with gcc - no Assembly":
  runBench("bench_fp_double_precision", "gcc", useAsm = false)

task bench_fpdbl_clang_noasm, "Run benchmark 𝔽p with clang - no Assembly":
  runBench("bench_fp_double_precision", "clang", useAsm = false)

# Extension field 𝔽p2
# ------------------------------------------

task bench_fp2, "Run benchmark with 𝔽p2 your default compiler":
  runBench("bench_fp2")

task bench_fp2_gcc, "Run benchmark 𝔽p2 with gcc":
  runBench("bench_fp2", "gcc")

task bench_fp2_clang, "Run benchmark 𝔽p2 with clang":
  runBench("bench_fp2", "clang")

task bench_fp2_gcc_noasm, "Run benchmark 𝔽p2 with gcc - no Assembly":
  runBench("bench_fp2", "gcc", useAsm = false)

task bench_fp2_clang_noasm, "Run benchmark 𝔽p2 with clang - no Assembly":
  runBench("bench_fp2", "clang", useAsm = false)

# Extension field 𝔽p4
# ------------------------------------------

task bench_fp4, "Run benchmark with 𝔽p4 your default compiler":
  runBench("bench_fp4")

task bench_fp4_gcc, "Run benchmark 𝔽p4 with gcc":
  runBench("bench_fp4", "gcc")

task bench_fp4_clang, "Run benchmark 𝔽p4 with clang":
  runBench("bench_fp4", "clang")

task bench_fp4_gcc_noasm, "Run benchmark 𝔽p4 with gcc - no Assembly":
  runBench("bench_fp4", "gcc", useAsm = false)

task bench_fp4_clang_noasm, "Run benchmark 𝔽p4 with clang - no Assembly":
  runBench("bench_fp4", "clang", useAsm = false)

# Extension field 𝔽p6
# ------------------------------------------

task bench_fp6, "Run benchmark with 𝔽p6 your default compiler":
  runBench("bench_fp6")

task bench_fp6_gcc, "Run benchmark 𝔽p6 with gcc":
  runBench("bench_fp6", "gcc")

task bench_fp6_clang, "Run benchmark 𝔽p6 with clang":
  runBench("bench_fp6", "clang")

task bench_fp6_gcc_noasm, "Run benchmark 𝔽p6 with gcc - no Assembly":
  runBench("bench_fp6", "gcc", useAsm = false)

task bench_fp6_clang_noasm, "Run benchmark 𝔽p6 with clang - no Assembly":
  runBench("bench_fp6", "clang", useAsm = false)

# Extension field 𝔽p12
# ------------------------------------------

task bench_fp12, "Run benchmark with 𝔽p12 your default compiler":
  runBench("bench_fp12")

task bench_fp12_gcc, "Run benchmark 𝔽p12 with gcc":
  runBench("bench_fp12", "gcc")

task bench_fp12_clang, "Run benchmark 𝔽p12 with clang":
  runBench("bench_fp12", "clang")

task bench_fp12_gcc_noasm, "Run benchmark 𝔽p12 with gcc - no Assembly":
  runBench("bench_fp12", "gcc", useAsm = false)

task bench_fp12_clang_noasm, "Run benchmark 𝔽p12 with clang - no Assembly":
  runBench("bench_fp12", "clang", useAsm = false)

# Elliptic curve G1
# ------------------------------------------

task bench_ec_g1, "Run benchmark on Elliptic Curve group 𝔾1 - Short Weierstrass with Projective Coordinates - Default compiler":
  runBench("bench_ec_g1")

task bench_ec_g1_gcc, "Run benchmark on Elliptic Curve group 𝔾1 - Short Weierstrass with Projective Coordinates - GCC":
  runBench("bench_ec_g1", "gcc")

task bench_ec_g1_clang, "Run benchmark on Elliptic Curve group 𝔾1 - Short Weierstrass with Projective Coordinates - Clang":
  runBench("bench_ec_g1", "clang")

task bench_ec_g1_gcc_noasm, "Run benchmark on Elliptic Curve group 𝔾1 - Short Weierstrass with Projective Coordinates - GCC no Assembly":
  runBench("bench_ec_g1", "gcc", useAsm = false)

task bench_ec_g1_clang_noasm, "Run benchmark on Elliptic Curve group 𝔾1 - Short Weierstrass with Projective Coordinates - Clang no Assembly":
  runBench("bench_ec_g1", "clang", useAsm = false)

# Elliptic curve G2
# ------------------------------------------

task bench_ec_g2, "Run benchmark on Elliptic Curve group 𝔾2 - Short Weierstrass with Projective Coordinates - Default compiler":
  runBench("bench_ec_g2")

task bench_ec_g2_gcc, "Run benchmark on Elliptic Curve group 𝔾2 - Short Weierstrass with Projective Coordinates - GCC":
  runBench("bench_ec_g2", "gcc")

task bench_ec_g2_clang, "Run benchmark on Elliptic Curve group 𝔾2 - Short Weierstrass with Projective Coordinates - Clang":
  runBench("bench_ec_g2", "clang")

task bench_ec_g2_gcc_noasm, "Run benchmark on Elliptic Curve group 𝔾2 - Short Weierstrass with Projective Coordinates - GCC no Assembly":
  runBench("bench_ec_g2", "gcc", useAsm = false)

task bench_ec_g2_clang_noasm, "Run benchmark on Elliptic Curve group 𝔾2 - Short Weierstrass with Projective Coordinates - Clang no Assembly":
  runBench("bench_ec_g2", "clang", useAsm = false)

# Pairings
# ------------------------------------------

task bench_pairing_bls12_377, "Run pairings benchmarks for BLS12-377 - Default compiler":
  runBench("bench_pairing_bls12_377")

task bench_pairing_bls12_377_gcc, "Run pairings benchmarks for BLS12-377 - GCC":
  runBench("bench_pairing_bls12_377", "gcc")

task bench_pairing_bls12_377_clang, "Run pairings benchmarks for BLS12-377 - Clang":
  runBench("bench_pairing_bls12_377", "clang")

task bench_pairing_bls12_377_gcc_noasm, "Run pairings benchmarks for BLS12-377 - GCC no Assembly":
  runBench("bench_pairing_bls12_377", "gcc", useAsm = false)

task bench_pairing_bls12_377_clang_noasm, "Run pairings benchmarks for BLS12-377 - Clang no Assembly":
  runBench("bench_pairing_bls12_377", "clang", useAsm = false)

# --

task bench_pairing_bls12_381, "Run pairings benchmarks for BLS12-381 - Default compiler":
  runBench("bench_pairing_bls12_381")

task bench_pairing_bls12_381_gcc, "Run pairings benchmarks for BLS12-381 - GCC":
  runBench("bench_pairing_bls12_381", "gcc")

task bench_pairing_bls12_381_clang, "Run pairings benchmarks for BLS12-381 - Clang":
  runBench("bench_pairing_bls12_381", "clang")

task bench_pairing_bls12_381_gcc_noasm, "Run pairings benchmarks for BLS12-381 - GCC no Assembly":
  runBench("bench_pairing_bls12_381", "gcc", useAsm = false)

task bench_pairing_bls12_381_clang_noasm, "Run pairings benchmarks for BLS12-381 - Clang no Assembly":
  runBench("bench_pairing_bls12_381", "clang", useAsm = false)

# --

task bench_pairing_bn254_nogami, "Run pairings benchmarks for BN254-Nogami - Default compiler":
  runBench("bench_pairing_bn254_nogami")

task bench_pairing_bn254_nogami_gcc, "Run pairings benchmarks for BN254-Nogami - GCC":
  runBench("bench_pairing_bn254_nogami", "gcc")

task bench_pairing_bn254_nogami_clang, "Run pairings benchmarks for BN254-Nogami - Clang":
  runBench("bench_pairing_bn254_nogami", "clang")

task bench_pairing_bn254_nogami_gcc_noasm, "Run pairings benchmarks for BN254-Nogami - GCC no Assembly":
  runBench("bench_pairing_bn254_nogami", "gcc", useAsm = false)

task bench_pairing_bn254_nogami_clang_noasm, "Run pairings benchmarks for BN254-Nogami - Clang no Assembly":
  runBench("bench_pairing_bn254_nogami", "clang", useAsm = false)

# --

task bench_pairing_bn254_snarks, "Run pairings benchmarks for BN254-Snarks - Default compiler":
  runBench("bench_pairing_bn254_snarks")

task bench_pairing_bn254_snarks_gcc, "Run pairings benchmarks for BN254-Snarks - GCC":
  runBench("bench_pairing_bn254_snarks", "gcc")

task bench_pairing_bn254_snarks_clang, "Run pairings benchmarks for BN254-Snarks - Clang":
  runBench("bench_pairing_bn254_snarks", "clang")

task bench_pairing_bn254_snarks_gcc_noasm, "Run pairings benchmarks for BN254-Snarks - GCC no Assembly":
  runBench("bench_pairing_bn254_snarks", "gcc", useAsm = false)

task bench_pairing_bn254_snarks_clang_noasm, "Run pairings benchmarks for BN254-Snarks - Clang no Assembly":
  runBench("bench_pairing_bn254_snarks", "clang", useAsm = false)


# Curve summaries
# ------------------------------------------

task bench_summary_bls12_377, "Run summary benchmarks for BLS12-377 - Default compiler":
  runBench("bench_summary_bls12_377")

task bench_summary_bls12_377_gcc, "Run summary benchmarks for BLS12-377 - GCC":
  runBench("bench_summary_bls12_377", "gcc")

task bench_summary_bls12_377_clang, "Run summary benchmarks for BLS12-377 - Clang":
  runBench("bench_summary_bls12_377", "clang")

task bench_summary_bls12_377_gcc_noasm, "Run summary benchmarks for BLS12-377 - GCC no Assembly":
  runBench("bench_summary_bls12_377", "gcc", useAsm = false)

task bench_summary_bls12_377_clang_noasm, "Run summary benchmarks for BLS12-377 - Clang no Assembly":
  runBench("bench_summary_bls12_377", "clang", useAsm = false)

# --

task bench_summary_bls12_381, "Run summary benchmarks for BLS12-381 - Default compiler":
  runBench("bench_summary_bls12_381")

task bench_summary_bls12_381_gcc, "Run summary benchmarks for BLS12-381 - GCC":
  runBench("bench_summary_bls12_381", "gcc")

task bench_summary_bls12_381_clang, "Run summary benchmarks for BLS12-381 - Clang":
  runBench("bench_summary_bls12_381", "clang")

task bench_summary_bls12_381_gcc_noasm, "Run summary benchmarks for BLS12-381 - GCC no Assembly":
  runBench("bench_summary_bls12_381", "gcc", useAsm = false)

task bench_summary_bls12_381_clang_noasm, "Run summary benchmarks for BLS12-381 - Clang no Assembly":
  runBench("bench_summary_bls12_381", "clang", useAsm = false)

# --

task bench_summary_bn254_nogami, "Run summary benchmarks for BN254-Nogami - Default compiler":
  runBench("bench_summary_bn254_nogami")

task bench_summary_bn254_nogami_gcc, "Run summary benchmarks for BN254-Nogami - GCC":
  runBench("bench_summary_bn254_nogami", "gcc")

task bench_summary_bn254_nogami_clang, "Run summary benchmarks for BN254-Nogami - Clang":
  runBench("bench_summary_bn254_nogami", "clang")

task bench_summary_bn254_nogami_gcc_noasm, "Run summary benchmarks for BN254-Nogami - GCC no Assembly":
  runBench("bench_summary_bn254_nogami", "gcc", useAsm = false)

task bench_summary_bn254_nogami_clang_noasm, "Run summary benchmarks for BN254-Nogami - Clang no Assembly":
  runBench("bench_summary_bn254_nogami", "clang", useAsm = false)

# --

task bench_summary_bn254_snarks, "Run summary benchmarks for BN254-Snarks - Default compiler":
  runBench("bench_summary_bn254_snarks")

task bench_summary_bn254_snarks_gcc, "Run summary benchmarks for BN254-Snarks - GCC":
  runBench("bench_summary_bn254_snarks", "gcc")

task bench_summary_bn254_snarks_clang, "Run summary benchmarks for BN254-Snarks - Clang":
  runBench("bench_summary_bn254_snarks", "clang")

task bench_summary_bn254_snarks_gcc_noasm, "Run summary benchmarks for BN254-Snarks - GCC no Assembly":
  runBench("bench_summary_bn254_snarks", "gcc", useAsm = false)

task bench_summary_bn254_snarks_clang_noasm, "Run summary benchmarks for BN254-Snarks - Clang no Assembly":
  runBench("bench_summary_bn254_snarks", "clang", useAsm = false)

# --

task bench_summary_pasta, "Run summary benchmarks for the Pasta curves - Default compiler":
  runBench("bench_summary_pasta")

task bench_summary_pasta_gcc, "Run summary benchmarks for the Pasta curves - GCC":
  runBench("bench_summary_pasta", "gcc")

task bench_summary_pasta_clang, "Run summary benchmarks for the Pasta curves - Clang":
  runBench("bench_summary_pasta", "clang")

task bench_summary_pasta_gcc_noasm, "Run summary benchmarks for the Pasta curves - GCC no Assembly":
  runBench("bench_summary_pasta", "gcc", useAsm = false)

task bench_summary_pasta_clang_noasm, "Run summary benchmarks for the Pasta curves - Clang no Assembly":
  runBench("bench_summary_pasta", "clang", useAsm = false)

# Hashes
# ------------------------------------------

task bench_sha256, "Run SHA256 benchmarks":
  runBench("bench_sha256")

# Hash-to-curve
# ------------------------------------------
task bench_hash_to_curve, "Run Hash-to-Curve benchmarks":
  runBench("bench_hash_to_curve")

task bench_hash_to_curve_gcc, "Run Hash-to-Curve benchmarks":
  runBench("bench_hash_to_curve", "gcc")

task bench_hash_to_curve_clang, "Run Hash-to-Curve benchmarks":
  runBench("bench_hash_to_curve", "clang")

task bench_hash_to_curve_gcc_noasm, "Run Hash-to-Curve benchmarks":
  runBench("bench_hash_to_curve", "gcc", useAsm = false)

task bench_hash_to_curve_clang_noasm, "Run Hash-to-Curve benchmarks":
  runBench("bench_hash_to_curve", "clang", useAsm = false)

# BLS signatures
# ------------------------------------------
task bench_blssig_on_bls12_381_g2, "Run Hash-to-Curve benchmarks":
  runBench("bench_blssig_on_bls12_381_g2")

task bench_blssig_on_bls12_381_g2_gcc, "Run Hash-to-Curve benchmarks":
  runBench("bench_blssig_on_bls12_381_g2", "gcc")

task bench_blssig_on_bls12_381_g2_clang, "Run Hash-to-Curve benchmarks":
  runBench("bench_blssig_on_bls12_381_g2", "clang")

task bench_blssig_on_bls12_381_g2_gcc_noasm, "Run Hash-to-Curve benchmarks":
  runBench("bench_blssig_on_bls12_381_g2", "gcc", useAsm = false)

task bench_blssig_on_bls12_381_g2_clang_noasm, "Run Hash-to-Curve benchmarks":
  runBench("bench_blssig_on_bls12_381_g2", "clang", useAsm = false)
