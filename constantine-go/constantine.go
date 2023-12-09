/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */

package constantine

/*
#cgo CFLAGS: -I"${SRCDIR}/../include"
#cgo LDFLAGS: "${SRCDIR}/../lib/libconstantine.a"
#include "constantine.h"
*/
import "C"

// Threadpool API
// ------------------------------------------------

type CttThreadpool struct {
	ctx *C.ctt_threadpool
}

func CttThreadpoolNew(numThreads int) (CttThreadpool) {
	return CttThreadpool{
		ctx: C.ctt_threadpool_new(C.size_t(numThreads)),
	}
}

func (tp CttThreadpool) Shutdown() {
	C.ctt_threadpool_shutdown(tp.ctx)
}