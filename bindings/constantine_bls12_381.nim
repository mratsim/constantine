# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/os,
  ./gen_bindings, gen_header

type
  bls12381_fr = Fr[BLS12_381]
  bls12381_fp = Fp[BLS12_381]

let cBindings {.compileTime.} = collectBindings:
  genBindingsField(bls12381_fr)
  genBindingsField(bls12381_fp)

# Write header
proc main() =
  echo "Running bindings generation for " & getAppFilename().extractFilename()

  var header: string
  header = genBuiltinsTypes()
  header &= '\n'
  header &= genCttBaseTypedef()
  header &= '\n'
  header &= genWordsRequired()
  header &= '\n'
  header &= genField("bls12381_fr", BLS12_381.getCurveOrderBitWidth())
  header &= '\n'
  header &= genField("bls12381_fp", BLS12_381.getCurveBitWidth())
  header &= cBindings

  header = genCpp(header)
  header = genHeader("BLS12381", header)
  header = genHeaderLicense() & header

  writeFile("constantine_bls12_381.h", header)

when isMainModule:
  main()