#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/wasi-common.sh"

cd "$REPO_ROOT"

repair_generated_makefile() {
  makefile_path=$1

  if ! grep -q '^built_programs = ' "$makefile_path"; then
    return 0
  fi

  tmp_path=$makefile_path.tmp

  awk '
    BEGIN {
      in_built_programs = 0
      built_programs = ""
    }

    function flush_built_programs() {
      if (in_built_programs) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", built_programs)
        print "built_programs = " built_programs
        in_built_programs = 0
        built_programs = ""
      }
    }

    /^built_programs = / {
      in_built_programs = 1
      built_programs = substr($0, length("built_programs = ") + 1)
      next
    }

    in_built_programs {
      if ($0 ~ /^[[:alnum:]_][[:alnum:]_]*[[:space:]]*=/) {
        flush_built_programs()
        print
      } else {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
        if ($0 != "") {
          if (built_programs != "") {
            built_programs = built_programs " " $0
          } else {
            built_programs = $0
          }
        }
      }
      next
    }

    {
      print
    }

    END {
      flush_built_programs()
    }
  ' "$makefile_path" >"$tmp_path"

  mv "$tmp_path" "$makefile_path"
}

: "${TARGET_PROG:=echo}"
: "${TARGET_BIN:=src/$TARGET_PROG}"
: "${TARGET_OBJ:=src/$TARGET_PROG.o}"
: "${WAT_OUT:=src/$TARGET_PROG.wat}"
: "${NOSTDLIB_WASM_OUT:=src/$TARGET_PROG.nostdlib.wasm}"
: "${NOSTDLIB_WAT_OUT:=src/$TARGET_PROG.nostdlib.wat}"
: "${DEBUG_CFLAGS:=-O0 -g3 -fno-inline -fno-omit-frame-pointer}"
: "${DEBUG_LDFLAGS:=-Wl,--export-all -Wl,--export-table -Wl,--no-gc-sections}"
: "${NOSTDLIB_INTERNAL_LIBS:=src/libver.a lib/libcoreutils.a lib/libcoreutils.a}"
: "${NOSTDLIB_ALLOWED_IMPORTS_REGEX_FILE:=scripts/wasi-allowed-imports.regex}"
: "${NOSTDLIB_MIN_IMPORTS:=1}"

if [ ! -x "$WASM2WAT_BIN" ]; then
  echo "error: wasm2wat tool not found: $WASM2WAT_BIN" >&2
  echo "set WASM2WAT_BIN to your wasm2wat executable path." >&2
  exit 1
fi

if [ ! -x "$WASM_LD_BIN" ]; then
  echo "error: wasm-ld tool not found: $WASM_LD_BIN" >&2
  echo "set WASM_LD_BIN to your wasm-ld executable path." >&2
  exit 1
fi

if [ ! -f "$NOSTDLIB_ALLOWED_IMPORTS_REGEX_FILE" ]; then
  echo "error: allowlist file not found: $NOSTDLIB_ALLOWED_IMPORTS_REGEX_FILE" >&2
  exit 1
fi

