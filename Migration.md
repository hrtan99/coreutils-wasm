# Coreutils To WASI Migration Notes

This document records the current status of the local migration work that builds
GNU coreutils as `wasm32-wasip1` binaries with `wasi-sdk` on macOS.

It focuses on:

- the source revision used for this work
- the host environment and toolchain versions
- the build configuration that was used
- the main migration issues encountered
- the source-level and build-level fixes applied
- the current runtime status under Wasmer 7


## 1. Source Baseline

Repository:

- local checkout of GNU coreutils

Current commit at the time this document was written:

- `5ec45a1aa`

Observed version metadata from the tree:

- `configure.ac` declares package name `GNU coreutils`
- `build-aux/git-version-gen .tarball-version` currently returns `UNKNOWN`

Notes:

- The tree is not in a clean upstream release state.
- There are local modifications in the worktree, and `gnulib` is also modified.
- The source headers and copyright years indicate a 2026-era coreutils tree.


## 2. Host Environment

Machine:

- Apple Silicon Mac
- `arm64`

Operating system:

- `macOS 26.3`
- build `25D125`

Kernel:

- `Darwin 25.3.0`

Output captured during migration:

```sh
uname -a
Darwin hrtans-MacBook-Pro-10.local 25.3.0 Darwin Kernel Version 25.3.0: Wed Jan 28 20:48:41 PST 2026; root:xnu-12377.81.4~5/RELEASE_ARM64_T6041 arm64

sw_vers
ProductName:		macOS
ProductVersion:		26.3
BuildVersion:		25D125
```


## 3. Tool Versions

Primary WASI toolchain:

- `wasi-sdk 32.0`
- installed under `/Users/hrtan/Downloads/wasi-sdk-32.0-arm64-macos`

Compiler used for the target build:

```sh
/Users/hrtan/Downloads/wasi-sdk-32.0-arm64-macos/bin/wasm32-wasip1-clang --version
clang version 22.1.0-wasi-sdk
Target: wasm32-unknown-wasip1
Thread model: posix
```

Autotools and parser generator used locally:

- `autoconf 2.72`
- `automake 1.18.1`
- `bison 3.8.2`

Other notable host-side tools:

- `GNU Make 3.81`
- host `clang 21.0.0git`
- `Wasmer 7.0.1`

Versions captured during migration:

```sh
autoconf (GNU Autoconf) 2.72
automake (GNU automake) 1.18.1
bison (GNU Bison) 3.8.2
wasmer 7.0.1
clang version 21.0.0git
GNU Make 3.81
```


## 4. Build Configuration Used

The stable configure invocation used for the current WASI build is:

```sh
PATH="/Users/hrtan/Downloads/wasi-sdk-32.0-arm64-macos/bin:$PATH" \
CC=wasm32-wasip1-clang \
AR=llvm-ar \
RANLIB=llvm-ranlib \
./configure --host=wasm32-wasip1 --disable-nls --disable-dependency-tracking
```

The stable build invocation is:

```sh
PATH="/Users/hrtan/Downloads/wasi-sdk-32.0-arm64-macos/bin:$PATH" \
make -j6
```

Important configure choices:

- `--host=wasm32-wasip1`
  This switches the tree into cross-compilation mode for WASI Preview 1.
- `--disable-nls`
  This avoids bringing translation/runtime locale infrastructure into the WASI build.
- `--disable-dependency-tracking`
  This was required because repeated autotools regeneration in this tree could leave
  `config.status` in a broken dependency-tracking bootstrap path on macOS.


## 5. High-Level Migration Strategy

The migration was handled in three layers:

1. build-system pruning
   Disable or avoid parts of the normal Unix build that are not useful for a
   cross-compiled WASI target, such as `po`, `gnulib-tests`, manpage generation,
   and some generated helper programs.

2. libc and POSIX compatibility shims
   Provide minimal implementations or safe fallbacks for interfaces that WASI
   does not provide, such as user/group database access, process control,
   signals, `ttyname`, `umask`, and pieces of spawn/pipe support.

3. iterative compile/link/runtime triage
   Re-run the build, fix the first concrete failure, and repeat until the tree
   links and a meaningful subset of commands can run under a WASI runtime.


## 6. Build-System Problems Encountered And Fixes

### 6.1 `po/`, docs, tests, and non-target recursion blocked the build

Problem:

- A normal coreutils build expects a much richer Unix host environment.
- For the WASI target, recursive entry into `po/`, `gnulib-tests`, and doc/man
  generation caused early failures unrelated to target executables.

Fix:

- Added a `WASI_HOST` conditional in `[configure.ac](/Users/hrtan/Projects/coreutils/configure.ac)`.
- Used that conditional in `[Makefile.am](/Users/hrtan/Projects/coreutils/Makefile.am)` to:
  - skip `po`
  - skip `gnulib-tests`
  - drop manpage generation inputs for WASI builds

Result:

- `configure` and top-level `make` could progress into actual target code.


### 6.2 `factor` repeatedly re-entered the build and failed

Problem:

