#!/bin/sh
# clang driver for the Nim→C compile of Constantine targeting rv64im freestanding
# (no OS, no libc). Nim's --clang.exe takes a bare program path, so the target flags
# ride along in this shim. The standalone include dir (declaration-only headers) is
# resolved relative to this script; mem*/alloca resolve to compiler builtins and
# malloc/free to the embedder's allocator at link time.
set -e
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
if [ -z "${CLANG:-}" ]; then
  if [ "$(uname -s)" = "Darwin" ]; then
    BREW_LLVM=$(brew --prefix llvm 2>/dev/null || true)
    CLANG=${BREW_LLVM:+$BREW_LLVM/bin/clang}
  fi
  CLANG=${CLANG:-clang}
fi
# shellcheck disable=SC2086
exec "$CLANG" --target=riscv64-unknown-none-elf -march=rv64im -mabi=lp64 -mno-relax -ffreestanding -ffunction-sections -fdata-sections -isystem "$HERE/include/standalone" -Wno-incompatible-pointer-types -Wno-int-conversion "$@"
