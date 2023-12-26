//! Constantine
//! Copyright (c) 2018-2019    Status Research & Development GmbH
//! Copyright (c) 2020-Present Mamy André-Ratsimbazafy
//! Licensed and distributed under either of
//!   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
//!   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
//! at your option. This file may not be copied, modified, or distributed except according to those terms.

use constantine_sys::*;

// Cryptographically secure RNGs
// ------------------------------------------------------------

pub mod csprngs {
    use constantine_sys::ctt_csprng_sysrand;
    use core::ffi::c_void;
    #[inline(always)]
    pub fn sysrand(buffer: &mut [u8]) {
        unsafe {
            ctt_csprng_sysrand(buffer.as_mut_ptr() as *mut c_void, buffer.len());
        }
    }
}

// Hardware detection
// ------------------------------------------------------------

pub mod hardware {
    use constantine_sys::ctt_cpu_get_num_threads_os;
    #[inline(always)]
    #[doc = " Query the number of threads available at the OS-level\n  to run computations.\n\n  This takes into account cores disabled at the OS-level, for example in a VM.\n  However this doesn't detect restrictions based on time quotas often used for Docker\n  or taskset / cpuset restrictions from cgroups.\n\n  For Simultaneous-Multithreading (SMT often call HyperThreading),\n  this returns the number of available logical cores."]
    pub fn get_num_threads_os() -> usize {
        unsafe { ctt_cpu_get_num_threads_os() }.try_into().unwrap()
    }
}

// Threadpool
// ------------------------------------------------------------

#[derive(Debug)]
pub struct Threadpool {
    ctx: *mut ctt_threadpool,
}

impl Threadpool {
    /// Instantiate a new Threadpool with `num_threads` threads.
    /// A single threadpool can be active on a given thread.
    /// A new threadpool may be instantiated if the previous one has been shutdown.
    #[inline(always)]
    pub fn new(num_threads: usize) -> Self {
        let ctx = unsafe { ctt_threadpool_new(num_threads.try_into().unwrap()) };
        Self { ctx }
    }

    /// Access the private context of Threadpool
    /// For use, only in Constantine's crates.
    /// No guarantee of continuous support.
    #[inline(always)]
    pub fn get_private_context(&self) -> *mut ctt_threadpool {
        self.ctx
    }
}

impl Drop for Threadpool {
    #[inline(always)]
    fn drop(&mut self) {
        unsafe { ctt_threadpool_shutdown(self.ctx) }
    }
}
