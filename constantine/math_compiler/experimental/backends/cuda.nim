# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import std / [macros, strformat, strutils, sugar, sequtils]

import ../gpu_types
import ./common_utils

proc gpuTypeToString*(t: GpuType,
                      ident: string = "",
                      allowArrayToPtr = false,
                      allowEmptyIdent = false): string
proc size*(ctx: var GpuContext, a: GpuType): string = size(gpuTypeToString(a, allowEmptyIdent = true))

proc getInnerArrayType(t: GpuType): string =
  ## Returns the name of the inner most type for a nested array.
  case t.kind
  of gtArray:
    result = getInnerArrayType(t.aTyp)
  else:
    result = gpuTypeToString(t)

proc gpuTypeToString*(t: GpuTypeKind): string =
  case t
  of gtBool: "bool"
  of gtUint8: "unsigned char"
  of gtUint16: "unsigned short"
  of gtUint32: "unsigned int"
  of gtUint64: "unsigned long long"
  of gtInt16: "short"
  of gtInt32: "int"
  of gtInt64: "long long"
  of gtFloat32: "float"
  of gtFloat64: "double"
  of gtVoid: "void"
  of gtSize_t: "size_t"
  of gtPtr: "*"
  of gtVoidPtr: "void*"
  of gtObject: "struct"
  of gtString: "const char*"
  else:
    raiseAssert "Invalid type : " & $t

proc gpuTypeToString*(t: GpuType, ident: string = "", allowArrayToPtr = false,
                      allowEmptyIdent = false,
                    ): string =
  ## Given an optional identifier required for array types
  ##
  ## XXX: we don't support this at the moment, it occured to me as something that
  ## could be useful sometimes...
  ## If `allowArrayToPtr` we allow casting a statically sized array to a pointer
  var skipIdent = false
  case t.kind
  of gtPtr:
    if t.to.kind == gtArray: # ptr to array type
      # need to pass `*` for the pointer into the identifier, i.e.
      # `state: var array[4, BigInt]`
      # must become
      # `BigInt (*state)[4]`
      # so as our ident we pass `theIdent = (*<ident>)` and generate the type for the internal
      # array type, which yields e.g. `BigInt <theIdent>[4]`.
      let ptrStar = gpuTypeToString(t.kind)
      result = gpuTypeToString(t.to, "(" & ptrStar & ident & ")")
      skipIdent = true
    else:
      let typ = gpuTypeToString(t.to, allowEmptyIdent = allowEmptyIdent)
      let ptrStar = gpuTypeToString(t.kind)
      result = typ & ptrStar
  of gtArray:
    # empty idents happen in e.g. function return types or casts
    if ident.len == 0 and not allowEmptyIdent: # and not allowArrayToPtr:
      when nimvm:
        error("Invalid call, got an array type but don't have an identifier: " & $t)
      else:
        raise newException(ValueError, "Invalid call, got an array type but don't have an identifier: " & $t)
    case t.aTyp.kind
    of gtArray: # nested array
      let typ = getInnerArrayType(t)        # get inner most type
      let lengths = getInnerArrayLengths(t) # get lengths as `[X][Y][Z]...`
      result = typ & " " & ident & lengths
    else:
      # NOTE: Nested arrays don't have an inner identifier!
      if t.aLen == 0: ## XXX: for the moment for 0 length arrays we generate flexible arrays instead
        result = gpuTypeToString(t.aTyp, allowEmptyIdent = allowEmptyIdent) & " " & ident & "[]"
      else:
        result = gpuTypeToString(t.aTyp, allowEmptyIdent = allowEmptyIdent) & " " & ident & "[" & $t.aLen & "]"
    skipIdent = true
  of gtObject: result = t.name
  else:        result = gpuTypeToString(t.kind)

  if ident.len > 0 and not skipIdent: # still need to add ident
    result.add " " & ident

