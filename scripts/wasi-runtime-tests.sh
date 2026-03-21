#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/wasi-common.sh"

cd "$REPO_ROOT"

prepare_tmp() {
  rm -rf "$WASI_TMP_DIR"
  mkdir -p "$WASI_TMP_DIR"

  printf 'alpha\nbeta\n' > "$WASI_TMP_DIR/in.txt"
  printf 'c\na\nb\na\n' > "$WASI_TMP_DIR/text.txt"
  printf 'a\nb\n' > "$WASI_TMP_DIR/a.txt"
  printf '1\n2\n' > "$WASI_TMP_DIR/b.txt"
  printf 'abc\n' > "$WASI_TMP_DIR/hash.txt"
  printf '1\n2\n3\n4\n' > "$WASI_TMP_DIR/tail.txt"
  printf 'a    b\n' > "$WASI_TMP_DIR/spaces.txt"
  printf 'a\tb\n' > "$WASI_TMP_DIR/tabs.txt"
}

run_ok() {
  name=$1
  shift
  echo "== PASS: $name =="
  if run_wasmer "$@"; then
    echo
  else
    status=$?
    echo "FAILED unexpectedly: $name (exit $status)" >&2
    exit $status
  fi
}

run_fail() {
  name=$1
  shift
  echo "== EXPECTED FAIL: $name =="
  if run_wasmer "$@"; then
    echo "Unexpected success: $name" >&2
    exit 1
  else
    status=$?
    echo "failed as expected (exit $status)"
    echo
  fi
}

run_ok_sh() {
  name=$1
  shift
  echo "== PASS: $name =="
  if sh -c "$*"; then
    echo
  else
    status=$?
    echo "FAILED unexpectedly: $name (exit $status)" >&2
    exit $status
  fi
}

ensure_wasmer_env
prepare_tmp

echo "== Runtime setup =="
echo "REPO_ROOT=$REPO_ROOT"
echo "WASMER_BIN=$WASMER_BIN"
echo "WASMER_DIR=$WASMER_DIR"
echo "WASMER_CACHE_DIR=$WASMER_CACHE_DIR"
echo "WASI_TMP_DIR=$WASI_TMP_DIR"
echo

run_ok "echo" ./src/echo -- "hello wasm"
run_ok "date" ./src/date -- "+%Y-%m-%d %H:%M:%S"
run_ok "pwd" ./src/pwd --dir=. --
run_ok "cat" ./src/cat --mapdir /:"$REPO_ROOT" -- /README-install
run_ok "test -f" ./src/test --mapdir /:"$REPO_ROOT" -- -f /README-install
run_ok "printf" ./src/printf -- "hello %s\n" wasm
run_ok "true" ./src/true --
run_fail "false" ./src/false --
run_ok "uname -a" ./src/uname -- -a
run_ok "head" ./src/head --mapdir /:"$REPO_ROOT" -- -n 3 /README-install
run_ok "realpath" ./src/realpath --mapdir /:"$REPO_ROOT" -- /README-install
run_ok "dirname" ./src/dirname -- /foo/bar.txt
run_ok "seq" ./src/seq -- 3
run_ok "sha1sum" ./src/sha1sum --mapdir /w:"$WASI_TMP_DIR" -- /w/hash.txt
run_ok "sha256sum" ./src/sha256sum --mapdir /:"$REPO_ROOT" -- /README-install
run_ok "sha512sum" ./src/sha512sum --mapdir /w:"$WASI_TMP_DIR" -- /w/hash.txt
run_ok "md5sum" ./src/md5sum --mapdir /w:"$WASI_TMP_DIR" -- /w/hash.txt
run_ok "sum" ./src/sum --mapdir /:"$REPO_ROOT" -- /README-install
run_ok "nproc" ./src/nproc --
run_ok "env" ./src/env --
run_ok "printenv" ./src/printenv --
run_ok "touch" ./src/touch --mapdir /w:"$WASI_TMP_DIR" -- /w/touched
run_ok "rm" ./src/rm --mapdir /w:"$WASI_TMP_DIR" -- /w/touched
run_ok "cut" ./src/cut --mapdir /w:"$WASI_TMP_DIR" -- -c 1 /w/text.txt
run_ok "paste" ./src/paste --mapdir /w:"$WASI_TMP_DIR" -- /w/a.txt /w/b.txt
run_ok "sort" ./src/sort --mapdir /w:"$WASI_TMP_DIR" -- /w/text.txt
run_ok "uniq" ./src/uniq --mapdir /w:"$WASI_TMP_DIR" -- /w/text.txt
run_ok_sh "tee" \
  "printf 'a\nb\n' | WASMER_DIR='$WASMER_DIR' WASMER_CACHE_DIR='$WASMER_CACHE_DIR' '$WASMER_BIN' run ./src/tee --mapdir /w:'$WASI_TMP_DIR' -- /w/out.txt >/dev/null"
run_ok "stat" ./src/stat --mapdir /w:"$WASI_TMP_DIR" -- /w/hash.txt
run_ok "expand" ./src/expand --mapdir /w:"$WASI_TMP_DIR" -- /w/tabs.txt
run_ok "expr" ./src/expr -- 1 + 2
run_ok "pathchk" ./src/pathchk -- /safe/path

run_fail "ls" ./src/ls --mapdir /:"$REPO_ROOT" -- /
run_fail "wc" ./src/wc --mapdir /:"$REPO_ROOT" -- -l /README-install
run_fail "cksum" ./src/cksum --mapdir /w:"$WASI_TMP_DIR" -- /w/hash.txt
run_fail "basename" ./src/basename -- /foo/bar.txt
run_fail "cp" ./src/cp --mapdir /w:"$WASI_TMP_DIR" -- /w/hash.txt /w/copy.txt
run_fail "mv" ./src/mv --mapdir /w:"$WASI_TMP_DIR" -- /w/hash.txt /w/moved.txt
run_fail "tail" ./src/tail --mapdir /w:"$WASI_TMP_DIR" -- -n 2 /w/tail.txt
run_fail "unexpand" ./src/unexpand --mapdir /w:"$WASI_TMP_DIR" -- /w/spaces.txt
run_fail "whoami" ./src/whoami --
run_fail "groups" ./src/groups --
run_fail "id" ./src/id --
run_fail "logname" ./src/logname --
run_fail "readlink" ./src/readlink --mapdir /:"$REPO_ROOT" -- /README-install
mkdir -p "$WASI_TMP_DIR/dir1"
run_fail "rmdir" ./src/rmdir --mapdir /w:"$WASI_TMP_DIR" -- /w/dir1

echo "All scripted checks completed."
