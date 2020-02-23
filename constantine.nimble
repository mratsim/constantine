packageName   = "constantine"
version       = "0.0.1"
author        = "Status Research & Development GmbH"
description   = "This library provides constant time big int primitives."
license       = "MIT or Apache License 2.0"
srcDir        = "src"

### Dependencies
requires "nim >= 1.1.0"

### Helper functions
proc test(path: string) =
  if not dirExists "build":
    mkDir "build"
  # Compilation language is controlled by WEAVE_TEST_LANG
  var lang = "c"
  if existsEnv"TEST_LANG":
    lang = getEnv"TEST_LANG"

  echo "\n========================================================================================"
  echo "Running ", path
  echo "========================================================================================"
  exec "nim " & lang & " --verbosity:0 --outdir:build -r --hints:off --warnings:off " & path

### tasks
task test, "Run all tests":
  # -d:testingCurves is configured in a *.nim.cfg for convenience
  test "",                  "tests/test_primitives.nim"
  test "",                  "tests/test_io_bigints.nim"
  test "",                  "tests/test_bigints.nim"
  test "",                  "tests/test_bigints_multimod.nim"
  test "",                  "tests/test_bigints_vs_gmp.nim"
  test "",                  "tests/test_finite_fields.nim"
  test "",                  "tests/test_finite_fields_vs_gmp.nim"
  test "",                  "tests/test_finite_fields_powinv.nim"

task test_no_gmp, "Run tests that don't require GMP":
  # -d:testingCurves is configured in a *.nim.cfg for convenience
  test "",                  "tests/test_primitives.nim"
  test "",                  "tests/test_io_bigints.nim"
  test "",                  "tests/test_bigints.nim"
  test "",                  "tests/test_bigints_multimod.nim"
  test "",                  "tests/test_finite_fields.nim"
  test "",                  "tests/test_finite_fields_powinv.nim"