- `src/factor.c` fails a static assertion under the current WASI type model.
- Even after removing `factor` from one generated make fragment, autotools regeneration
  kept reintroducing it through another path.

Fix:

- Filtered `factor` from the WASI `optional_bin_progs` list in
  `[configure.ac](/Users/hrtan/Projects/coreutils/configure.ac)`.
- Restored `[src/cu-progs.mk](/Users/hrtan/Projects/coreutils/src/cu-progs.mk)` to a normal generated form
  after earlier experiments.
- Avoided relying on GNU-make-only filtering inside `src/local.mk`, because automake
  mis-parsed it and treated `filter-out` as a bogus target/program name.

Result:

- The WASI build now excludes `factor` in the generated program list.


### 6.3 Automake regeneration broke dependency tracking

Problem:

- After editing autotools inputs, `make` triggered `automake` and `config.status --recheck`.
- The resulting `config.status` sometimes failed with:
  `Something went wrong bootstrapping makefile fragments for automatic dependency tracking`.

Fix:

- Re-ran configure explicitly with `--disable-dependency-tracking`.

Result:

- The tree could be regenerated and built reliably again.


### 6.4 `parse-datetime.c` generation failed

Problem:

- `lib/parse-datetime.c` is generated from `lib/parse-datetime.y`.
- The Apple system `bison` was too old.
- One intermediate failed generation left `lib/parse-datetime.c` as an empty file.

Fix:

- Installed and used Homebrew `bison 3.8.2`.
- Regenerated the parser manually and materialized `lib/parse-datetime.c`.

Result:

- `date` and other commands depending on parse-datetime logic could link again.


## 7. Source-Level Compatibility Problems And Fixes

This migration required a large number of targeted compatibility changes.
The intent was not to implement full Unix semantics on WASI, but to make the
programs compile, link, and behave sensibly where possible.


### 7.1 Signal support and signal emulation

Problem:

- Coreutils and gnulib expect more POSIX signal support than plain WASI provides.

Fix:

- Enabled `_WASI_EMULATED_SIGNAL` in `[Makefile.am](/Users/hrtan/Projects/coreutils/Makefile.am)`.
- Linked against `-lwasi-emulated-signal` and `-lsetjmp` from
  `[src/local.mk](/Users/hrtan/Projects/coreutils/src/local.mk)`.
- Adjusted gnulib signal-related wrappers, including
  `[gnulib/lib/signal.in.h](/Users/hrtan/Projects/coreutils/gnulib/lib/signal.in.h)`.
- Disabled the local `raise` implementation under WASI to avoid duplicate symbol
  conflicts with the emulation library.

Result:

- Signal-related compile and link failures were removed.


### 7.2 Missing POSIX user/group/process interfaces

Problem:

- WASI does not provide normal Unix account, login, or process identity APIs.
- Commands such as `id`, `groups`, `whoami`, and `logname` depend on these.

Fix:

- Added local stub headers:
  - `[pwd.h](/Users/hrtan/Projects/coreutils/pwd.h)`
  - `[grp.h](/Users/hrtan/Projects/coreutils/grp.h)`
  - `[sys/wait.h](/Users/hrtan/Projects/coreutils/sys/wait.h)`
- Added inline stubs and fallback macros in
  `[src/system.h](/Users/hrtan/Projects/coreutils/src/system.h)` for:
  - `geteuid`, `getuid`, `getegid`, `getgid`
  - `umask`
  - `execvp`
  - `kill`
  - `ttyname`
- Added a minimal WASI `getgroups` path in
  `[lib/getgroups.c](/Users/hrtan/Projects/coreutils/lib/getgroups.c)` and
  `[gnulib/lib/getgroups.c](/Users/hrtan/Projects/coreutils/gnulib/lib/getgroups.c)`.

Result:

- The tree compiles and many commands run.
- Account-related commands still remain runtime-limited, which is documented in
  `README-wasi-runtime.md`.


### 7.3 File descriptor and directory API mismatches

Problem:

- Several gnulib replacements assumed Unix semantics for `dup`, `dup2`, `opendirat`,
  and related `fcntl` behavior.

Fix:

- Reworked:
  - `lib/dup.c`
  - `lib/dup2.c`
  - gnulib copies of the same files
- Used `fcntl(F_DUPFD_CLOEXEC)` and `__wasilibc_fd_renumber` for WASI paths.
- Added a renamed helper path around `opendirat` in:
  - `lib/opendirat.h`
  - `lib/opendirat.c`
  - `lib/backupfile.c`
  - `lib/fts.c`
  - `gnulib/lib/fts.c`

Result:

- Directory walking and several file-oriented commands could compile and link.


### 7.4 Networking, locale, mount, and spawn support gaps

Problem:

- Gnulib expects richer libc and kernel support for:
  - DNS lookups
  - locale names
  - mount table discovery
  - pipe and spawn APIs

Fix:

- Added WASI-safe stubs or short-circuit implementations in:
  - `lib/getaddrinfo.c`
  - `lib/getlocalename_l-unsafe.c`
  - `lib/mountlist.c`
  - `lib/pipe.c`
  - `lib/pipe2.c`
  - `lib/spawni.c`
  - `lib/time_rz.c`
  - `lib/mktime.c`
  - `lib/savewd.c`
  - and corresponding gnulib copies

