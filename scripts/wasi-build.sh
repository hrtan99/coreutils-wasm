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

echo "== Tool paths =="
echo "REPO_ROOT=$REPO_ROOT"
echo "WASI_SDK_DIR=$WASI_SDK_DIR"
echo "WASI_CC=$WASI_CC"
echo "WASI_AR=$WASI_AR"
echo "WASI_RANLIB=$WASI_RANLIB"
echo "AUTOCONF_BIN=$AUTOCONF_BIN"
echo "AUTOMAKE_BIN=$AUTOMAKE_BIN"
echo "BISON_BIN=$BISON_BIN"
echo "WASMER_BIN=$WASMER_BIN"
echo

echo "== Configure =="
CC=$WASI_CC AR=$WASI_AR RANLIB=$WASI_RANLIB \
  ./configure \
  --host="$WASI_HOST" \
  --disable-nls \
  --disable-dependency-tracking

repair_generated_makefile Makefile

echo
echo "== Build =="
make -j"$BUILD_JOBS"
