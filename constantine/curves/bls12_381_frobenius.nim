# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/curves,
  ../towers,
  ../io/io_towers

# Frobenius map - on extension fields
# -----------------------------------------------------------------

# c = (SNR^((p-1)/6)^coef).
# Then for frobenius(2): c  * conjugate(c)
# And for frobenius(3):  c² * conjugate(c)
const BLS12_381_FrobeniusMapCoefficients* = [
  # frobenius(1) -----------------------
  [Fp2[BLS12_381].fromHex(  # SNR^((p-1)/6)^0
    "0x1",
    "0x0"
  ),
  Fp2[BLS12_381].fromHex(  # SNR^((p-1)/6)^1
    "0x1904d3bf02bb0667c231beb4202c0d1f0fd603fd3cbd5f4f7b2443d784bab9c4f67ea53d63e7813d8d0775ed92235fb8",
    "0xfc3e2b36c4e03288e9e902231f9fb854a14787b6c7b36fec0c8ec971f63c5f282d5ac14d6c7ec22cf78a126ddc4af3"
  ),
  Fp2[BLS12_381].fromHex(  # SNR^((p-1)/6)^2
    "0x0",
    "0x1a0111ea397fe699ec02408663d4de85aa0d857d89759ad4897d29650fb85f9b409427eb4f49fffd8bfd00000000aaac"
  ),
  Fp2[BLS12_381].fromHex(  # SNR^((p-1)/6)^3
    "0x6af0e0437ff400b6831e36d6bd17ffe48395dabc2d3435e77f76e17009241c5ee67992f72ec05f4c81084fbede3cc09",
    "0x6af0e0437ff400b6831e36d6bd17ffe48395dabc2d3435e77f76e17009241c5ee67992f72ec05f4c81084fbede3cc09"
  ),
  Fp2[BLS12_381].fromHex(  # SNR^((p-1)/6)^4
    "0x1a0111ea397fe699ec02408663d4de85aa0d857d89759ad4897d29650fb85f9b409427eb4f49fffd8bfd00000000aaad",
    "0x0"
  ),
  Fp2[BLS12_381].fromHex(  # SNR^((p-1)/6)^5
    "0x5b2cfd9013a5fd8df47fa6b48b1e045f39816240c0b8fee8beadf4d8e9c0566c63a3e6e257f87329b18fae980078116",
    "0x144e4211384586c16bd3ad4afa99cc9170df3560e77982d0db45f3536814f0bd5871c1908bd478cd1ee605167ff82995"
  )],
  # frobenius(2) -----------------------
  [Fp2[BLS12_381].fromHex(  # norm(SNR)^((p-1)/6)^0
    "0x1",
    "0x0"
  ),
  Fp2[BLS12_381].fromHex(  # norm(SNR)^((p-1)/6)^1
    "0x5f19672fdf76ce51ba69c6076a0f77eaddb3a93be6f89688de17d813620a00022e01fffffffeffff",
    "0x0"
  ),
  Fp2[BLS12_381].fromHex(  # norm(SNR)^((p-1)/6)^2
    "0x5f19672fdf76ce51ba69c6076a0f77eaddb3a93be6f89688de17d813620a00022e01fffffffefffe",
    "0x0"
  ),
  Fp2[BLS12_381].fromHex(  # norm(SNR)^((p-1)/6)^3
    "0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaaa",
    "0x0"
  ),
  Fp2[BLS12_381].fromHex(  # norm(SNR)^((p-1)/6)^4
    "0x1a0111ea397fe699ec02408663d4de85aa0d857d89759ad4897d29650fb85f9b409427eb4f49fffd8bfd00000000aaac",
    "0x0"
  ),
  Fp2[BLS12_381].fromHex(  # norm(SNR)^((p-1)/6)^5
    "0x1a0111ea397fe699ec02408663d4de85aa0d857d89759ad4897d29650fb85f9b409427eb4f49fffd8bfd00000000aaad",
    "0x0"
  )],
  # frobenius(3) -----------------------
  [Fp2[BLS12_381].fromHex(  # (SNR²)^((p-1)/6)^0
    "0x1",
    "0x0"
  ),
  Fp2[BLS12_381].fromHex(  # (SNR²)^((p-1)/6)^1
    "0x135203e60180a68ee2e9c448d77a2cd91c3dedd930b1cf60ef396489f61eb45e304466cf3e67fa0af1ee7b04121bdea2",
    "0x6af0e0437ff400b6831e36d6bd17ffe48395dabc2d3435e77f76e17009241c5ee67992f72ec05f4c81084fbede3cc09"
  ),
  Fp2[BLS12_381].fromHex(  # (SNR²)^((p-1)/6)^2
    "0x0",
    "0x1"
  ),
  Fp2[BLS12_381].fromHex(  # (SNR²)^((p-1)/6)^3
    "0x135203e60180a68ee2e9c448d77a2cd91c3dedd930b1cf60ef396489f61eb45e304466cf3e67fa0af1ee7b04121bdea2",
    "0x135203e60180a68ee2e9c448d77a2cd91c3dedd930b1cf60ef396489f61eb45e304466cf3e67fa0af1ee7b04121bdea2"
  ),
  Fp2[BLS12_381].fromHex(  # (SNR²)^((p-1)/6)^4
    "0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaaa",
    "0x0"
  ),
  Fp2[BLS12_381].fromHex(  # (SNR²)^((p-1)/6)^5
    "0x6af0e0437ff400b6831e36d6bd17ffe48395dabc2d3435e77f76e17009241c5ee67992f72ec05f4c81084fbede3cc09",
    "0x135203e60180a68ee2e9c448d77a2cd91c3dedd930b1cf60ef396489f61eb45e304466cf3e67fa0af1ee7b04121bdea2"
  )]]

# ψ (Psi) - Untwist-Frobenius-Twist Endomorphisms on twisted curves
# -----------------------------------------------------------------
# BLS12_381 is a M-Twist: psi1_coef1 = (1/SNR)^((p-1)/6)

# (1/SNR)^((p-1)/3)
const BLS12_381_FrobeniusPsi_psi1_coef2* = Fp2[BLS12_381].fromHex( 
  "0x0",
  "0x1a0111ea397fe699ec02408663d4de85aa0d857d89759ad4897d29650fb85f9b409427eb4f49fffd8bfd00000000aaad"
)
# (1/SNR)^((p-1)/2)
const BLS12_381_FrobeniusPsi_psi1_coef3* = Fp2[BLS12_381].fromHex( 
  "0x135203e60180a68ee2e9c448d77a2cd91c3dedd930b1cf60ef396489f61eb45e304466cf3e67fa0af1ee7b04121bdea2",
  "0x6af0e0437ff400b6831e36d6bd17ffe48395dabc2d3435e77f76e17009241c5ee67992f72ec05f4c81084fbede3cc09"
)
# norm((1/SNR))^((p-1)/3)
const BLS12_381_FrobeniusPsi_psi2_coef2* = Fp2[BLS12_381].fromHex( 
  "0x1a0111ea397fe699ec02408663d4de85aa0d857d89759ad4897d29650fb85f9b409427eb4f49fffd8bfd00000000aaac",
  "0x0"
)