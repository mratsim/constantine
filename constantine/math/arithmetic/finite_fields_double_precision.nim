# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/abstractions,
  ../config/curves,
  ./bigints,
  ./finite_fields,
  ./limbs,
  ./limbs_extmul,
  ./limbs_montgomery

when UseASM_X86_64:
  import assembly/limbs_asm_modular_dbl_prec_x86

type FpDbl*[C: static Curve] = object
  ## Double-precision Fp element
  ## A FpDbl is a partially-reduced double-precision element of Fp
  ## The allowed range is [0, 2ⁿp)
  ## with n = w*WordBitWidth
  ## and w the number of words necessary to represent p on the machine.
  ## Concretely a 381-bit p needs 6*64 bits limbs (hence 384 bits total)
  ## and so FpDbl would 768 bits.
  # We directly work with double the number of limbs,
  # instead of BigInt indirection.
  limbs2x*: matchingLimbs2x(C)

template doublePrec*(T: type Fp): type =
  ## Return the double-precision type matching with Fp
  FpDbl[T.C]

# No exceptions allowed
{.push raises: [].}
{.push inline.}

func `==`*(a, b: FpDbl): SecretBool =
  a.limbs2x == b.limbs2x

func isZero*(a: FpDbl): SecretBool =
  a.limbs2x.isZero()

func setZero*(a: var FpDbl) =
  a.limbs2x.setZero()

func prod2x*(r: var FpDbl, a, b: Fp) =
  ## Double-precision multiplication
  ## Store the product of ``a`` by ``b`` into ``r``
  ##
  ## If a and b are in [0, p)
  ## Output is in [0, p²)
  ##
  ## Output can be up to [0, 2ⁿp) range
  ## provided spare bits are available in Fp representation
  r.limbs2x.prod(a.mres.limbs, b.mres.limbs)

func square2x*(r: var FpDbl, a: Fp) =
  ## Double-precision squaring
  ## Store the square of ``a`` into ``r``
  ##
  ## If a is in [0, p)
  ## Output is in [0, p²)
  ##
  ## Output can be up to [0, 2ⁿp) range
  ## provided spare bits are available in Fp representation
  r.limbs2x.square(a.mres.limbs)

func redc2x*(r: var Fp, a: FpDbl) =
  ## Reduce a double-precision field element into r
  ## from [0, 2ⁿp) range to [0, p) range
  redc2xMont(
    r.mres.limbs,
    a.limbs2x,
    Fp.C.Mod.limbs,
    Fp.getNegInvModWord(),
    Fp.getSpareBits()
  )

func diff2xUnr*(r: var FpDbl, a, b: FpDbl) =
  ## Double-precision substraction without reduction
  ##
  ## If the result is negative, fully reduced addition/substraction
  ## are necessary afterwards to guarantee the [0, 2ⁿp) range
  discard r.limbs2x.diff(a.limbs2x, b.limbs2x)

func diff2xMod*(r: var FpDbl, a, b: FpDbl) =
  ## Double-precision modular substraction
  ## Output is conditionally reduced by 2ⁿp
  ## to stay in the [0, 2ⁿp) range
  when UseASM_X86_64:
    submod2x_asm(r.limbs2x, a.limbs2x, b.limbs2x, FpDbl.C.Mod.limbs)
  else:
    # Substraction step
    var underflowed = SecretBool r.limbs2x.diff(a.limbs2x, b.limbs2x)

    # Conditional reduction by 2ⁿp
    const N = r.limbs2x.len div 2
    const M = FpDbl.C.Mod
    var carry = Carry(0)
    var sum: SecretWord
    staticFor i, 0, N:
      addC(carry, sum, r.limbs2x[i+N], M.limbs[i], carry)
      underflowed.ccopy(r.limbs2x[i+N], sum)

func sum2xUnr*(r: var FpDbl, a, b: FpDbl) =
  ## Double-precision addition without reduction
  ##
  ## If the result is bigger than 2ⁿp, fully reduced addition/substraction
  ## are necessary afterwards to guarantee the [0, 2ⁿp) range
  discard r.limbs2x.sum(a.limbs2x, b.limbs2x)

