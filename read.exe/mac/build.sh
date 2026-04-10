#!/bin/bash
set -e
SRC="$(dirname "$0")/main.cpp"
OUT="$(dirname "$0")/read"

echo "Compiling $SRC"
c++ -O2 -std=c++17 -o "$OUT" "$SRC"
echo "[OK] Built: $OUT"
