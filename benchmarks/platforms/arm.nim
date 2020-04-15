# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# TODO cycle counting on ARM
#
# - see writeup: http://zhiyisun.github.io/2016/03/02/How-to-Use-Performance-Monitor-Unit-(PMU)-of-64-bit-ARMv8-A-in-Linux.html
#
# Otherwise Google or FFTW approach might work but might require perf_counter privilege (`kernel.perf_event_paranoid=0` ?)
# - https://github.com/google/benchmark/blob/0ab2c290/src/cycleclock.h#L127-L151
# - https://github.com/FFTW/fftw3/blob/ef15637f/kernel/cycle.h#L518-L564
# - https://github.com/vesperix/FFTW-for-ARMv7/blob/22ec5c0b/kernel/cycle.h#L404-L457
