/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
#ifndef __CTT_H_THREADPOOL__
#define __CTT_H_THREADPOOL__

#ifdef __cplusplus
extern "C" {
#endif

#if defined(__SIZE_TYPE__)
typedef __SIZE_TYPE__    size_t;
#else
#include <stddef.h>
#endif

typedef struct ctt_threadpool ctt_threadpool;

/** Create a new threadpool that manages `num_threads` threads
 *
 * Initialize a threadpool that manages `num_threads` threads.
 *
 * A Constantine's threadpool cannot be instantiated
 * on a thread managed by another Constantine's threadpool
 * including the root thread.
 *
 * Mixing with other libraries' threadpools and runtime
 * will not impact correctness but may impact performance.
 */
struct ctt_threadpool* ctt_threadpool_new(size_t num_threads);

/** Wait until all pending tasks are processed and then shutdown the threadpool
 */
void ctt_threadpool_shutdown(struct ctt_threadpool* threadpool);

#ifdef __cplusplus
}
#endif

#endif // __CTT_H_THREADPOOL__