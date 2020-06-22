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
  ("tests/t_finite_fields_mulsquare.nim", false),
  ("tests/t_finite_fields_sqrt.nim", false),
  ("tests/t_finite_fields_powinv.nim", false),
  ("tests/t_finite_fields_vs_gmp.nim", true),
  # Precompute
  ("tests/t_precomputed", false),
  # Towers of extension fields
  ("tests/t_fp2.nim", false),
  ("tests/t_fp2_sqrt.nim", false),
  ("tests/t_fp6_bn254_snarks.nim", false),
  ("tests/t_fp6_bls12_377.nim", false),
  ("tests/t_fp6_bls12_381.nim", false),
  ("tests/t_fp12_bn254_snarks.nim", false),
  ("tests/t_fp12_bls12_377.nim", false),
  ("tests/t_fp12_bls12_381.nim", false),
  # Elliptic curve arithmetic G1
  ("tests/t_ec_wstrass_prj_g1_add_double.nim", false),
  ("tests/t_ec_wstrass_prj_g1_mul_sanity.nim", false),
  ("tests/t_ec_wstrass_prj_g1_mul_distri.nim", false),
  ("tests/t_ec_wstrass_prj_g1_mul_vs_ref.nim", false),
  # Elliptic curve arithmetic G2
  ("tests/t_ec_wstrass_prj_g2_add_double_bn254_snarks.nim", false),
  ("tests/t_ec_wstrass_prj_g2_mul_sanity_bn254_snarks.nim", false),
  ("tests/t_ec_wstrass_prj_g2_mul_distri_bn254_snarks.nim", false),
  ("tests/t_ec_wstrass_prj_g2_mul_vs_ref_bn254_snarks.nim", false),

  ("tests/t_ec_wstrass_prj_g2_add_double_bls12_381.nim", false),
  ("tests/t_ec_wstrass_prj_g2_mul_sanity_bls12_381.nim", false),
  ("tests/t_ec_wstrass_prj_g2_mul_distri_bls12_381.nim", false),
  ("tests/t_ec_wstrass_prj_g2_mul_vs_ref_bls12_381.nim", false),
  # Elliptic curve arithmetic vs Sagemath
  ("tests/t_ec_sage_bn254.nim", false),
  ("tests/t_ec_sage_bls12_381.nim", false),
  # Edge cases highlighted by past bugs
  ("tests/t_ec_wstrass_prj_edge_cases.nim", false)
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

  let command = "nim " & lang & cc & " " & flags & " --verbosity:0 --outdir:build -r --hints:off --warnings:off " & path

  if not commandFile:
    echo "\n=============================================================================================="
    echo "Running [flags: ", flags, "] ", path
    echo "=============================================================================================="
    exec command
  else:
    # commandFile.writeLine command
    exec "echo \'" & command & "\' >> " & buildParallel

proc runBench(benchName: string, compiler = "") =
  if not dirExists "build":
    mkDir "build"

  var cc = ""
  if compiler != "":
    cc = "--cc:" & compiler
  exec "nim c " & cc &
       " -d:danger --verbosity:0 -o:build/" & benchName & "_" & compiler &
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

task bench_fp, "Run benchmark 𝔽p with your default compiler":
  runBench("bench_fp")

task bench_fp_gcc, "Run benchmark 𝔽p with gcc":
  runBench("bench_fp", "gcc")

task bench_fp_clang, "Run benchmark 𝔽p with clang":
  runBench("bench_fp", "clang")

task bench_fp2, "Run benchmark with 𝔽p2 your default compiler":
  runBench("bench_fp2")

task bench_fp2_gcc, "Run benchmark 𝔽p2 with gcc":
  runBench("bench_fp2", "gcc")

task bench_fp2_clang, "Run benchmark 𝔽p2 with clang":
  runBench("bench_fp2", "clang")

task bench_fp6, "Run benchmark with 𝔽p6 your default compiler":
  runBench("bench_fp6")

task bench_fp6_gcc, "Run benchmark 𝔽p6 with gcc":
  runBench("bench_fp6", "gcc")

task bench_fp6_clang, "Run benchmark 𝔽p6 with clang":
  runBench("bench_fp6", "clang")

task bench_fp12, "Run benchmark with 𝔽p12 your default compiler":
  runBench("bench_fp12")

task bench_fp12_gcc, "Run benchmark 𝔽p12 with gcc":
  runBench("bench_fp12", "gcc")

task bench_fp12_clang, "Run benchmark 𝔽p12 with clang":
  runBench("bench_fp12", "clang")

task bench_ec_g1, "Run benchmark on Elliptic Curve group 𝔾1 - Short Weierstrass with Projective Coordinates - GCC":
  runBench("bench_ec_g1")

task bench_ec_g1_gcc, "Run benchmark on Elliptic Curve group 𝔾1 - Short Weierstrass with Projective Coordinates - GCC":
  runBench("bench_ec_g1", "gcc")

task bench_ec_g1_clang, "Run benchmark on Elliptic Curve group 𝔾1 - Short Weierstrass with Projective Coordinates - Clang":
  runBench("bench_ec_g1", "clang")

task bench_ec_g2, "Run benchmark on Elliptic Curve group 𝔾2 - Short Weierstrass with Projective Coordinates - GCC":
  runBench("bench_ec_g2")

task bench_ec_g2_gcc, "Run benchmark on Elliptic Curve group 𝔾2 - Short Weierstrass with Projective Coordinates - GCC":
  runBench("bench_ec_g2", "gcc")

task bench_ec_g2_clang, "Run benchmark on Elliptic Curve group 𝔾2 - Short Weierstrass with Projective Coordinates - Clang":
  runBench("bench_ec_g2", "clang")
