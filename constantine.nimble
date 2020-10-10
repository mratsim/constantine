packageName   = "constantine"
version       = "0.0.1"
author        = "Status Research & Development GmbH"
description   = "This library provides constant time big int primitives."
license       = "MIT or Apache License 2.0"
srcDir        = "src"

# Dependencies
# ----------------------------------------------------------------

requires "nim >= 1.1.0"

# Test config
# ----------------------------------------------------------------

const buildParallel = "test_parallel.txt"

const testDesc: seq[tuple[path: string, useGMP: bool]] = @[
  # Primitives
  ("tests/t_primitives.nim", false),
  ("tests/t_primitives_extended_precision.nim", false),
  # Big ints
  ("tests/t_io_bigints.nim", false),
  ("tests/t_bigints.nim", false),
  ("tests/t_bigints_multimod.nim", false),
  ("tests/t_bigints_mod_vs_gmp.nim", true),
  ("tests/t_bigints_mul_vs_gmp.nim", true),
  ("tests/t_bigints_mul_high_words_vs_gmp.nim", true),
  # Field
  ("tests/t_io_fields", false),
  ("tests/t_finite_fields.nim", false),
  ("tests/t_finite_fields_conditional_arithmetic.nim", false),
  ("tests/t_finite_fields_mulsquare.nim", false),
  ("tests/t_finite_fields_sqrt.nim", false),
  ("tests/t_finite_fields_powinv.nim", false),
  ("tests/t_finite_fields_vs_gmp.nim", true),
  ("tests/t_fp_cubic_root.nim", false),
  # Double-width finite fields
  ("tests/t_finite_fields_double_width.nim", false),
  # Towers of extension fields
  ("tests/t_fp2.nim", false),
  ("tests/t_fp2_sqrt.nim", false),
  ("tests/t_fp6_bn254_snarks.nim", false),
  ("tests/t_fp6_bls12_377.nim", false),
  ("tests/t_fp6_bls12_381.nim", false),
  ("tests/t_fp6_bw6_761.nim", false),
  ("tests/t_fp12_bn254_snarks.nim", false),
  ("tests/t_fp12_bls12_377.nim", false),
  ("tests/t_fp12_bls12_381.nim", false),
  ("tests/t_fp12_exponentiation.nim", false),

  ("tests/t_fp4_frobenius.nim", false),
  # Elliptic curve arithmetic G1
  ("tests/t_ec_shortw_prj_g1_add_double.nim", false),
  ("tests/t_ec_shortw_prj_g1_mul_sanity.nim", false),
  ("tests/t_ec_shortw_prj_g1_mul_distri.nim", false),
  ("tests/t_ec_shortw_prj_g1_mul_vs_ref.nim", false),
  ("tests/t_ec_shortw_prj_g1_mixed_add.nim", false),

  ("tests/t_ec_shortw_jac_g1_add_double.nim", false),
  ("tests/t_ec_shortw_jac_g1_mul_sanity.nim", false),
  ("tests/t_ec_shortw_jac_g1_mul_distri.nim", false),
  ("tests/t_ec_shortw_jac_g1_mul_vs_ref.nim", false),
  # mixed_add

  # Elliptic curve arithmetic G2
  ("tests/t_ec_shortw_prj_g2_add_double_bn254_snarks.nim", false),
  ("tests/t_ec_shortw_prj_g2_mul_sanity_bn254_snarks.nim", false),
  ("tests/t_ec_shortw_prj_g2_mul_distri_bn254_snarks.nim", false),
  ("tests/t_ec_shortw_prj_g2_mul_vs_ref_bn254_snarks.nim", false),
  ("tests/t_ec_shortw_prj_g2_mixed_add_bn254_snarks.nim", false),

  ("tests/t_ec_shortw_prj_g2_add_double_bls12_381.nim", false),
  ("tests/t_ec_shortw_prj_g2_mul_sanity_bls12_381.nim", false),
  ("tests/t_ec_shortw_prj_g2_mul_distri_bls12_381.nim", false),
  ("tests/t_ec_shortw_prj_g2_mul_vs_ref_bls12_381.nim", false),
  ("tests/t_ec_shortw_prj_g2_mixed_add_bls12_381.nim", false),

  ("tests/t_ec_shortw_prj_g2_add_double_bls12_377.nim", false),
  ("tests/t_ec_shortw_prj_g2_mul_sanity_bls12_377.nim", false),
  ("tests/t_ec_shortw_prj_g2_mul_distri_bls12_377.nim", false),
  ("tests/t_ec_shortw_prj_g2_mul_vs_ref_bls12_377.nim", false),
  ("tests/t_ec_shortw_prj_g2_mixed_add_bls12_377.nim", false),

  ("tests/t_ec_shortw_prj_g2_add_double_bw6_761.nim", false),
  ("tests/t_ec_shortw_prj_g2_mul_sanity_bw6_761.nim", false),
  ("tests/t_ec_shortw_prj_g2_mul_distri_bw6_761.nim", false),
  ("tests/t_ec_shortw_prj_g2_mul_vs_ref_bw6_761.nim", false),
  ("tests/t_ec_shortw_prj_g2_mixed_add_bw6_761.nim", false),

  ("tests/t_ec_shortw_jac_g2_add_double_bn254_snarks.nim", false),
  ("tests/t_ec_shortw_jac_g2_mul_sanity_bn254_snarks.nim", false),
  ("tests/t_ec_shortw_jac_g2_mul_distri_bn254_snarks.nim", false),
  ("tests/t_ec_shortw_jac_g2_mul_vs_ref_bn254_snarks.nim", false),
  # mixed_add

  ("tests/t_ec_shortw_jac_g2_add_double_bls12_381.nim", false),
  ("tests/t_ec_shortw_jac_g2_mul_sanity_bls12_381.nim", false),
  ("tests/t_ec_shortw_jac_g2_mul_distri_bls12_381.nim", false),
  ("tests/t_ec_shortw_jac_g2_mul_vs_ref_bls12_381.nim", false),
  # mixed_add

  ("tests/t_ec_shortw_jac_g2_add_double_bls12_377.nim", false),
  ("tests/t_ec_shortw_jac_g2_mul_sanity_bls12_377.nim", false),
  ("tests/t_ec_shortw_jac_g2_mul_distri_bls12_377.nim", false),
  ("tests/t_ec_shortw_jac_g2_mul_vs_ref_bls12_377.nim", false),
  # mixed_add

  ("tests/t_ec_shortw_jac_g2_add_double_bw6_761.nim", false),
  ("tests/t_ec_shortw_jac_g2_mul_sanity_bw6_761.nim", false),
  ("tests/t_ec_shortw_jac_g2_mul_distri_bw6_761.nim", false),
  ("tests/t_ec_shortw_jac_g2_mul_vs_ref_bw6_761.nim", false),
  # mixed_add

  # Elliptic curve arithmetic vs Sagemath
  ("tests/t_ec_frobenius.nim", false),
  ("tests/t_ec_sage_bn254_nogami.nim", false),
  ("tests/t_ec_sage_bn254_snarks.nim", false),
  ("tests/t_ec_sage_bls12_377.nim", false),
  ("tests/t_ec_sage_bls12_381.nim", false),
  # Edge cases highlighted by past bugs
  ("tests/t_ec_shortw_prj_edge_cases.nim", false),
  # Pairing
  ("tests/t_pairing_bls12_377_line_functions.nim", false),
  ("tests/t_pairing_bls12_381_line_functions.nim", false),
  ("tests/t_pairing_mul_fp12_by_lines.nim", false),
  ("tests/t_pairing_cyclotomic_fp12.nim", false),
  ("tests/t_pairing_bn254_nogami_optate.nim", false),
  ("tests/t_pairing_bn254_snarks_optate.nim", false),
  ("tests/t_pairing_bls12_377_optate.nim", false),
  ("tests/t_pairing_bls12_381_optate.nim", false),
]

