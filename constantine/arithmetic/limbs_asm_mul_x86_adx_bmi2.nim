# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/macros,
  # Internal
  ../config/common,
  ../primitives,
  ./limbs,
  ./limbs_asm_montmul_x86

# ############################################################
#
#        Assembly implementation of finite fields
#
# ############################################################

# Note: We can refer to at most 30 registers in inline assembly
#       and "InputOutput" registers count double
#       They are nice to let the compiler deals with mov
#       but too constraining so we move things ourselves.

static: doAssert UseASM_X86_64

# MULX/ADCX/ADOX
{.localPassC:"-madx -mbmi2".}
# Necessary for the compiler to find enough registers (enabled at -O1)
{.localPassC:"-fomit-frame-pointer".}

# Multiplication
# ------------------------------------------------------------
proc mulx_by_word*(
       ctx: var Assembler_x86,
       hi: Operand,
       t: OperandArray,
       a: Operand, # Pointer in scratchspace
       word0: Operand,
       lo, rRDX: Operand
     ) =
  ## Multiply the `a[0..<N]` by `word` and store in `t[0..<N]`
  ## and carry register `C` (t[N])
  ## `t` and `C` overwritten
  ## `S` is a scratchspace carry register
  ## `rRDX` is the RDX register descriptor
  let N = min(a.len, t.len)

  ctx.comment "  Outer loop i = 0"

  # for j=0 to N-1
  #  (C,t[j])  := t[j] + a[j]*b[i] + C

  # First limb
  ctx.mov rRDX, word0
  if N > 1:
    ctx.mulx t[1], t[0], a[0], rdx
    ctx.`xor` hi, hi # Clear flags - TODO: necessary?
  else:
    ctx.mulx hi, t[0], a[0], rdx
    return

  # Steady state
  for j in 1 ..< N-1:
    ctx.mulx t[j+1], lo, a[j], rdx
    if j == 1:
      ctx.add t[j], lo
    else:
      ctx.adc t[j], lo

  # Last limb
  ctx.comment "  Outer loop i = 0, last limb"
  ctx.mulx hi, lo, a[N-1], rdx
  ctx.adc t[N-1], lo

  # Final carries
  ctx.comment "  Accumulate last carries in hi word"
  ctx.adc hi, 0

proc mulaccx_by_word*(
       ctx: var Assembler_x86,
       hi: Operand,
       t: OperandArray,
       a: Operand, # Pointer in scratchspace
       i: int,
       word: Operand,
       lo, rRDX: Operand
     ) =
  ## Multiply the `a[0..<N]` by `word`
  ## and accumulate in `t[0..<N]`
  ## and carry register `C` (t[N])
  ## `t` and `C` are multiply-accumulated
  ## `S` is a scratchspace register
  ## `rRDX` is the RDX register descriptor
  let N = min(a.len, t.len)

  doAssert i != 0

  ctx.comment "  Outer loop i = " & $i & ", j in [0, " & $N & ")"
  ctx.mov rRDX, word
  ctx.`xor` hi, hi # Clear flags - TODO: necessary?

  # for j=0 to N-1
  #  (C,t[j])  := t[j] + a[j]*b[i] + C

  # Steady state
  for j in 0 ..< N-1:
    ctx.mulx hi, lo, a[j], rdx
    ctx.adox t[j], lo
    ctx.adcx t[j+1], hi

  # Last limb
  ctx.comment "  Outer loop i = " & $i & ", last limb"
  ctx.mulx hi, lo, a[N-1], rdx
  ctx.adox t[N-1], lo

  # Final carries
  ctx.comment "  Accumulate last carries in hi word"
  ctx.mov  rRDX, 0 # Set to 0 without clearing flags
  ctx.adcx hi, rRDX
  ctx.adox hi, rRDX
