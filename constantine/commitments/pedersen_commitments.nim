# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../math/[ec_shortweierstrass, arithmetic],
  ../math/elliptic/ec_multi_scalar_mul,
  ../platforms/views


## ############################################################
##
##                Pedersen Commitments
##
## ############################################################

func pedersen_commit*[EC, ECaff](
      r: var EC,
      messages: openArray[Fr],
      public_generators: openArray[ECaff]) {.inline.} =
  ## Vector Pedersen Commitment with elliptic curves
  ##
  ## Inputs
  ## - messages m=(m₀,...,mₙ₋₁)
  ## - public generators G=(G₀,...,Gₙ₋₁)
  ##
  ## Computes: Commit(m, r) := ∑[mᵢ]Gᵢ
  r.multiScalarMul_reference_vartime(messages, public_generators)

func pedersen_commit*[EC, ECaff, F](
      r: var EC,
      messages: StridedView[F],
      public_generators: StridedView[ECaff]) =
  ## Vector Pedersen Commitment with elliptic curves
  ##
  ## Inputs
  ## - messages m=(m₀,...,mₙ₋₁)
  ## - public generators G=(G₀,...,Gₙ₋₁)
  ##
  ## Computes: Commit(m, r) := ∑[mᵢ]Gᵢ
  r.pedersen_commit(messages.toOpenArray(), public_generators.toOpenArray())

func pedersen_commit*[EC, ECaff](
      r: var EC,
      messages: openArray[Fr],
      public_generators: openArray[ECaff],
      blinding_factor: Fr,
      hiding_generator: ECaff) =
  ## Blinded Vector Pedersen Commitment with elliptic curves
  ##
  ## Inputs
  ## - messages m=(m₀,...,mₙ₋₁)=(G₀,...,Gₙ₋₁)
  ## - public generators G
  ## - blinding factor r
  ## - hiding generator H
  ##
  ## Computes: Commit(m, r) := ∑[mᵢ]Gᵢ + [r]H

  # - Non-Interactive and Information-Theoretic Secure Verifiable Secret Sharing
  #   Torben Pryds Pedersen
  #   https://link.springer.com/content/pdf/10.1007/3-540-46766-1_9.pdf
  #
  # - https://zcash.github.io/halo2/background/groups.html#vector-pedersen-commitment
  #   https://eprint.iacr.org/2019/1021.pdf
  #   Chapter 3
  #
  # - High Assurance Specification of the halo2 Protocol
  #   https://cdck-file-uploads-global.s3.dualstack.us-west-2.amazonaws.com/zcash/original/3X/5/0/50b210737efe301239d8d774a43e1f1d6234eab9.pdf
  #
  # - MIT IAP, 2023.1
  #   https://assets.super.so/9c1ce0ba-bad4-4680-8c65-3a46532bf44a/files/61fb28e6-f2dc-420f-89e1-cc8000233a4f.pdf
  #
  # - https://dankradfeist.de/ethereum/2021/07/27/inner-product-arguments.html

  r.pedersen_commit(messages, public_generators)

  # We could run the following in MSM, but that would require extra alloc and copy
  var rH {.noInit.}: EC
  rH.fromAffine(hiding_generator)
  rH.scalarMul_vartime(blinding_factor)

  r += rH