# For temporary (hopefully) investigation that can only be reproduced in CI
const useDebug = [
  "tests/t_bigints.nim"
]


# Helper functions
# ----------------------------------------------------------------

proc test(flags, path: string, commandFile = false) =
  # commandFile should be a "file" but Nimscript doesn't support IO
  # TODO: use a proper runner
  if not dirExists "build":
    mkDir "build"
  # Compilation language is controlled by WEAVE_TEST_LANG
  var lang = "c"
  if existsEnv"TEST_LANG":
    lang = getEnv"TEST_LANG"

  var cc = ""
  if existsEnv"CC":
    cc = " --cc:" & getEnv"CC"

  let command = "nim " & lang & cc & " " & flags &
    " --verbosity:0 --outdir:build/testsuite -r --hints:off --warnings:off " &
    " --nimcache:nimcache/" & path & " " &
    path

  if not commandFile:
    echo "\n=============================================================================================="
    echo "Running [flags: ", flags, "] ", path
    echo "=============================================================================================="
    exec command
  else:
    # commandFile.writeLine command
    exec "echo \'" & command & "\' >> " & buildParallel

proc runBench(benchName: string, compiler = "", useAsm = true) =
  if not dirExists "build":
    mkDir "build"

  var cc = ""
  if compiler != "":
    cc = "--cc:" & compiler
  if not useAsm:
    cc &= " -d:ConstantineASM=false"
  exec "nim c " & cc &
       " -d:danger --verbosity:0 -o:build/bench/" & benchName & "_" & compiler & "_" & (if useAsm: "useASM" else: "noASM") &
       " --nimcache:nimcache/" & benchName & "_" & compiler & "_" & (if useAsm: "useASM" else: "noASM") &
       " -r --hints:off --warnings:off benchmarks/" & benchName & ".nim"

