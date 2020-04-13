import system except getCommand, setCommand, switch, `--`,
  packageName, version, author, description, license, srcDir, binDir, backend,
  skipDirs, skipFiles, skipExt, installDirs, installFiles, installExt, bin, foreignDeps,
  requires, task, packageName
import nimscriptapi, strutils
packageName   = "constantine"
version       = "0.0.1"
author        = "Status Research & Development GmbH"
description   = "This library provides constant time big int primitives."
license       = "MIT or Apache License 2.0"
srcDir        = "src"

### Dependencies
requires "nim >= 1.1.0"

### Helper functions
proc test(flags, path: string) =
  if not dirExists "build":
    mkDir "build"
  # Compilation language is controlled by WEAVE_TEST_LANG
  var lang = "c"
  if existsEnv"TEST_LANG":
    lang = getEnv"TEST_LANG"

  var cc = ""
  if existsEnv"CC":
    cc = " --cc:" & getEnv"CC"

  echo "\n========================================================================================"
  echo "Running [flags: ", flags, "] ", path
  echo "========================================================================================"
  exec "nim " & lang & cc & " " & flags & " --verbosity:0 --outdir:build -r --hints:off --warnings:off " & path

### tasks
task test, "Run all tests":
  # -d:testingCurves is configured in a *.nim.cfg for convenience

  # Primitives
  test "", "tests/test_primitives.nim"

  # Big ints
  test "", "tests/test_io_bigints.nim"
  test "", "tests/test_bigints.nim"
  test "", "tests/test_bigints_multimod.nim"

  test "", "tests/test_bigints_vs_gmp.nim"

  # Field
  test "", "tests/test_io_fields"
  test "", "tests/test_finite_fields.nim"
  test "", "tests/test_finite_fields_mulsquare.nim"
  test "", "tests/test_finite_fields_sqrt.nim"
  test "", "tests/test_finite_fields_powinv.nim"

  test "", "tests/test_finite_fields_vs_gmp.nim"

  # Towers of extension fields
  test "", "tests/test_fp2.nim"
  test "", "tests/test_fp6.nim"
  test "", "tests/test_fp12.nim"

  # Elliptic curve arithmetic
  test "", "tests/test_ec_weierstrass_projective_g1.nim"

  if sizeof(int) == 8: # 32-bit tests on 64-bit arch
    # Primitives
    test "-d:Constantine32", "tests/test_primitives.nim"

    # Big ints
    test "-d:Constantine32", "tests/test_io_bigints.nim"
    test "-d:Constantine32", "tests/test_bigints.nim"
    test "-d:Constantine32", "tests/test_bigints_multimod.nim"

    test "-d:Constantine32", "tests/test_bigints_vs_gmp.nim"

    # Field
    test "-d:Constantine32", "tests/test_io_fields"
    test "-d:Constantine32", "tests/test_finite_fields.nim"
    test "-d:Constantine32", "tests/test_finite_fields_mulsquare.nim"
    test "-d:Constantine32", "tests/test_finite_fields_sqrt.nim"
    test "-d:Constantine32", "tests/test_finite_fields_powinv.nim"

    test "-d:Constantine32", "tests/test_finite_fields_vs_gmp.nim"

    # Towers of extension fields
    test "-d:Constantine32", "tests/test_fp2.nim"
    test "-d:Constantine32", "tests/test_fp6.nim"
    test "-d:Constantine32", "tests/test_fp12.nim"

    # Elliptic curve arithmetic
    test "-d:Constantine32", "tests/test_ec_weierstrass_projective_g1.nim"

task test_no_gmp, "Run tests that don't require GMP":
  # -d:testingCurves is configured in a *.nim.cfg for convenience

  # Primitives
  test "", "tests/test_primitives.nim"

  # Big ints
  test "", "tests/test_io_bigints.nim"
  test "", "tests/test_bigints.nim"
  test "", "tests/test_bigints_multimod.nim"

  # Field
  test "", "tests/test_io_fields"
  test "", "tests/test_finite_fields.nim"
  test "", "tests/test_finite_fields_mulsquare.nim"
  test "", "tests/test_finite_fields_sqrt.nim"
  test "", "tests/test_finite_fields_powinv.nim"

  # Towers of extension fields
  test "", "tests/test_fp2.nim"
  test "", "tests/test_fp6.nim"
  test "", "tests/test_fp12.nim"

  # Elliptic curve arithmetic
  test "", "tests/test_ec_weierstrass_projective_g1.nim"

  if sizeof(int) == 8: # 32-bit tests
    # Primitives
    test "-d:Constantine32", "tests/test_primitives.nim"

    # Big ints
    test "-d:Constantine32", "tests/test_io_bigints.nim"
    test "-d:Constantine32", "tests/test_bigints.nim"
    test "-d:Constantine32", "tests/test_bigints_multimod.nim"

    # Field
    test "-d:Constantine32", "tests/test_io_fields"
    test "-d:Constantine32", "tests/test_finite_fields.nim"
    test "-d:Constantine32", "tests/test_finite_fields_mulsquare.nim"
    test "-d:Constantine32", "tests/test_finite_fields_sqrt.nim"
    test "-d:Constantine32", "tests/test_finite_fields_powinv.nim"

    # Towers of extension fields
    test "-d:Constantine32", "tests/test_fp2.nim"
    test "-d:Constantine32", "tests/test_fp6.nim"
    test "-d:Constantine32", "tests/test_fp12.nim"

    # Elliptic curve arithmetic
    test "-d:Constantine32", "tests/test_ec_weierstrass_projective_g1.nim"

proc runBench(benchName: string, compiler = "") =
  if not dirExists "build":
    mkDir "build"

  var cc = ""
  if compiler != "":
    cc = "--cc:" & compiler
  exec "nim c " & cc &
       " -d:danger --verbosity:0 -o:build/" & benchName & "_" & compiler &
       " -r --hints:off --warnings:off benchmarks/" & benchName & ".nim"

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

onExit()
