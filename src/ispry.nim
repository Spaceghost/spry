# Interactive Spry REPL
#
# Copyright (c) 2015 Göran Krampe
#
# I am not fond of REPLs, since I think they are silly dumb approximations
# of the real thing - a fully live environment like Smalltalk!
#
# But ok, its nice as a starter and for going through a tutorial :)

import os, strutils
when defined(readLine):
  import rdstdin
  when not defined(Windows):
    import linenoise

# Basic Spry
import spryvm

# Spry extra modules, as much as possible!
import spryextend, sprymath, spryos, spryio, sprythread, sprypython, spryoo, sprydebug, sprycompress, sprystring, sprymodules

const Prompt = ">>> "

when defined(readLine) and not defined(Windows):
  const HistoryFile = ".ispry-history"
  # Load existing history file
  discard historyLoad(HistoryFile)
  # Makes sure editing wraps for long lines?
  setMultiLine(1)

proc getLine(prompt: string): string =
  # Using line editing
  when defined(readLine):
    result = readLineFromStdin(prompt)
    when not defined(Windows):
      discard historySave(HistoryFile)
  else:
    # Primitive fallback
    stdout.write(prompt)
    result = stdin.readline()

proc main() =
  # Let's create a Spry interpreter. It also holds all state.
  let spry = newInterpreter()
  spry.addExtend()
  spry.addMath()
  spry.addOS()
  spry.addIO()
  spry.addThread()
  spry.addPython()
  spry.addOO()
  spry.addDebug()
  spry.addCompress()
  spry.addString()
  spry.addModules()

  var
    lines, stashed, fileLines = newSeq[string]()
    suspended: bool = true

  # Check if a file was given as input, if so collect lines
  # and set suspended = false which means we start out following the given
  # script instead of interactively.
  if commandLineParams().len > 0:
    let fn = commandLineParams()[0]
    if fn.len() > 0:
      suspended = false
      for line in lines(fn):
        fileLines.add(line)

  echo "Welcome to interactive Spry!"
  echo "An empty line will evaluate previous lines, so hit enter twice."
  # We collect lines until an empty line is entered, easy way to enter
  # multiline code.

  while true:
    var line: string
    if suspended:
      line = getLine(Prompt)
    else:
      if fileLines.len == 0:
        quit 0
      # Read a line, eh, would be nice with removeFirst or popFirst...
      line = fileLines[0]
      fileLines.delete(0)
      # Logic for pausing
      if line.strip() == "# pause":
        var enter = getLine("         <enter = eval, s = suspend>")
        if enter.strip() == "s":
          stdout.write("         <suspended, c = continue>\n")
          stashed = lines
          lines = newSeq[string]()
          suspended = true
        continue
      else:
        stdout.write(line & "\n")

    # Logic to start the script again
    if suspended and line.strip() == "c":
      lines = stashed
      suspended = false
      continue

    # Finally time to eval
    if line.strip().len() == 0:
      let code = lines.join("\n")
      lines = newSeq[string]()
      try:
        # Let the interpreter eval the code. We need to eval whatever we
        # get (ispry acting as a func) - but we also need to use parens or
        # it may get weird. The surrounding block is just because we only
        # want to pass one Node.
        var output = $spry.evalRoot("[" & code & "]")
        # Print any result
        if output.isNil:
          output = if suspended: "nil" else: ""
        stdout.write(output & "\n")
      except:
        echo "Oops, sorry about that: " & getCurrentExceptionMsg() & "\n"
        echo getStackTrace()
    else:
      lines.add(line)

main()