# Tasks
# ----------------------------------------------------------------

task test, "Run all tests":
  # -d:testingCurves is configured in a *.nim.cfg for convenience

  for td in testDesc:
    if td.path in useDebug:
      test "-d:debugConstantine", td.path
    else:
      test "", td.path

  if sizeof(int) == 8: # 32-bit tests on 64-bit arch
    for td in testDesc:
      if td.path in useDebug:
        test "-d:Constantine32 -d:debugConstantine", td.path
      else:
        test "-d:Constantine32", td.path

  # Ensure benchmarks stay relevant. Ignore Windows 32-bit at the moment
  if not defined(windows) or not (existsEnv"UCPU" or getEnv"UCPU" == "i686"):
    runBench("bench_fp")
    runBench("bench_fp_double_width")
    runBench("bench_fp2")
    runBench("bench_fp6")
    runBench("bench_fp12")
    runBench("bench_ec_g1")
    runBench("bench_ec_g2")
    runBench("bench_pairing_bls12_377")
    runBench("bench_pairing_bls12_381")
    runBench("bench_pairing_bn254_nogami")
    runBench("bench_pairing_bn254_snarks")

task test_no_gmp, "Run tests that don't require GMP":
  # -d:testingCurves is configured in a *.nim.cfg for convenience
  for td in testDesc:
    if not td.useGMP:
      if td.path in useDebug:
        test "-d:debugConstantine", td.path
      else:
        test "", td.path

  if sizeof(int) == 8: # 32-bit tests on 64-bit arch
    for td in testDesc:
      if not td.useGMP:
        if td.path in useDebug:
          test "-d:Constantine32 -d:debugConstantine", td.path
        else:
          test "-d:Constantine32", td.path

  # Ensure benchmarks stay relevant. Ignore Windows 32-bit at the moment
  if not defined(windows) or not (existsEnv"UCPU" or getEnv"UCPU" == "i686"):
    runBench("bench_fp")
    runBench("bench_fp2")
    runBench("bench_fp6")
    runBench("bench_fp12")
    runBench("bench_ec_g1")
    runBench("bench_ec_g2")
    runBench("bench_pairing_bls12_377")
    runBench("bench_pairing_bls12_381")
    runBench("bench_pairing_bn254_nogami")
    runBench("bench_pairing_bn254_snarks")

