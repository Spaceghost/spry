Files and what they are.

# Core Spry

* spryvm.nim    - The Spry interpreter and parser.
* sprytest.nim  - Accompanying tests for the Spry interpreter
* test.sh       - Trivial shell script to run sprytest.nim
* testjs.sh     - Trivial shell script to run sprytest.nim compiled for nodejs

# Spry executables

* spry      - The kitchen sink Spry interpreter useful for scripting
* ispry     - A first shot at a REPL for playing and for running interactive tutorials
* sprymin   - A minimal core Spry interpreter with only a few modules 
* sprymicro - As small as it can get, source is embedded

# Going small
The Spry interpreter is fairly small, only around 1100 lines of code but it does include the Nim soft realtime GC so we can't
go ultra small. But using for example musl-libc or diet-libc you can make a statically linked stripped 64 bit x86_64 VM
that is only around 100kb. Clang makes a smaller non-size optimized binary, but larger size optimized.

## musl-libc
If you want to try building with musl-libc (which seems to be the most competent small libc) you need to install
musl-dev and then use a build command like this (replace sprymin with spry/sprymicro/ispry)::

```
nim -d:release --opt:size --passL:-static --gcc.exe:musl-gcc --gcc.linkerexe:musl-gcc c sprymin && strip -s sprymin
```
On my machine that produces a nimin around 124kb and nimicro around 95kb.

## diet-libc
If you want to try building with diet-libc you need to install dietlibc-dev and add this file:

gokr@yoda:~/nim/ni/src$ cat /usr/bin/dietgcc 
diet gcc $@

...then use a build command like this (replace sprymin with spry/sprymicro/ispry), sprymicro is the absolute smallest:

```
nim -d:release --opt:size --passL:-static --gcc.exe:dietgcc --gcc.linkerexe:dietgcc c sprymin && strip -s sprymin
```
On my machine that produces a sprymin around 103kb and sprymicro around 95kb.
