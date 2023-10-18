# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internal
  ../../platforms/[abstractions, allocs],
  ./limbs_views

func prod_comba(r: var openArray[SecretWord], a, b: openArray[SecretWord]) {.noInline, tags: [Alloca].} =
  ## Extended precision multiplication
  # We use Product Scanning / Comba multiplication
  var t, u, v = Zero
  let stopEx = min(a.len+b.len, r.len)

  let tmp = allocStackArray(SecretWord, stopEx)

  for i in 0 ..< stopEx:
    # Invariant for product scanning:
    # if we multiply accumulate by a[k1] * b[k2]
    # we have k1+k2 == i
    let ib = min(b.len-1, i)
    let ia = i - ib
    for j in  0 ..< min(a.len - ia, ib+1):
      mulAcc(t, u, v, a[ia+j], b[ib-j])

    tmp[i] = v
    if i < stopEx-1:
      v = u
      u = t
      t = Zero

  for i in 0 ..< stopEx:
    r[i] = tmp[i]

  for i in stopEx ..< r.len:
    r[i] = Zero

func prod*(r: var openArray[SecretWord], a, b: openArray[SecretWord]) {.inline, meter.}=
  ## Extended precision multiplication
  r.prod_comba(a, b)

func prod_vartime*(r: var openArray[SecretWord], a, b: openArray[SecretWord]) {.inline, meter.}=
  ## Extended precision multiplication (vartime)

  let aBits  = a.getBits_LE_vartime()
  let bBits  = b.getBits_LE_vartime()

  let aWords = wordsRequired(aBits)
  let bWords = wordsRequired(bBits)
  let rWords = wordsRequired(aBits + bBits)

  r.toOpenArray(0, rWords-1)
   .prod_comba(
    a.toOpenArray(0, aWords-1),
    b.toOpenArray(0, bWords-1)
   )

  for i in rWords ..< r.len:
    r[i] = Zero