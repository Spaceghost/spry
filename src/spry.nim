# Spry Language executable
#
# Copyright (c) 2015 Göran Krampe

# Enable when profiling
when defined(profiler):
  import nimprof

import os, parseopt2

import spryvm

import sprycore, sprylib, spryextend, sprymath, spryos, spryio, sprythread,
 spryoo, sprydebug, sprycompress, sprystring, sprymodules, spryreflect,
 spryblock, sprynet, spryjson

# import sprypython

var spry = newInterpreter()

# Add extra modules
spry.addCore()
spry.addExtend()
spry.addMath()
spry.addOS()
spry.addIO()
spry.addThread()
#spry.addPython()
spry.addOO()
spry.addDebug()
spry.addCompress()
spry.addString()
spry.addModules()
spry.addReflect()
#spry.addUI()
spry.addBlock()
spry.addNet()
spry.addJSON()
#spry.addSophia()
spry.addLib()


let doc = """

Usage:
  spry [options] <path-or-stdin>

Options:
  -e --eval "code"    Evaluates Spry code given as string
  -h --help           Show this screen
  -v --version        Show version of Spry
"""

proc writeVersion() =
  echo "Spry 0.6"

proc writeHelp() =
  writeVersion()
  echo doc
  quit()

var
  filename: string
  eval = false
  code: string

for kind, key, val in getopt():
  case kind
  of cmdArgument:
    filename = key
  of cmdLongOption, cmdShortOption:
    case key
    of "help", "h":
      writeHelp()
    of "version", "v":
      writeVersion()
      quit()
    of "eval", "e": eval = true
  of cmdEnd: assert(false) # cannot happen

if eval:
  if filename == nil:
    writeHelp()
  else:
    code = filename
else:
  code =
    if filename == nil:
      # no filename has been given, so we use stdin
      readAll stdin
    else:
      readFile(filename)

discard spry.eval("[" & code & "]")
