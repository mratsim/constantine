# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/llvm/[llvm, asm_nvidia],
  constantine/platforms/[primitives],
  ./ir,
  ./impl_fields_globals,
  ./impl_fields_dispatch,
  ./impl_fields_ops,
  ./impl_curves_ops_affine,
  ./impl_curves_ops_jacobian,
  std / typetraits # for distinctBase

## Section name used for `llvmInternalFnDef`
const SectionName = "ctt.msm_nvidia"

proc msm*(asy: Assembler_LLVM, cd: CurveDescriptor, r, coefs, points: ValueRef,
          c, N: int) {.used.} =
  ## Inner implementation of MSM, for static dispatch over c, the bucket bit length
  ## This is a straightforward simple translation of BDLO12, section 4
  ##
  ## Entirely serial implementation!
  ##
  ## Important note: The coefficients given to this procedure must be in canonical
  ## representation instead of Montgomery representation! Thus, you cannot pass
  ## values of type `Fr[Curve]` directly, as they are internally stored in Montgomery
  ## rep. Convert to a `BigInt` using `fromField`.
  let name = cd.name & "_msm_impl"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([r, coefs, points]),
          {kHot}):
    tagParameter(1, "sret")

    # Inject templates for convenient access
    declFieldOps(asy, cd.fd)
    declEllipticJacOps(asy, cd)
    declEllipticAffOps(asy, cd)
    declNumberOps(asy, cd.fd)

    let (ri, coefsIn, pointsIn) = llvmParams
    let rA = asy.asEcPointJac(cd, ri)
    let cs = asy.asFieldScalarArray(cd, coefsIn, N) # coefficients
    let Ps = asy.asEcAffArray(cd, pointsIn, N) # EC points
    # Prologue
    # --------
    let numBuckets = 1 shl c - 1 # bucket 0 is unused
    let numWindows = cd.orderBitWidth.int.ceilDiv_vartime(c)

    let miniMSMs = asy.initEcJacArray(cd, numWindows)
    let buckets  = asy.initEcJacArray(cd, numBuckets)

    # Algorithm
    # ---------
    var cNonZero = asy.initMutVal(cd.fd.wordTy)
    asy.llvmFor w, 0, numWindows - 1, true:
      # Place our points in a bucket corresponding to
      # how many times their bit pattern in the current window of size c
      asy.llvmFor i, 0, numBuckets - 1, true:
        buckets[i].setNeutral()

      # 1. Bucket accumulation.                            Cost: n - (2ᶜ-1) => n points in 2ᶜ-1 buckets, first point per bucket is just copied
      asy.llvmFor j, 0, N-1, true:
        var b = asy.initMutVal(cd.fd.wordTy)
        let w0 = asy.initConstVal(0, cd.fd.wordTy)
        asy.getWindowAt(cd, b.buf, cs[j].buf, asy.to(w, cd.fd.wordTy) * c, constInt(cd.fd.wordTy, c))
        llvmIf(asy):
          if b != w0:
            buckets[b-1] += Ps[j]

      var accumBuckets = asy.newEcPointJac(cd)
      var miniMSM      = asy.newEcPointJac(cd)
      accumBuckets.store(buckets[numBuckets-1])
      miniMSM.store(buckets[numBuckets-1])

      asy.llvmFor k, numBuckets-2, 0, false:
        accumBuckets += buckets[k] # Stores S₈ then    S₈+S₇ then       S₈+S₇+S₆ then ...
        miniMSM += accumBuckets    # Stores S₈ then [2]S₈+S₇ then [3]S₈+[2]S₇+S₆ then ...

      miniMSMs[w].store(miniMSM)

    rA.store(miniMSMs[numWindows-1])
    asy.llvmFor w, numWindows-2, 0, false:
      asy.llvmFor j, 0, c-1:
        rA.double()
      rA += miniMSMs[w]

    asy.br.retVoid()

  asy.callFn(name, [r, coefs, points])