func sum2xMod*(r: var FpDbl, a, b: FpDbl) =
  ## Double-precision modular addition
  ## Output is conditionally reduced by 2ⁿp
  ## to stay in the [0, 2ⁿp) range
  when UseASM_X86_64:
    addmod2x_asm(r.limbs2x, a.limbs2x, b.limbs2x, FpDbl.C.Mod.limbs, Fp[FpDbl.C].getSpareBits())
  else:
    # Addition step
    var overflowed = SecretBool r.limbs2x.sum(a.limbs2x, b.limbs2x)

    const N = r.limbs2x.len div 2
    const M = FpDbl.C.Mod
    # Test >= 2ⁿp
    var borrow = Borrow(0)
    var t{.noInit.}: Limbs[N]
    staticFor i, 0, N:
      subB(borrow, t[i], r.limbs2x[i+N], M.limbs[i], borrow)

    # If no borrow occured, r was bigger than 2ⁿp
    overflowed = overflowed or not(SecretBool borrow)

    # Conditional reduction by 2ⁿp
    staticFor i, 0, N:
      overflowed.ccopy(r.limbs2x[i+N], t[i])

func neg2xMod*(r: var FpDbl, a: FpDbl) =
  ## Double-precision modular substraction
  ## Negate modulo 2ⁿp
  when UseASM_X86_64:
    negmod2x_asm(r.limbs2x, a.limbs2x, FpDbl.C.Mod.limbs)
  else:
    # If a = 0 we need r = 0 and not r = M
    # as comparison operator assume unicity
    # of the modular representation.
    # Also make sure to handle aliasing where r.addr = a.addr
    var t {.noInit.}: FpDbl
    let isZero = a.isZero()
    const N = r.limbs2x.len div 2
    const M = FpDbl.C.Mod
    var borrow = Borrow(0)
    # 2ⁿp is filled with 0 in the first half
    staticFor i, 0, N:
      subB(borrow, t.limbs2x[i], Zero, a.limbs2x[i], borrow)
    # 2ⁿp has p (shifted) for the rest of the limbs
    staticFor i, N, r.limbs2x.len:
      subB(borrow, t.limbs2x[i], M.limbs[i-N], a.limbs2x[i], borrow)

    # Zero the result if input was zero
    t.limbs2x.csetZero(isZero)
    r = t

func prod2xImpl(
    r {.noAlias.}: var FpDbl,
    a {.noAlias.}: FpDbl, b: static int) =
  ## Multiplication by a small integer known at compile-time
  ## Requires no aliasing and b positive
  static: doAssert b >= 0

  when b == 0:
    r.setZero()
  elif b == 1:
    r = a
  elif b == 2:
    r.sum2xMod(a, a)
  elif b == 3:
    r.sum2xMod(a, a)
    r.sum2xMod(a, r)
  elif b == 4:
    r.sum2xMod(a, a)
    r.sum2xMod(r, r)
  elif b == 5:
    r.sum2xMod(a, a)
    r.sum2xMod(r, r)
    r.sum2xMod(r, a)
  elif b == 6:
    r.sum2xMod(a, a)
    let t2 = r
    r.sum2xMod(r, r) # 4
    r.sum2xMod(t, t2)
  elif b == 7:
    r.sum2xMod(a, a)
    r.sum2xMod(r, r) # 4
    r.sum2xMod(r, r)
    r.diff2xMod(r, a)
  elif b == 8:
    r.sum2xMod(a, a)
    r.sum2xMod(r, r)
    r.sum2xMod(r, r)
  elif b == 9:
    r.sum2xMod(a, a)
    r.sum2xMod(r, r)
    r.sum2xMod(r, r) # 8
    r.sum2xMod(r, a)
  elif b == 10:
    r.sum2xMod(a, a)
    r.sum2xMod(r, r)
    r.sum2xMod(r, a) # 5
    r.sum2xMod(r, r)
  elif b == 11:
    r.sum2xMod(a, a)
    r.sum2xMod(r, r)
    r.sum2xMod(r, a) # 5
    r.sum2xMod(r, r)
    r.sum2xMod(r, a)
  elif b == 12:
    r.sum2xMod(a, a)
    r.sum2xMod(r, r) # 4
    let t4 = a
    r.sum2xMod(r, r) # 8
    r.sum2xMod(r, t4)
  else:
    {.error: "Multiplication by this small int not implemented".}

func prod2x*(r: var FpDbl, a: FpDbl, b: static int) =
  ## Multiplication by a small integer known at compile-time
  const negate = b < 0
  const b = if negate: -b
            else: b
  when negate:
    var t {.noInit.}: typeof(r)
    t.neg2xMod(a)
  else:
    let t = a
  prod2xImpl(r, t, b)

{.pop.} # inline
{.pop.} # raises no exceptions
