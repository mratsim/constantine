/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */

// This is a test to ensure the C API for the threadpool works on all platforms
// and:
//   if special options like -d:tlsEmulation:off are needed
//   if NimMain is done implicitly at load time.

#include <stdio.h>
#include <constantine.h>

void ctt_init_NimMain(void);

int main(){
  printf("Constantine: Testing the C API for the threadpool.\n");
  // ctt_init_NimMain();

  struct ctt_threadpool* tp = ctt_threadpool_new(4);
  printf("Constantine: Threadpool init successful.\n");
  ctt_threadpool_shutdown(tp);
  printf("Constantine: Threadpool shutdown successful.\n");

  return 0;
}