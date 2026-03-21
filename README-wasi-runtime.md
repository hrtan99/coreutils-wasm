# Running Coreutils WASM With Wasmer 7

This document records the current runtime status of the WASI build in this
repository when executed with Wasmer 7 on macOS.

The results below are based on direct local tests in this repository, not on
assumptions.


## Runtime Setup

Wasmer 7 was installed under:

```sh
/Users/hrtan/.wasmer
```

Before running any command, load Wasmer and set temporary runtime directories:

```sh
source /Users/hrtan/.wasmer/wasmer.sh
export WASMER_DIR=/tmp/wasmer7-home
export WASMER_CACHE_DIR=/tmp/wasmer7-cache
mkdir -p "$WASMER_DIR" "$WASMER_CACHE_DIR"
```

When a command needs filesystem access, map a host directory into the guest:

```sh
wasmer run ./src/cat --mapdir /:"$PWD" -- /README-install
```

Note: Wasmer 7 currently warns that `--mapdir` is deprecated and will be
replaced by `--volume` in a future release.


## Usable Commands

The following commands were tested and completed successfully under Wasmer 7:

- `echo`
- `date`
- `cat`
- `test`
- `pwd`
- `printf`
- `true`
- `false`
- `uname`
- `head`
- `realpath`
- `dirname`
- `seq`
- `sha1sum`
- `sha256sum`
- `sha512sum`
- `md5sum`
- `sum`
- `nproc`
- `env`
- `printenv`
- `rm`
- `touch`
- `cut`
- `paste`
- `sort`
- `uniq`
- `tee`
- `stat`
- `expand`
- `expr`
- `pathchk`


## Broken Commands

The following commands were tested and are currently not reliable under Wasmer 7:

- `ls`
  Runtime error: `legacy_exceptions feature required for try instruction`
- `wc`
  Runtime trap: `out of bounds memory access`
- `cksum`
  Runtime trap: `out of bounds memory access`
- `basename`
  Fails with `memory exhausted`
- `cp`
  Fails with `memory exhausted`
- `mv`
  Fails with `memory exhausted`
- `tail`
  Fails with `memory exhausted`
- `unexpand`
  Fails with `memory exhausted`
- `whoami`
  Fails because user database lookups are stubbed under WASI
- `groups`
  Fails because group database lookups are stubbed under WASI
- `id`
  Produces partial output, then fails with `memory exhausted`
- `logname`
  Fails with `no login name`
- `readlink`
  Returns failure without useful output
- `rmdir`
  Failed in mapped-directory tests with `No such file or directory`


## Not Yet Stable

These commands either behaved suspiciously or were not clean enough to mark as
usable:

- `mkdir`
- `sleep`
- `fold`
- `truncate`


## Example Commands

These examples were verified locally.

Print a string:

```sh
wasmer run ./src/echo -- 'hello wasm'
```

Print the current date:

```sh
wasmer run ./src/date -- '+%Y-%m-%d %H:%M:%S'
```

Read a file from the repository:

```sh
wasmer run ./src/cat --mapdir /:"$PWD" -- /README-install
```

Check whether a file exists:

```sh
wasmer run ./src/test --mapdir /:"$PWD" -- -f /README-install
```

Show the first three lines of a file:

```sh
wasmer run ./src/head --mapdir /:"$PWD" -- -n 3 /README-install
```

Resolve a path:

```sh
wasmer run ./src/realpath --mapdir /:"$PWD" -- /README-install
```

Compute a SHA-256 digest:

```sh
wasmer run ./src/sha256sum --mapdir /:"$PWD" -- /README-install
```

Sort a file:

```sh
mkdir -p wasi-tmp
printf 'c\na\nb\na\n' > wasi-tmp/text.txt
wasmer run ./src/sort --mapdir /w:"$PWD/wasi-tmp" -- /w/text.txt
```

Use `tee` with redirected stdin:

```sh
mkdir -p wasi-tmp
printf 'a\nb\n' > wasi-tmp/in.txt
wasmer run ./src/tee --mapdir /w:"$PWD/wasi-tmp" -- /w/out.txt < wasi-tmp/in.txt
```


## Notes

- The current runtime target is practical for a subset of commands, especially
  text-processing, hashing, simple file inspection, and basic argument-driven
  utilities.
- Commands that depend on user/group databases or deeper runtime support are
  still limited by the WASI compatibility shims in this tree.
- Commands that fail with `memory exhausted` likely need further source-level
  fixes rather than a different invocation syntax.