proc genFunctionType*(typ: GpuType, fn: string, fnArgs: string): string =
  ## Returns the correct function with its return type
  if typ.kind == gtPtr and typ.to.kind == gtArray:
    # crazy stuff. Syntax to return a pointer to a statically sized array:
    # `Foo (*fnName(fnArgs))[ArrayLen]`
    # where the return type is actually:
    # `Foo (*)[ArrayLen]` (which already is hideous)
    let arrayTyp = typ.to.aTyp
    let innerTyp = gpuTypeToString(arrayTyp, allowEmptyIdent = true)
    let innerLen = $typ.to.aLen
    result = &"{innerTyp} (*{fn}({fnArgs}))[{innerLen}]"
  else:
    # normal stuff
    result = &"{gpuTypeToString(typ, allowEmptyIdent = true)} {fn}({fnArgs})"

proc genMemcpy(lhs, rhs, size: string): string =
  result = &"memcpy({lhs}, {rhs}, {size})"


proc genCuda*(ctx: var GpuContext, ast: GpuAst, indent = 0): string
proc size(ctx: var GpuContext, a: GpuAst): string = size(ctx.genCuda(a))
proc address(ctx: var GpuContext, a: GpuAst): string = address(ctx.genCuda(a))

proc genCuda*(ctx: var GpuContext, ast: GpuAst, indent = 0): string =
  ## The actual CUDA code generator.
  let indentStr = "  ".repeat(indent)
  case ast.kind
  of gpuVoid: return # nothing to emit
  of gpuProc:
    let attrs = collect:
      for att in ast.pAttributes:
        $att

    # Parameters
    var params: seq[string]
    for p in ast.pParams:
      params.add gpuTypeToString(p.typ, p.ident.ident(), allowEmptyIdent = false)
    let fnArgs = params.join(", ")
    let fnSig = genFunctionType(ast.pRetType, ast.pName.ident(), fnArgs)

    # extern "C" is needed to avoid name mangling
    result = indentStr & "extern \"C\" " & attrs.join(" ") & " " &
             fnSig & "{\n"

    result &= ctx.genCuda(ast.pBody, indent + 1)
    result &= "\n" & indentStr & "}"

  of gpuBlock:
    result = ""
    if ast.blockLabel.len > 0:
      result.add "\n" & indentStr & "{ // " & ast.blockLabel & "\n"
    for i, el in ast.statements:
      result.add ctx.genCuda(el, indent)
      if el.kind != gpuBlock and not ctx.skipSemicolon: # nested block ⇒ ; already added
        result.add ";"
      if i < ast.statements.high:
        result.add "\n"
    if ast.blockLabel.len > 0:
      result.add "\n" & indentStr & "} // " & ast.blockLabel & "\n"

  of gpuVar:
    result = indentStr & ast.vAttributes.join(" ") & " " & gpuTypeToString(ast.vType, ast.vName.ident())
    # If there is an initialization, the type might require a memcpy
    if ast.vInit.kind != gpuVoid and not ast.vRequiresMemcpy:
      result &= " = " & ctx.genCuda(ast.vInit)
    elif ast.vInit.kind != gpuVoid:
      result.add ";\n"
      result.add indentStr & genMemcpy(address(ast.vName.ident()), ctx.address(ast.vInit),
                                       size(ast.vName.ident()))

  of gpuAssign:
    if ast.aRequiresMemcpy:
      result = indentStr & genMemcpy(ctx.address(ast.aLeft), ctx.address(ast.aRight),
                                     ctx.size(ast.aLeft))
    else:
      result = indentStr & ctx.genCuda(ast.aLeft) & " = " & ctx.genCuda(ast.aRight)

  of gpuIf:
    # skip semicolon in the condition. Otherwise can lead to problematic code
    ctx.withoutSemicolon: # skip semicolon for if bodies
      result = indentStr & "if (" & ctx.genCuda(ast.ifCond) & ") {\n"
    result &= ctx.genCuda(ast.ifThen, indent + 1) & "\n"
    result &= indentStr & "}"
    if ast.ifElse.kind != gpuVoid:
      result &= " else {\n"
      result &= ctx.genCuda(ast.ifElse, indent + 1) & "\n"
      result &= indentStr & "}"

  of gpuFor:
    result = indentStr & "for(int " & ast.fVar.ident() & " = " &
             ctx.genCuda(ast.fStart) & "; " &
             ast.fVar.ident() & " < " & ctx.genCuda(ast.fEnd) & "; " &
             ast.fVar.ident() & "++) {\n"
    result &= ctx.genCuda(ast.fBody, indent + 1) & "\n"
    result &= indentStr & "}"
  of gpuWhile:
    ctx.withoutSemicolon:
      result = indentStr & "while (" & ctx.genCuda(ast.wCond) & "){\n"
    result &= ctx.genCuda(ast.wBody, indent + 1) & "\n"
    result &= indentStr & "}"

  of gpuDot:
    result = ctx.genCuda(ast.dParent) & "." & ctx.genCuda(ast.dField)

  of gpuIndex:
    result = ctx.genCuda(ast.iArr) & "[" & ctx.genCuda(ast.iIndex) & "]"

  of gpuCall:
    result = indentStr & ast.cName.ident() & "(" &
             ast.cArgs.mapIt(ctx.genCuda(it)).join(", ") & ")"

  of gpuTemplateCall:
    when nimvm:
      error("Template calls are not supported at the moment. In theory there shouldn't even _be_ any template " &
        "calls in the expanded body of the `cuda` macro.")
    else:
      raise newException(ValueError, "Template calls are not supported at the moment. In theory there shouldn't even _be_ any template " &
        "calls in the expanded body of the `cuda` macro.")
    when false: # Template replacement would look something like this:
      let templ = ctx.templates[ast.tcName]
      let expandedBody = substituteTemplateArgs(
        templ.body,
        templ.params,
        ast.tcArgs
      )
      result = ctx.genCuda(expandedBody, indent)

  of gpuBinOp:
    result = indentStr & "(" & ctx.genCuda(ast.bLeft) & " " &
             ast.bOp & " " &
             ctx.genCuda(ast.bRight) & ")"

  of gpuIdent:
    result = ast.ident()

  of gpuLit:
    if ast.lType.kind == gtString: result = "\"" & ast.lValue & "\""
    elif ast.lValue == "DEFAULT": result = "{}" # default initialization, `DEFAULT` placeholder
    else: result = ast.lValue

  of gpuArrayLit:
    result = "{"
    for i, el in ast.aValues:
      result.add "(" & gpuTypeToString(ast.aLitType) & ")" & el
      if i < ast.aValues.high:
        result.add ", "
    result.add "}"

  of gpuReturn:
    result = indentStr & "return " & ctx.genCuda(ast.rValue)

  of gpuPrefix:
    result = ast.pOp & ctx.genCuda(ast.pVal)

  of gpuTypeDef:
    result = "struct " & ast.tName & "{\n"
    for el in ast.tFields:
      result.add "  " & gpuTypeToString(el.typ, el.name) & ";\n"
    result.add "}"

  of gpuObjConstr:
    result = "{"
    for i, el in ast.ocFields:
      result.add ctx.genCuda(el.value)
      if i < ast.ocFields.len - 1:
        result.add ", "
    result.add "}"

  of gpuInlineAsm:
    result = indentStr & "asm(" & ast.stmt.strip & ");"

  of gpuComment:
    result = indentStr & "/* " & ast.comment & " */"

  of gpuConv:
    result = "(" & gpuTypeToString(ast.convTo, allowEmptyIdent = true) & ")" & ctx.genCuda(ast.convExpr)
  of gpuCast:
    result = "(" & gpuTypeToString(ast.cTo, allowEmptyIdent = true) & ")" & ctx.genCuda(ast.cExpr)

  of gpuAddr:
    result = "(&" & ctx.genCuda(ast.aOf) & ")"

  of gpuDeref:
    result = "(*" & ctx.genCuda(ast.dOf) & ")"

  of gpuConstexpr:
    if ast.cType.kind == gtArray:
      result = indentStr & "__constant__ " & gpuTypeToString(ast.cType, ctx.genCuda(ast.cIdent)) & " = " & ctx.genCuda(ast.cValue)
    else:
      result = indentStr & "__constant__ " & gpuTypeToString(ast.cType, allowEmptyIdent = true) & " " & ctx.genCuda(ast.cIdent) & " = " & ctx.genCuda(ast.cValue)

  else:
    echo "Unhandled node kind in genCuda: ", ast.kind
    raiseAssert "Unhandled node kind in genCuda: " & ast.repr
    result = ""