task test_parallel, "Run all tests in parallel (via GNU parallel)":
  # -d:testingCurves is configured in a *.nim.cfg for convenience
  let cmdFile = true # open(buildParallel, mode = fmWrite) # Nimscript doesn't support IO :/
  exec "> " & buildParallel

  for td in testDesc:
    if td.path in useDebug:
      test "-d:debugConstantine", td.path, cmdFile
    else:
      test "", td.path, cmdFile

  # cmdFile.close()
  # Execute everything in parallel with GNU parallel
  exec "parallel --keep-order --group < " & buildParallel

  exec "> " & buildParallel
  if sizeof(int) == 8: # 32-bit tests on 64-bit arch
    for td in testDesc:
      if td.path in useDebug:
        test "-d:Constantine32 -d:debugConstantine", td.path, cmdFile
      else:
        test "-d:Constantine32", td.path, cmdFile
    # cmdFile.close()
    # Execute everything in parallel with GNU parallel
    exec "parallel --keep-order --group < " & buildParallel

  # Now run the benchmarks
  #
  # Benchmarks compile and run
  # ignore Windows 32-bit for the moment
  # Ensure benchmarks stay relevant. Ignore Windows 32-bit at the moment
  if not defined(windows) or not (existsEnv"UCPU" or getEnv"UCPU" == "i686"):
    runBench("bench_fp")
    runBench("bench_fp2")
    runBench("bench_fp6")
    runBench("bench_fp12")
    runBench("bench_ec_g1")
    runBench("bench_ec_g2")
    runBench("bench_pairing_bls12_377")
    runBench("bench_pairing_bls12_381")
    runBench("bench_pairing_bn254_nogami")
    runBench("bench_pairing_bn254_snarks")

task test_parallel_no_assembler, "Run all tests (without macro assembler) in parallel (via GNU parallel)":
  # -d:testingCurves is configured in a *.nim.cfg for convenience
  let cmdFile = true # open(buildParallel, mode = fmWrite) # Nimscript doesn't support IO :/
  exec "> " & buildParallel

  for td in testDesc:
    if td.path in useDebug:
      test "-d:debugConstantine -d:ConstantineASM=false", td.path, cmdFile
    else:
      test " -d:ConstantineASM=false", td.path, cmdFile

  # cmdFile.close()
  # Execute everything in parallel with GNU parallel
  exec "parallel --keep-order --group < " & buildParallel

  exec "> " & buildParallel
  if sizeof(int) == 8: # 32-bit tests on 64-bit arch
    for td in testDesc:
      if td.path in useDebug:
        test "-d:Constantine32 -d:debugConstantine -d:ConstantineASM=false", td.path, cmdFile
      else:
        test "-d:Constantine32 -d:ConstantineASM=false", td.path, cmdFile
    # cmdFile.close()
    # Execute everything in parallel with GNU parallel
    exec "parallel --keep-order --group < " & buildParallel

  # Now run the benchmarks
  #
  # Benchmarks compile and run
  # ignore Windows 32-bit for the moment
  # Ensure benchmarks stay relevant. Ignore Windows 32-bit at the moment
  if not defined(windows) or not (existsEnv"UCPU" or getEnv"UCPU" == "i686"):
    runBench("bench_fp")
    runBench("bench_fp2")
    runBench("bench_fp6")
    runBench("bench_fp12")
    runBench("bench_ec_g1")
    runBench("bench_ec_g2")
    runBench("bench_pairing_bls12_377")
    runBench("bench_pairing_bls12_381")
    runBench("bench_pairing_bn254_nogami")
    runBench("bench_pairing_bn254_snarks")

