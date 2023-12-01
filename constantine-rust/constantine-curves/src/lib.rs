//! Constantine
//! Copyright (c) 2018-2019    Status Research & Development GmbH
//! Copyright (c) 2020-Present Mamy André-Ratsimbazafy
//! Licensed and distributed under either of
//!   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
//!   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
//! at your option. This file may not be copied, modified, or distributed except according to those terms.

use constantine_sys::*;

pub struct CttThreadpool {
    ctx: *mut ctt_threadpool,
}

impl CttThreadpool {
    #[inline(always)]
    pub fn new(num_threads: usize) -> CttThreadpool {
        let ctx = unsafe{ ctt_threadpool_new(num_threads) };
        CttThreadpool{ctx}
    }
}

impl Drop for CttThreadpool {
    fn drop(&mut self) {
        unsafe { ctt_threadpool_shutdown(self.ctx) }
    }
}



#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn t_threadpool() {
        let tp = CttThreadpool::new(4);
        drop(tp);
    }
}
