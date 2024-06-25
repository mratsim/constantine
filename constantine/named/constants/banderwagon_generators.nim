# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/named/algebra,
  constantine/math/elliptic/ec_twistededwards_affine,
  constantine/math/io/[io_fields, io_extfields]

{.used.}

# Generators
# -----------------------------------------------------------------
# https://eprint.iacr.org/2021/1152.pdf

const Banderwagon_generator* = ECP_TwEdwards_Aff[Fp[Banderwagon]](
  x: Fp[Banderwagon].fromHex("29c132cc2c0b34c5743711777bbe42f32b79c022ad998465e1e71866a252ae18"),
  y: Fp[Banderwagon].fromHex("2a6c669eda123e0f157d8b50badcd586358cad81eee464605e3167b6cc974166")
)
