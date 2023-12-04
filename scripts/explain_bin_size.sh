#!/bin/sh
# Explain size of ELF .o files (does not work with gcc -flto).
nm -oS --defined-only -fposix -td "$@" |
    sort -nk5 | awk '{print $1,$2,$3,$5}'