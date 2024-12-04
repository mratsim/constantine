/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
#ifndef __CTT_H_CONSTANTINE__
#define __CTT_H_CONSTANTINE__

// Core functions
#include "constantine/core/datatypes.h"
#include "constantine/core/serialization.h"
#include "constantine/core/threadpool.h"

// Hash functions
#include "constantine/hashes/sha256.h"

// Cryptographically Secure Random Number Generators
#include "constantine/csprngs/sysrand.h"

// Curves
#include "constantine/curves/bls12_381.h"
#include "constantine/curves/bn254_snarks.h"
#include "constantine/curves/pallas.h"
#include "constantine/curves/vesta.h"

#include "constantine/curves/bls12_381_codecs.h"
#include "constantine/curves/banderwagon.h"

#include "constantine/curves/bls12_381_parallel.h"
#include "constantine/curves/bn254_snarks_parallel.h"
#include "constantine/curves/pallas_parallel.h"
#include "constantine/curves/vesta_parallel.h"

// Protocols
#include "constantine/protocols/ethereum_bls_signatures.h"
#include "constantine/protocols/ethereum_bls_signatures_parallel.h"
#include "constantine/protocols/ethereum_eip4844_kzg.h"
#include "constantine/protocols/ethereum_eip4844_kzg_parallel.h"

#include "constantine/protocols/ethereum_evm_precompiles.h"

#endif