task test_parallel_no_gmp, "Run all tests in parallel (via GNU parallel)":
  # -d:testingCurves is configured in a *.nim.cfg for convenience
  let cmdFile = true # open(buildParallel, mode = fmWrite) # Nimscript doesn't support IO :/
  exec "> " & buildParallel

  for td in testDesc:
    if not td.useGMP:
      if td.path in useDebug:
        test "-d:debugConstantine", td.path, cmdFile
      else:
        test "", td.path, cmdFile

  # cmdFile.close()
  # Execute everything in parallel with GNU parallel
  exec "parallel --keep-order --group < " & buildParallel

  exec "> " & buildParallel
  if sizeof(int) == 8: # 32-bit tests on 64-bit arch
    for td in testDesc:
      if not td.useGMP:
        if td.path in useDebug:
          test "-d:Constantine32 -d:debugConstantine", td.path, cmdFile
        else:
          test "-d:Constantine32", td.path, cmdFile
    # cmdFile.close()
    # Execute everything in parallel with GNU parallel
    exec "parallel --keep-order --group < " & buildParallel

  # Now run the benchmarks
  #
  # Benchmarks compile and run
  # ignore Windows 32-bit for the moment
  # Ensure benchmarks stay relevant. Ignore Windows 32-bit at the moment
  if not defined(windows) or not (existsEnv"UCPU" or getEnv"UCPU" == "i686"):
    runBench("bench_fp")
    runBench("bench_fp2")
    runBench("bench_fp6")
    runBench("bench_fp12")
    runBench("bench_ec_g1")
    runBench("bench_ec_g2")
    runBench("bench_pairing_bls12_377")
    runBench("bench_pairing_bls12_381")
    runBench("bench_pairing_bn254_nogami")
    runBench("bench_pairing_bn254_snarks")

task test_parallel_no_gmp_no_assembler, "Run all tests in parallel (via GNU parallel)":
  # -d:testingCurves is configured in a *.nim.cfg for convenience
  let cmdFile = true # open(buildParallel, mode = fmWrite) # Nimscript doesn't support IO :/
  exec "> " & buildParallel

  for td in testDesc:
    if not td.useGMP:
      if td.path in useDebug:
        test "-d:debugConstantine -d:ConstantineASM=false", td.path, cmdFile
      else:
        test "-d:ConstantineASM=false", td.path, cmdFile

  # cmdFile.close()
  # Execute everything in parallel with GNU parallel
  exec "parallel --keep-order --group < " & buildParallel

  exec "> " & buildParallel
  if sizeof(int) == 8: # 32-bit tests on 64-bit arch
    for td in testDesc:
      if not td.useGMP:
        if td.path in useDebug:
          test "-d:Constantine32 -d:debugConstantine", td.path, cmdFile
        else:
          test "-d:Constantine32", td.path, cmdFile
    # cmdFile.close()
    # Execute everything in parallel with GNU parallel
    exec "parallel --keep-order --group < " & buildParallel

  # Now run the benchmarks
  #
  # Benchmarks compile and run
  # ignore Windows 32-bit for the moment
  # Ensure benchmarks stay relevant. Ignore Windows 32-bit at the moment
  if not defined(windows) or not (existsEnv"UCPU" or getEnv"UCPU" == "i686"):
    runBench("bench_fp")
    runBench("bench_fp2")
    runBench("bench_fp6")
    runBench("bench_fp12")
    runBench("bench_ec_g1")
    runBench("bench_ec_g2")
    runBench("bench_pairing_bls12_377")
    runBench("bench_pairing_bls12_381")
    runBench("bench_pairing_bn254_nogami")
    runBench("bench_pairing_bn254_snarks")

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

task bench_fpdbl, "Run benchmark 𝔽pDbl with your default compiler":
  runBench("bench_fp_double_width")

task bench_fpdbl_gcc, "Run benchmark 𝔽p with gcc":
  runBench("bench_fp_double_width", "gcc")

task bench_fpdbl_clang, "Run benchmark 𝔽p with clang":
  runBench("bench_fp_double_width", "clang")

task bench_fpdbl_gcc_noasm, "Run benchmark 𝔽p with gcc - no Assembly":
  runBench("bench_fp_double_width", "gcc", useAsm = false)

task bench_fpdbl_clang_noasm, "Run benchmark 𝔽p with clang - no Assembly":
  runBench("bench_fp_double_width", "clang", useAsm = false)

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
