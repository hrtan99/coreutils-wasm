#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

: "${WASI_HOST:=wasm32-wasip1}"
: "${WASI_SDK_DIR:=/Users/hrtan/Downloads/wasi-sdk-32.0-arm64-macos}"
: "${WASI_BIN_DIR:=$WASI_SDK_DIR/bin}"

: "${WASI_CC:=$WASI_BIN_DIR/wasm32-wasip1-clang}"
: "${WASI_AR:=$WASI_BIN_DIR/llvm-ar}"
: "${WASI_RANLIB:=$WASI_BIN_DIR/llvm-ranlib}"

: "${AUTOCONF_BIN:=autoconf}"
: "${AUTOMAKE_BIN:=automake-1.18}"
: "${BISON_BIN:=/opt/homebrew/opt/bison/bin/bison}"

: "${WASMER_SH:=/Users/hrtan/.wasmer/wasmer.sh}"
: "${WASMER_BIN:=/Users/hrtan/.wasmer/bin/wasmer}"
: "${WASMER_DIR:=/tmp/wasmer7-home}"
: "${WASMER_CACHE_DIR:=/tmp/wasmer7-cache}"

: "${BUILD_JOBS:=8}"
: "${WASI_TMP_DIR:=$REPO_ROOT/wasi-tmp}"

export REPO_ROOT
export WASI_HOST
export WASI_SDK_DIR
export WASI_BIN_DIR
export WASI_CC
export WASI_AR
export WASI_RANLIB
export AUTOCONF_BIN
export AUTOMAKE_BIN
export BISON_BIN
export WASMER_SH
export WASMER_BIN
export WASMER_DIR
export WASMER_CACHE_DIR
export BUILD_JOBS
export WASI_TMP_DIR

export PATH="$WASI_BIN_DIR:$PATH"

ensure_wasmer_env() {
  if [ -f "$WASMER_SH" ]; then
    # shellcheck disable=SC1090
    . "$WASMER_SH"
  fi
  mkdir -p "$WASMER_DIR" "$WASMER_CACHE_DIR"
}

run_wasmer() {
  ensure_wasmer_env
  WASMER_DIR=$WASMER_DIR WASMER_CACHE_DIR=$WASMER_CACHE_DIR \
    "$WASMER_BIN" run "$@"
}