check_nostdlib_imports() {
  wat_path=$1
  allowlist_path=$2

  imports_raw_file=$(mktemp "${TMPDIR:-/tmp}/wasi-imports-raw.XXXXXX")
  imports_file=$(mktemp "${TMPDIR:-/tmp}/wasi-imports.XXXXXX")
  bad_imports_file=$(mktemp "${TMPDIR:-/tmp}/wasi-bad-imports.XXXXXX")

  awk '
    $1 == "(import" && $2 ~ /^"/ && $3 ~ /^"/ {
      module = $2
      symbol = $3
      gsub(/"/, "", module)
      gsub(/"/, "", symbol)
      print module ":" symbol
    }
  ' "$wat_path" >"$imports_raw_file"

  sort -u "$imports_raw_file" >"$imports_file"

  awk '
    NR == FNR {
      if ($0 ~ /^[[:space:]]*$/) next
      if ($0 ~ /^[[:space:]]*#/) next
      n++
      patterns[n] = $0
      next
    }
    {
      ok = 0
      for (i = 1; i <= n; i++) {
        if ($0 ~ patterns[i]) {
          ok = 1
          break
        }
      }
      if (!ok) {
        print $0
      }
    }
  ' "$allowlist_path" "$imports_file" >"$bad_imports_file"

  bad_count=$(wc -l <"$bad_imports_file")
  total_count=$(wc -l <"$imports_file")

  if [ "$total_count" -lt "$NOSTDLIB_MIN_IMPORTS" ]; then
    echo
    echo "Import policy check: FAIL"
    echo "  imports found: $total_count (minimum required: $NOSTDLIB_MIN_IMPORTS)"
    rm -f "$imports_raw_file" "$imports_file" "$bad_imports_file"
    return 1
  fi

  if [ "$bad_count" -ne 0 ]; then
    echo
    echo "Import policy check: FAIL"
    echo "  unexpected imports: $bad_count / $total_count"
    sed 's/^/  - /' "$bad_imports_file"
    rm -f "$imports_raw_file" "$imports_file" "$bad_imports_file"
    return 1
  fi

  echo
  echo "Import policy check: PASS ($total_count imports)"
  rm -f "$imports_raw_file" "$imports_file" "$bad_imports_file"
}

echo "== Debug Build Config =="
echo "TARGET_PROG=$TARGET_PROG"
echo "TARGET_BIN=$TARGET_BIN"
echo "TARGET_OBJ=$TARGET_OBJ"
echo "WAT_OUT=$WAT_OUT"
echo "NOSTDLIB_WASM_OUT=$NOSTDLIB_WASM_OUT"
echo "NOSTDLIB_WAT_OUT=$NOSTDLIB_WAT_OUT"
echo "NOSTDLIB_INTERNAL_LIBS=$NOSTDLIB_INTERNAL_LIBS"
echo "NOSTDLIB_ALLOWED_IMPORTS_REGEX_FILE=$NOSTDLIB_ALLOWED_IMPORTS_REGEX_FILE"
echo "DEBUG_CFLAGS=$DEBUG_CFLAGS"
echo "DEBUG_LDFLAGS=$DEBUG_LDFLAGS"
echo "WASI_CC=$WASI_CC"
echo "WASM_LD_BIN=$WASM_LD_BIN"
echo "WASM2WAT_BIN=$WASM2WAT_BIN"
echo

echo "== Configure =="
CC=$WASI_CC AR=$WASI_AR RANLIB=$WASI_RANLIB \
  ./configure \
  --host="$WASI_HOST" \
  --disable-nls \
  --disable-dependency-tracking

repair_generated_makefile Makefile

echo
echo "== Build ($TARGET_BIN) =="
make -j"$BUILD_JOBS" \
  "CFLAGS=$DEBUG_CFLAGS" \
  "LDFLAGS=$DEBUG_LDFLAGS" \
  "$TARGET_BIN"

if [ ! -f "$TARGET_BIN" ]; then
  echo "error: expected wasm binary not found: $TARGET_BIN" >&2
  exit 1
fi

if [ ! -f "$TARGET_OBJ" ]; then
  echo "error: expected object file not found: $TARGET_OBJ" >&2
  exit 1
fi

for internal_lib in $NOSTDLIB_INTERNAL_LIBS; do
  if [ ! -f "$internal_lib" ]; then
    echo "error: expected internal library not found: $internal_lib" >&2
    exit 1
  fi
done

echo
echo "== Generate WAT =="
"$WASM2WAT_BIN" --generate-names "$TARGET_BIN" -o "$WAT_OUT"

echo
echo "== Generate No-Stdlib WASM (Internal Libs Linked) =="
"$WASM_LD_BIN" \
  --no-entry \
  --export-all \
  --export-table \
  --allow-undefined \
  --import-undefined \
  -o "$NOSTDLIB_WASM_OUT" \
  "$TARGET_OBJ" \
  $NOSTDLIB_INTERNAL_LIBS

echo
echo "== Generate No-Stdlib WAT =="
"$WASM2WAT_BIN" --generate-names "$NOSTDLIB_WASM_OUT" -o "$NOSTDLIB_WAT_OUT"

check_nostdlib_imports "$NOSTDLIB_WAT_OUT" "$NOSTDLIB_ALLOWED_IMPORTS_REGEX_FILE"

echo
echo "Done."
echo "WASM: $TARGET_BIN"
echo "WAT:  $WAT_OUT"
echo "No-Stdlib WASM: $NOSTDLIB_WASM_OUT"
echo "No-Stdlib WAT:  $NOSTDLIB_WAT_OUT"
