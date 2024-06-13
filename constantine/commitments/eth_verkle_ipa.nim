# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

## ############################################################
##
##                 Inner Product Arguments
##              Ethereum Verkle Tries flavor
##
## ############################################################

# This file implements Inner Product Arguments (IPA) commitment.
# While generic in theory and usable beyond Ethereum,
# the transcript hardcodes Ethereum challenges and would need to be
# modified to be compatible with other IPA implementations like Halo2.

