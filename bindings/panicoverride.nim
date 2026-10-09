# Standalone panic hook for bare-metal guest builds.
# The compilerprocs replace the Nim runtime's default panic/output path.
{.push stack_trace: off, profiler: off.}

proc rawoutput(s: string) {.compilerproc, codegenDecl: "static $# $#$#".} =
  discard

proc c_builtin_trap() {.importc: "__builtin_trap", nodecl.}

proc panic(s: string) {.noreturn, compilerproc,
    codegenDecl: "static $# $#$#".} =
  rawoutput(s)
  c_builtin_trap()

{.pop.}
