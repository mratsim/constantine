# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./ct_types,
  ../config

# ############################################################
#
#   Constant-time multiplexers/selectors/conditional moves
#
# ############################################################

# For efficiency, those are implemented in inline assembly if possible
# API:
# - mux(CTBool, SecretWord, SecretWord)
# - mux(CTBool, CTBool, CTBool)
# - ccopy(CTBool, var SecretWord, SecretWord)
#
# Those prevents the compiler from introducing branches and leaking secret data:
# - https://www.cl.cam.ac.uk/~rja14/Papers/whatyouc.pdf
# - https://github.com/veorq/cryptocoding

# Generic implementation
# ------------------------------------------------------------

func mux_fallback[T](ctl: CTBool[T], x, y: T): T {.inline.}=
  ## result = if ctl: x else: y
  ## This is a constant-time operation
  y xor (-T(ctl) and (x xor y))

func mux_fallback[T: CTBool](ctl, x, y: T): T {.inline.}=
  ## result = if ctl: x else: y
  ## This is a constant-time operation
  T(T.T(y) xor (-T.T(ctl) and (T.T(x) xor T.T(y))))

func ccopy_fallback[T](ctl: CTBool[T], x: var T, y: T) {.inline.}=
  ## Conditional copy
  ## Copy ``y`` into ``x`` if ``ctl`` is true
  x = ctl.mux_fallback(y, x)

# x86 and x86-64
# ------------------------------------------------------------

# Note, we don't need the Intel syntax here, contrary to field arithmetic assembly.
# And the {.localpassC:"-masm=intel".} is local to those files.


const
  nim_v2 = (NimMajor, NimMinor) > (1, 6)
  noExplicitVarDeref = defined(cpp) or nim_v2

template mux_x86_impl() {.dirty.} =
  static: doAssert(X86)
  static: doAssert(GCC_Compatible)

  when UseAsmSyntaxIntel:
    var muxed = x
    asm """
      test %[ctl], %[ctl]
      cmovz %[muxed], %[y]
      : [muxed] "+r" (`muxed`)
      : [ctl] "r" (`ctl`), [y] "r" (`y`)
      : "cc"
    """
    muxed
  else:
    when sizeof(T) == 8:
      var muxed = x
      asm """
        testq %[ctl], %[ctl]
        cmovzq %[y], %[muxed]
        : [muxed] "+r" (`muxed`)
        : [ctl] "r" (`ctl`), [y] "r" (`y`)
        : "cc"
      """
      muxed
    else:
      var muxed = x
      asm """
        testl %[ctl], %[ctl]
        cmovzl %[y], %[muxed]
        : [muxed] "+r" (`muxed`)
        : [ctl] "r" (`ctl`), [y] "r" (`y`)
        : "cc"
      """
      muxed

func mux_x86[T](ctl: CTBool[T], x, y: T): T {.inline.}=
  ## Multiplexer / selector
  ## Returns x if ctl is true
  ## else returns y
  ## So equivalent to ctl? x: y
  mux_x86_impl()

func mux_x86[T: CTBool](ctl: CTBool, x, y: T): T {.inline.}=
  ## Multiplexer / selector
  ## Returns x if ctl is true
  ## else returns y
  ## So equivalent to ctl? x: y
  mux_x86_impl()

func ccopy_x86[T](ctl: CTBool[T], x: var T, y: T) {.inline.}=
  ## Conditional copy
  ## Copy ``y`` into ``x`` if ``ctl`` is true
  static: doAssert(X86)
  static: doAssert(GCC_Compatible)

  # Due to https://github.com/nim-lang/Nim/issues/23114
  # We don't use asm statement with `var` param

  when UseAsmSyntaxIntel:
    when noExplicitVarDeref:
      {.emit:[
        """
        asm volatile(
          "test %[ctl], %[ctl]\n"
          "cmovnz %[x], %[y]\n"
          : [x] "+r" (""", x, """)
          : [ctl] "r" (""", ctl, """), [y] "r" (""", y, """)
          : "cc"
        );"""].}
    else:
      {.emit:[
        """
        asm volatile(
          "test %[ctl], %[ctl]\n"
          "cmovnz %[x], %[y]\n"
          : [x] "+r" (*""", x, """)
          : [ctl] "r" (""", ctl, """), [y] "r" (""", y, """)
          : "cc"
        );"""].}
  else:
    when sizeof(T) == 8:
      when noExplicitVarDeref:
        {.emit:[
          """
          asm volatile(
            "testq %[ctl], %[ctl]\n"
            "cmovnzq %[y], %[x]\n"
            : [x] "+r" (""", x, """)
            : [ctl] "r" (""", ctl, """), [y] "r" (""", y, """)
            : "cc"
          );"""].}
      else:
        {.emit:[
          """
          asm volatile(
            "testq %[ctl], %[ctl]\n"
            "cmovnzq %[y], %[x]\n"
            : [x] "+r" (*""", x, """)
            : [ctl] "r" (""", ctl, """), [y] "r" (""", y, """)
            : "cc"
          );"""].}
    else:
      when noExplicitVarDeref:
        {.emit:[
          """
          asm volatile(
            "testl %[ctl], %[ctl]\n"
            "cmovnzl %[y], %[x]\n"
            : [x] "+r" (""", x, """)
            : [ctl] "r" (""", ctl, """), [y] "r" (""", y, """)
            : "cc"
          );"""].}
      else:
        {.emit:[
          """
          asm volatile(
            "testl %[ctl], %[ctl]\n"
            "cmovnzl %[y], %[x]\n"
            : [x] "+r" (*""", x, """)
            : [ctl] "r" (""", ctl, """), [y] "r" (""", y, """)
            : "cc"
          );"""].}

# Public functions
# ------------------------------------------------------------

func mux*[T](ctl: CTBool[T], x, y: T): T {.inline.}=
  ## Multiplexer / selector
  ## Returns x if ctl is true
  ## else returns y
  ## So equivalent to ctl? x: y
  when nimvm:
    mux_fallback(ctl, x, y)
  else:
    when X86 and GCC_Compatible:
      mux_x86(ctl, x, y)
    else:
      mux_fallback(ctl, x, y)

func mux*[T: CTBool](ctl: CTBool, x, y: T): T {.inline.}=
  ## Multiplexer / selector
  ## Returns x if ctl is true
  ## else returns y
  ## So equivalent to ctl? x: y
  when nimvm:
    mux_fallback(ctl, x, y)
  else:
    when X86 and GCC_Compatible:
      mux_x86(ctl, x, y)
    else:
      mux_fallback(ctl, x, y)

func ccopy*[T](ctl: CTBool[T], x: var T, y: T) {.inline.}=
  ## Conditional copy
  ## Copy ``y`` into ``x`` if ``ctl`` is true
  when nimvm:
    ccopy_fallback(ctl, x, y)
  else:
    when X86 and GCC_Compatible:
      ccopy_x86(ctl, x, y)
    else:
      ccopy_fallback(ctl, x, y)
