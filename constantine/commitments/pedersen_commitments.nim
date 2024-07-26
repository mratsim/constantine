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
  ../math/polynomials/polynomials,
  ../platforms/views


## ############################################################
##
##                Pedersen Commitments
##
## ############################################################

func pedersen_commit[EC, ECaff](
      public_generators: openArray[ECaff],
      r: var EC,
      messages: openArray[Fr]) {.inline.} =
  ## Vector Pedersen Commitment with elliptic curves
  ##
  ## Context
  ## - public generators G=(G₀,...,Gₙ₋₁)
  ##
  ## Inputs
  ## - messages m=(m₀,...,mₙ₋₁)
  ##
  ## Output:
  ##   Commit(m) := ∑[mᵢ]Gᵢ
  r.multiScalarMul_vartime(messages, public_generators)

func pedersen_commit*[N: static int, EC, ECaff, F](
      crs: PolynomialEval[N, EcAff],
      r: var EC,
      messages: PolynomialEval[N, F]) {.inline.} =
  ## Vector Pedersen Commitment with elliptic curves
  ##
  ## Context
  ## - public generators G=(G₀,...,Gₙ₋₁)
  ##
  ## Inputs
  ## - messages m=(m₀,...,mₙ₋₁)
  ##
  ## Output:
  ##   Commit(m) := ∑[mᵢ]Gᵢ
  r.multiScalarMul_vartime(messages.evals, crs.evals)

func pedersen_commit*[EC, ECaff, F](
      public_generators: View[ECaff],
      r: var EC,
      messages: View[F]) {.inline.} =
  ## Vector Pedersen Commitment with elliptic curves
  ##
  ## Context
  ## - public generators G=(G₀,...,Gₙ₋₁)
  ##
  ## Inputs
  ## - messages m=(m₀,...,mₙ₋₁)
  ##
  ## Output:
  ##   Commit(m) := ∑[mᵢ]Gᵢ
  public_generators.toOpenArray().pedersen_commit(r, messages.toOpenArray())

func pedersen_commit*[EC, ECaff](
      public_generators: openArray[ECaff],
      hiding_generator: ECaff,
      output: var EC,
      messages: openArray[Fr],
      blinding_factor: Fr) =
  ## Blinded Vector Pedersen Commitment with elliptic curves
  ##
  ## Context
  ## - public generators G=(G₀,...,Gₙ₋₁)
  ## - Hiding generator H
  ##
  ## Inputs
  ## - messages m=(m₀,...,mₙ₋₁)
  ## - blinding factor r
  ##
  ## Output:
  ##   Commit(m, r) := ∑[mᵢ]Gᵢ + [r]H
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

  output.pedersen_commit(messages, public_generators)

  # We could run the following in MSM, but that would require extra alloc and copy
  var rH {.noInit.}: EC
  rH.fromAffine(hiding_generator)
  rH.scalarMul_vartime(blinding_factor)

  output += rH
