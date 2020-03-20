when defined(i386) or defined(amd64):
  import x86
  export getTicks

# This doesn't always work unfortunately ...

proc volatilize(x: ptr byte) {.codegenDecl: "$# $#(char const volatile *x)", inline.} =
  discard

template preventOptimAway*[T](x: var T) =
  volatilize(cast[ptr byte](unsafeAddr x))

template preventOptimAway*[T](x: T) =
  volatilize(cast[ptr byte](x))
