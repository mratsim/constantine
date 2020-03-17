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
  test "", "tests/test_finite_fields_powinv.nim"

  test "", "tests/test_finite_fields_vs_gmp.nim"

  # 𝔽p2
  test "", "tests/test_fp2.nim"

  if sizeof(int) == 8: # 32-bit tests
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
    test "-d:Constantine32", "tests/test_finite_fields_powinv.nim"

    test "-d:Constantine32", "tests/test_finite_fields_vs_gmp.nim"

    # 𝔽p2
    test "", "tests/test_fp2.nim"

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
  test "", "tests/test_finite_fields_powinv.nim"

  # 𝔽p2
  test "", "tests/test_fp2.nim"

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
    test "-d:Constantine32", "tests/test_finite_fields_powinv.nim"

    # 𝔽p2
    test "", "tests/test_fp2.nim"
