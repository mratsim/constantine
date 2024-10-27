# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internal
  constantine/named/algebras,
  constantine/math/io/[io_bigints, io_fields],
  constantine/math/arithmetic,
  constantine/platforms/abstractions,
  constantine/platforms/llvm/llvm,
  constantine/math_compiler/[ir, pub_fields, codegen_nvidia]

proc genStoreBool*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  let name = fd.name & "_store_bool"
  let ptrBool = pointer_t(asy.ctx.int1_t())
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [ptrBool, asy.ctx.int1_t()]):
    let (r, condition) = llvmParams
    asy.store(r, condition)
    asy.br.retVoid()
  return name

proc genStoreIntFloat*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  let name = fd.name & "_store_int_float"
  let ptrInt = pointer_t(asy.ctx.int64_t())
  let ptrFloat = pointer_t(asy.ctx.float64_t())
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [ptrInt, ptrFloat, asy.ctx.int64_t(), asy.ctx.float64_t()]):
    let (ri, rf, i, f) = llvmParams
    asy.store(ri, i)
    asy.store(rf, f)
    asy.br.retVoid()
  return name

proc genStoreIntFloatFromPtr*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  let name = fd.name & "_store_int_float"
  let ptrInt = pointer_t(asy.ctx.int64_t())
  let ptrFloat = pointer_t(asy.ctx.float64_t())
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [ptrInt, ptrFloat, ptrInt, ptrFloat]):
    let (ri, rf, i, f) = llvmParams
    asy.store(ri, asy.load2(ptrInt, i))
    asy.store(rf, asy.load2(ptrFloat, f))
    asy.br.retVoid()
  return name

proc genStoreIntFloat32FromPtr*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  let name = fd.name & "_store_int_float"
  let ptrInt = pointer_t(asy.ctx.int32_t())
  let ptrFloat = pointer_t(asy.ctx.float32_t())
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [ptrInt, ptrFloat, ptrInt, ptrFloat]):
    let (ri, rf, i, f) = llvmParams
    asy.store(ri, asy.load2(ptrInt, i))
    asy.store(rf, asy.load2(ptrFloat, f))
    asy.br.retVoid()
  return name


template test(wordSize: int, ker, body: untyped): untyped =
  block:
    # the field is just a placeholder for this test
    let nv = initNvAsm(Fp[BN254_Snarks], wordSize)
    let kernel {.inject.} = nv.compile(ker)

    body

# Store bool by passing explicit `addr` of a `var`
test(32, genStoreBool):
  let t = true
  var b: bool
  kernel.execCuda(b.addr, t)
  doAssert b == t

# Store bool by passing explicit `ptr bool` var
test(32, genStoreBool):
  let t = true
  var b: bool
  var bP: ptr bool
  bP = b.addr
  kernel.execCuda(bP, t)
  doAssert bP[] == t

# Store bool by passing explicit `bool` as a `var`
test(32, genStoreBool):
  let t = true
  var b: bool
  kernel.execCuda(b, t)
  doAssert b == t

# Store bool by passing explicit `bool` as a `let` fails
template fails(body): untyped =
  when compiles(body):
    raiseAssert "This body should fail: " & astToStr(body)
  else:
    echo "[INFO] ", astToStr(body), "\nfails as expected."
fails:
  test(32, genStoreBool):
    let t = true
    let b = false
    kernel.execCuda(b, t)

# Passing a bool literal works
test(32, genStoreBool):
  var b: bool
  kernel.execCuda(b, true)
  doAssert b == true

# Passing an int and float as let vars
test(32, genStoreIntFloat):
  let x = 5
  let y = 5.5
  var ri: int
  var rf: float
  kernel.execCuda(res = (ri, rf), inputs = (x, y))
  doAssert ri == x
  doAssert rf == y

# Passing an int and float as literals
test(32, genStoreIntFloat):
  var ri: int
  var rf: float
  kernel.execCuda(res = (ri, rf), inputs = (5, 5.5))
  doAssert ri == 5
  doAssert rf == 5.5

# Passing an int and float as consts
test(32, genStoreIntFloat):
  const x = 5
  const y = 5.5
  var ri: int
  var rf: float
  kernel.execCuda(res = (ri, rf), inputs = (x, y))
  doAssert ri == x
  doAssert rf == y

# Using `let` variable to store in int and float fails
fails:
  test(32, genStoreIntFloat):
    const x = 5
    const y = 5.5
    let ri: int
    let rf: float
    kernel.execCuda(res = (ri, rf), inputs = (x, y))
    doAssert ri == x
    doAssert rf == y

# Explicitly passing ptr int / ptr float
test(32, genStoreIntFloat):
  let x = 5
  let y = 5.5
  var ri: int
  var rf: float
  var riP: ptr int
  riP = ri.addr
  var rfP: ptr float
  rfP = rf.addr
  kernel.execCuda(res = (riP, rfP), inputs = (x, y))
  doAssert ri == x
  doAssert rf == y

# Pass inputs to `ptr T` as `ptr T` (64 bit size types)
test(32, genStoreIntFloatFromPtr):
  let x = 5
  let y = 5.5
  var ri: int
  var rf: float
  var iP: ptr int
  iP = x.addr
  var fP: ptr float
  fP = y.addr
  kernel.execCuda(res = (ri, rf), inputs = (iP, fP))
  doAssert ri == x
  doAssert rf == y

# Passing inputs to `ptr T` as `addr x` (64 bit size types)
test(32, genStoreIntFloatFromPtr):
  let x = 5
  let y = 5.5
  var ri: int
  var rf: float
  kernel.execCuda(res = (ri, rf), inputs = (x.addr, y.addr))
  doAssert ri == x
  doAssert rf == y

# Pass inputs to `ptr T` as `ptr T` (32 bit size types)
test(32, genStoreIntFloatFromPtr):
  let x = 5'i32
  let y = 5.5'f32
  var ri: int32
  var rf: float32
  var iP: ptr int32
  iP = x.addr
  var fP: ptr float32
  fP = y.addr
  kernel.execCuda(res = (ri, rf), inputs = (iP, fP))
  doAssert ri == x
  doAssert rf == y

# Passing inputs to `ptr T` as `addr x` (32 bit size types)
test(32, genStoreIntFloatFromPtr):
  let x = 5'i32
  let y = 5.5'f32
  var ri: int32
  var rf: float32
  kernel.execCuda(res = (ri, rf), inputs = (x.addr, y.addr))
  doAssert ri == x
  doAssert rf == y