Result:

- The tree can link a much larger executable set even where full behavior is not
  available under WASI.


### 7.5 Missing libc entry points discovered during iterative linking

Problems encountered during linking included:

- `flockfile` / `funlockfile`
- `umask`
- `clock`
- `getgroups`
- `ttyname`

Fixes:

- Converted `getopt.c` to use no-op macros for `flockfile`/`funlockfile` under WASI.
- Added `umask` and `ttyname` inline fallbacks in `src/system.h`.
- Removed `clock()` usage as fallback entropy in `tempname.c` under WASI.
- Added explicit WASI `getgroups` fallback behavior.

Result:

- Link-time failures were cleared one by one until the build completed.


### 7.6 Problematic compile-time assertions

Problem:

- Some static assertions that are valid on normal Unix builds break under the
  current WASI type setup.

Fix:

- Disabled the problematic assertion block in
  `[src/head.c](/Users/hrtan/Projects/coreutils/src/head.c)` for `__wasi__`.

Result:

- `head` compiled and later ran successfully under Wasmer 7.


## 8. Runtime Validation

Runtime validation was performed primarily with:

- `Wasmer 5.0.4`
- later `Wasmer 7.0.1`

Why Wasmer 7 was installed:

- Wasmer 5 could run simple commands but failed earlier on exception-handling support.
- Wasmer 7 improved runtime compatibility for a larger subset of commands.

The current runtime status is documented separately in:

- `[README-wasi-runtime.md](/Users/hrtan/Projects/coreutils/README-wasi-runtime.md)`

Summary:

- A useful subset of commands now runs under Wasmer 7.
- Some commands still fail due to:
  - runtime feature mismatches (`ls`)
  - incomplete WASI shims for user/group lookup
  - remaining memory handling or logic bugs in specific utilities


## 9. Files Most Heavily Involved In This Migration

Build-system files:

- `[configure.ac](/Users/hrtan/Projects/coreutils/configure.ac)`
- `[Makefile.am](/Users/hrtan/Projects/coreutils/Makefile.am)`
- `[src/local.mk](/Users/hrtan/Projects/coreutils/src/local.mk)`
- `[src/cu-progs.mk](/Users/hrtan/Projects/coreutils/src/cu-progs.mk)`

Core compatibility shim and program files:

- `[src/system.h](/Users/hrtan/Projects/coreutils/src/system.h)`
- `[src/head.c](/Users/hrtan/Projects/coreutils/src/head.c)`
- `[pwd.h](/Users/hrtan/Projects/coreutils/pwd.h)`
- `[grp.h](/Users/hrtan/Projects/coreutils/grp.h)`
- `[sys/wait.h](/Users/hrtan/Projects/coreutils/sys/wait.h)`

Representative gnulib/lib fixes:

- `[lib/getopt.c](/Users/hrtan/Projects/coreutils/lib/getopt.c)`
- `[lib/getgroups.c](/Users/hrtan/Projects/coreutils/lib/getgroups.c)`
- `[lib/tempname.c](/Users/hrtan/Projects/coreutils/lib/tempname.c)`
- `[lib/raise.c](/Users/hrtan/Projects/coreutils/lib/raise.c)`
- `[gnulib/lib/getopt.c](/Users/hrtan/Projects/coreutils/gnulib/lib/getopt.c)`
- `[gnulib/lib/getgroups.c](/Users/hrtan/Projects/coreutils/gnulib/lib/getgroups.c)`
- `[gnulib/lib/tempname.c](/Users/hrtan/Projects/coreutils/gnulib/lib/tempname.c)`
- `[gnulib/lib/raise.c](/Users/hrtan/Projects/coreutils/gnulib/lib/raise.c)`


## 10. Current Status

Current state of the migration:

- the tree builds to `wasm32-wasip1` successfully on macOS
- a documented subset of commands runs under Wasmer 7
- runtime support is still partial, not feature-complete

What is already good enough:

- text formatting and simple text processing
- hashing and checksum tools based on modern digest paths
- basic file existence and metadata checks
- basic environment-driven and argument-driven commands

What still needs additional work:

- directory-heavy commands such as `ls`
- user/group/account commands
- commands currently failing with `memory exhausted`
- commands that still trap at runtime, such as `wc` and `cksum`


## 11. Recommended Next Steps

If this migration is continued, the highest-value next tasks are:

1. investigate `memory exhausted` failures
   Focus first on `basename`, `cp`, `mv`, `tail`, and `unexpand`.

2. investigate runtime traps
   Focus first on `wc` and `cksum`.

3. decide whether to support a second runtime
   `Wasmer 7` is useful, but not sufficient for all generated modules.

4. reduce generated-file drift
   Some steps in this migration temporarily relied on regenerated files and
   autotools behavior that is fragile under repeated regeneration.

5. keep runtime documentation in sync
   Update `README-wasi-runtime.md` as commands move between the usable and
   broken lists.
