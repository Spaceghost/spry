# Ni Language
#
# Copyright (c) 2015 Göran Krampe


## TODO: Make infix work properly without parens by swapping?
## TODO: Make parens more lightweight, now they carry a Context etc etc
## TODO: Optimize away lots of book keeping to get a bit more speed

import strutils, sequtils, tables, nimprof

type
  # Ni interpreter
  Interpreter* = ref object
    args*: seq[Node]         # Collecting args for infix
    stack*: seq[Activation]  # Execution stack
    root*: Context           # Root bindings
    trueVal: Node
    falseVal: Node
    nilVal: Node

  RuntimeException* = object of Exception
  ParseException* = object of Exception

  # The parser builds a Node tree using a stack for nested blocks
  Parser* = ref object
    token: string                       # Collects the current token
    stack: seq[Node]                    # Lexical stack of Nodes
    valueParsers*: seq[ValueParser]     # Registered valueParsers

  # Base class for pluggable value parsers
  ValueParser* = ref object of RootObj
    token: string
  
  # Basic value parsers included by default
  IntValueParser = ref object of ValueParser
  StringValueParser = ref object of ValueParser
  FloatValueParser = ref object of ValueParser

  # We use an object variant for the parse Node in classic Araq style
  NodeKind* = enum niWord, niSetWord, niGetWord, niSymbolWord, niValue,
    niBlock, niParen, niCurly, niBinding, niSetBinding

  # Nodes form an AST which we later eval directly using Interpreter
  Node* = ref object of RootObj
    case kind*: NodeKind
    # The four word "formats" correspond to Rebol
    of niWord, niSetWord, niGetWord, niSymbolWord:
      word*:  string
    # A value node is some kind of "thing" :)
    of niValue:
      value*: Value
    # All these have child nodes
    # TODO: Curly is not yet explored
    of niBlock, niParen, niCurly:
      nodes*: seq[Node]
      resolved*: bool # A flag so we resolve "only first time" when using bind
    of niBinding, niSetBinding:
      binding*: Binding # When resolving a niBinding replaces a niWord
      

  # The activation record used by Interpreter for executing blocks
  Activation = ref object
    paren: Node            # The paren we are running
    closure: BlockClosure  # ...or the bound block we are running TODO: Improve
    pos: int               # Which node we are at
    context: Context       # The context of the closure above

  # Contexts holds Bindings. This way we, when forming a closure we can lookup
  # a word to get the Binding and from then on simply set/get the val on the
  # Binding instead.
  Binding = ref object
    key: string
    val: Node

  # An "object" basically in Rebol terminology, named slots of Nodes.
  # Idea is to represent them in code using {name: "Göran" age: 46}
  # They are also used as our internal namespaces and so on.
  Context = ref object
    bindings: ref Table[string, Binding]

  # Values are also represented with an object variant, like Node
  ValueKind* = enum niInt, niFloat, niString, niBool, niNil,
    niContext, niProc, niClosure
  Value* = object
    case kind*: ValueKind
    of niInt:     intVal*: int64 # Seems reasonable for Ni
    of niFloat:   floatVal*: float64 # Same
    of niString:  stringVal*: string
    of niBool:    boolVal*: bool
    of niNil:     nil # No need for a value :)
    of niContext: contextVal*: Context
    of niProc:    procVal*: NimProc
    of niClosure: closureVal*: BlockClosure
    
  # Base for behaviors, either primitives in Nim or Ni blocks
  Function = ref object of RootObj
    infix*: bool
    arity*: int
  
  # Signature for Nim primitives
  ProcType = proc(ni: Interpreter, a: varargs[Node]): Node
  # A wrapped Nim proc
  NimProc* = ref object of Function
    prok*: ProcType

  # A block node that has been bound so we can execute it as a function
  BlockClosure* = ref object of Function
    node*: Node
    context*: Context


# Utilities I would like to have in stdlib
template isEmpty[T](a: openArray[T]): bool =
  a.len == 0
template notEmpty[T](a: openArray[T]): bool =
  a.len > 0
template notNil[T](a:T): bool =
  not a.isNil
template debug(x: untyped) =
  when false: echo(x)

# Extending Ni from other modules
type ParserExt = proc(p: Parser)
var parserExts = newSeq[ParserExt]()

proc addParserExtension*(prok: ParserExt) =
  parserExts.add(prok)

type InterpreterExt = proc(ni: Interpreter)
var interpreterExts = newSeq[InterpreterExt]()

proc addInterpreterExtension*(prok: InterpreterExt) =
  interpreterExts.add(prok)

# Forward declarations
proc closureBlock*(ni: Interpreter, node: Node): Node
proc resolve(self: Node, ni: Interpreter)
proc parse*(self: Parser, str: string): Node
proc eval*(self: Node, ni: Interpreter): Node
proc `$`*(self: Node): string

# String representations
proc `$`*(self: Binding): string =
  self.key & ":" & $self.val

proc `$`*(self: Context): string =
  result = "{"
  for k,v in self.bindings:
    result.add($v & " ")
  return result & "}"

proc `$`*(self: Value): string =
  case self.kind
  of niInt:
    $self.intVal
  of niFloat:
    $self.floatVal
  of niString:
    "\"" & self.stringVal & "\""
  of niBool:
    $self.boolVal
  of niNil:
    "nil"
  of niContext:
    $self.contextVal
  of niProc:
    "proc(" & $self.procVal.arity & ")"
  of niClosure:
    "closure(" & $self.closureVal.node & ")"

proc `$`*(self: seq[Node]): string =
  self.map(proc(n: Node): string = $n).join(" ")



proc `$`*(self: Node): string =
  case self.kind
  of niWord:
    self.word
  of niSetWord:
    self.word & ":"
  of niGetWord:
    ":" & self.word
  of niSymbolWord:
    "'" & self.word
  of niValue:
    $self.value
  of niBlock:
    "[" & $self.nodes & "]"
  of niParen:
    "(" & $self.nodes & ")"
  of niCurly:
    "{" & $self.nodes & "}"
  of niBinding:
    "%" & $self.binding & "%"
  of niSetBinding:
    ":%" & $self.binding & "%"

# Nifties
template add(self: Node, n: Node) =
  self.nodes.add(n)

proc isFunction(self: Node): bool =
  case self.kind
  of niValue:
    case self.value.kind
    of niProc, niClosure:
      true
    else:
      false
  else:
    false

# Constructor procs
proc raiseRuntimeException*(msg: string) =
  raise newException(RuntimeException, msg)

proc raiseParseException*(msg: string) =
  raise newException(ParseException, msg)

proc newContext*(): Context =
  Context(bindings: newTable[string, Binding]())
  
proc newNimProc*(prok: ProcType, infix: bool, arity: int): NimProc =
  NimProc(prok: prok, infix: infix, arity: arity)

proc newBlockClosure*(node: Node, infix: bool, arity: int): BlockClosure =
  BlockClosure(node: node, infix: infix, arity: arity)

proc newWord*(s: string): Node =
  Node(kind: niWord, word: s)

proc newSetWord*(s: string): Node =
  Node(kind: niSetWord, word: s)

proc newGetWord*(s: string): Node =
  Node(kind: niGetWord, word: s)

proc newSymbolWord*(s: string): Node =
  Node(kind: niSymbolWord, word: s)

proc newBlock*(nodes: seq[Node]): Node =
  Node(kind: niBlock, nodes: nodes)
  
proc newBlock*(): Node =
  newBlock(newSeq[Node]())

proc newParen*(): Node =
  Node(kind: niParen, nodes: newSeq[Node]())

proc newCurly*(): Node =
  Node(kind: niCurly, nodes: newSeq[Node]())

proc newBinding*(b: Binding): Node =
  Node(kind: niBinding, binding: b)

proc newSetBinding*(b: Binding): Node =
  Node(kind: niSetBinding, binding: b)

proc newActivation*(closure: BlockClosure): Activation =
  Activation(closure: closure, context: closure.context)

proc newActivation*(paren: Node): Activation =
  Activation(paren: paren)

proc newValue*(v: int64): Node =
  Node(kind: niValue, value: Value(kind: niInt, intVal: v))

proc newValue*(v: float64): Node =
  Node(kind: niValue, value: Value(kind: niFloat, floatVal: v))

proc newValue*(v: string): Node =
  Node(kind: niValue, value: Value(kind: niString, stringVal: v))

proc newValue*(v: bool): Node =
  Node(kind: niValue, value: Value(kind: niBool, boolVal: v))

proc newNilValue*(): Node =
  Node(kind: niValue, value: Value(kind: niNil))

proc newValue*(v: NimProc): Node =
  Node(kind: niValue, value: Value(kind: niProc, procVal: v))

proc newValue*(v: Context): Node =
  Node(kind: niValue, value: Value(kind: niContext, contextVal: v))

proc newValue*(v: BlockClosure): Node =
  Node(kind: niValue, value: Value(kind: niClosure, closureVal: v))

proc newPrim*(prok: ProcType, infix: bool, arity: int): Node =
  newValue(NimProc(prok: prok, infix: infix, arity: arity))

# Context lookups
proc lookup*(self: Context, key: string): Binding =
  self.bindings[key]

proc bindit*(self: Context, key: string, val: Node): Binding =
  result = Binding(key: key, val: val)
  self.bindings[key] = result

# Methods for the base value parsers
method parseValue(self: ValueParser, s: string): Node {.procvar.} =
  nil

method parseValue(self: IntValueParser, s: string): Node {.procvar.} =
  try:
    return newValue(parseInt(s)) 
  except ValueError:
    return nil

method parseValue(self: FloatValueParser, s: string): Node {.procvar.} =
  try:
    return newValue(parseFloat(s)) 
  except ValueError:
    return nil

method parseValue(self: StringValueParser, s: string): Node {.procvar.} =
  # If it ends and starts with '"' then ok, no escapes yet
  if s.len > 1 and s[0] == '"' and s[^1] == '"':
    result = newValue(s[1..^2])

method prefixLength(self: ValueParser): int = 0

method tokenReady(self: ValueParser, token: string, ch: char): string =
  ## Return true if self wants to take over parsing a literal
  ## and deciding when its complete. This is used for delimited literals
  ## that can contain whitespace. Otherwise parseValue is needed.
  nil

method tokenStart(self: ValueParser, token: string, ch: char): bool =
  false

method prefixLength(self: StringValueParser): int = 1

method tokenStart(self: StringValueParser, token: string, ch: char): bool =
  ch == '"'

method tokenReady(self: StringValueParser, token: string, ch: char): string =
  # Minimally two '"' and the previous char was not '\'
  if ch == '"' and token[^1] != '\\':
    return token & ch
  else:
    return nil

proc newParser*(): Parser =
  ## Create a new Ni parser with the basic value parsers included
  result = Parser(stack: newSeq[Node](), valueParsers: newSeq[ValueParser]())
  result.valueParsers.add(StringValueParser())
  result.valueParsers.add(IntValueParser())
  result.valueParsers.add(FloatValueParser())
  # Call registered extension procs
  for ex in parserExts:
    ex(result)

# Converters
converter toValue(x: int64): Value =
  result.kind = niInt
  result.intVal = x
converter toValue(x: float64): Value =
  result.kind = niFloat
  result.floatVal = x
converter toValue(x: string): Value =
  result.kind = niString
  result.stringVal = x

converter toString(x: Value): string =
  x.stringVal
converter toFloat(x: int64): float64 =
  x.float64
converter toInt(x: Value): int64 =
  x.intVal
converter toFloat(x: Value): float64 =
  x.floatVal

proc resolveBlock(ni: Interpreter, self: Node): Node =
  debug "RESOLVING" & $self
  self.resolve(ni)
  self.resolved = true
  debug "RESOLVED: " & $self
  self

proc dump(ni: Interpreter) =
  echo "ROOT: " & $ni.root
  for a in ni.stack:
    if a.context.notNil:
      echo "CONTEXT: " & $a.context

# Primitives written in Nim
proc primAdd(ni: Interpreter, a: varargs[Node]): Node =
  newValue(a[0].value.intVal + a[1].value.intVal)
proc primSub(ni: Interpreter, a: varargs[Node]): Node =
  newValue(a[0].value.intVal - a[1].value.intVal)
proc primMul(ni: Interpreter, a: varargs[Node]): Node =
  newValue(a[0].value.intVal * a[1].value.intVal)
proc primDiv(ni: Interpreter, a: varargs[Node]): Node =
  newValue(a[0].value.intVal / a[1].value.intVal)
proc primLt(ni: Interpreter, a: varargs[Node]): Node =
  newValue(a[0].value.intVal < a[1].value.intVal)
proc primGt(ni: Interpreter, a: varargs[Node]): Node =
  newValue(a[0].value.intVal > a[1].value.intVal)
proc primDo(ni: Interpreter, a: varargs[Node]): Node =
  ni.closureBlock(a[0]).eval(ni)
proc primClosure(ni: Interpreter, a: varargs[Node]): Node =
  ni.closureBlock(a[0])
proc primResolve(ni: Interpreter, a: varargs[Node]): Node =
  ni.resolveBlock(a[0])
proc primParse(ni: Interpreter, a: varargs[Node]): Node =
  newParser().parse(a[0].value.stringVal)
proc primEcho(ni: Interpreter, a: varargs[Node]): Node =
  echo($a[0])
proc primIf(ni: Interpreter, a: varargs[Node]): Node =
  if a[0].value.boolVal: ni.primDo(a[1]) else: ni.nilVal
proc primIfelse(ni: Interpreter, a: varargs[Node]): Node =
  if a[0].value.boolVal: ni.primDo(a[1]) else: ni.primDo(a[2])
proc primLoop(ni: Interpreter, a: varargs[Node]): Node =
  for i in 1 .. a[0].value.intVal:
    result = ni.primDo(a[1])
proc primDump(ni: Interpreter, a: varargs[Node]): Node =
  ni.dump

proc newInterpreter*(): Interpreter =
  result = Interpreter(stack: newSeq[Activation](), args: newSeq[Node](), root: newContext())
  # Singletons
  result.trueVal = newValue(true)
  result.falseVal = newValue(false)
  result.nilVal = newNilValue()
  let root = result.root
  discard root.bindit("false", result.falseVal)
  discard root.bindit("true", newValue(true))
  discard root.bindit("nil", newNilValue())  
  # Primitives in Nim
  discard root.bindit("+", newPrim(primAdd, true, 2))
  discard root.bindit("-", newPrim(primSub, true, 2))
  discard root.bindit("*", newPrim(primMul, true, 2))
  discard root.bindit("/", newPrim(primDiv, true, 2))
  discard root.bindit("<", newPrim(primLt, true, 2))
  discard root.bindit(">", newPrim(primGt, true, 2))
  discard root.bindit("closure", newPrim(primClosure, false, 1))
  discard root.bindit("resolve", newPrim(primResolve, false, 1))
  discard root.bindit("do", newPrim(primDo, false, 1))
  discard root.bindit("parse", newPrim(primParse, false, 1))
  discard root.bindit("echo", newPrim(primEcho, false, 1))
  discard root.bindit("if", newPrim(primIf, false, 2))
  discard root.bindit("ifelse", newPrim(primIfelse, false, 3))
  discard root.bindit("loop", newPrim(primLoop, false, 2))
  discard root.bindit("dump", newPrim(primDump, false, 1))
  # Call registered extension procs
  for ex in interpreterExts:
    ex(result)

proc top(ni: Interpreter): Activation =
  ni.stack[ni.stack.high]


proc lookup(ni: Interpreter, key: string): Binding =
#  if ni.stack.notEmpty and ni.top.context.notNil:
#    result = ni.top.context.lookup(key)
  if result.isNil:
    result = ni.root.lookup(key)
    if result.notNil: debug("FOUND " & key & " IN ROOT: " & $result) 
#  else:
#    debug("FOUND " & key & " IN CONTEXT: " & $result)

proc bindit(ni: Interpreter, key: string, val: Node): Binding =
# TODO: Need a way to distinguish between where to bind... so only root for now
#  if ni.stack.notEmpty:
#    if ni.top.context.isNil:
#      ni.top.context = newContext()
#    debug("BIND IN CONTEXT: " & $key & ": " & $val)
#    ni.top.context.bindit(key, val)
#  else:
    debug("BIND IN ROOT: " & $key & ": " & $val)
    ni.root.bindit(key, val)

proc `[]`(self: Node, i: int): Node =
  ## We allow indexing of Nodes if they are of the composite kind.
  case self.kind
  of niBlock, niParen, niCurly:
    self.nodes[i]
  else:
    nil

proc len(self: Node): int =
  ## Return number of child nodes
  case self.kind
  of niBlock, niParen, niCurly:
    self.nodes.len
  else:
    0

proc len(self: Activation): int =
  if self.closure.isNil:
    self.paren.len
  else:
    self.closure.node.len

proc `[]`(self: Value, i: int): Node =
  case self.kind
  of niClosure:
    self.closureVal.node.nodes[i]
  else:
    nil

proc endOfBlock*(ni: Interpreter): bool =
  let activation = ni.top
  activation.pos == activation.len

proc next(ni: Interpreter): Node =
  ## Get next node in the current block Activation.
  let activation = ni.top
  if activation.pos == activation.len:
    raiseRuntimeException("End of current block, too few arguments")
  else:
    if activation.closure.isNil:
      result = activation.paren[activation.pos]
    else:
      result = activation.closure.node[activation.pos]
    inc activation.pos

proc evalNext*(ni: Interpreter): Node =
  ## Evaluate the next node in the current block Activation.
  ni.next.eval(ni)

proc evalParen*(ni: Interpreter, node: Node): Node =
  ## Evaluate all nodes in the paren, then return last
  ni.stack.add(newActivation(node))
  while not ni.endOfBlock:
    ni.args.add(ni.evalNext())
  discard ni.stack.pop
  result = ni.args.pop
  #echo "POPRESULT: " & $result
  ni.args = @[]

proc eval(self: NimProc, ni: Interpreter): Node =
  var args: seq[Node] = @[]
  if self.infix:
    # If infix we pop the last one gathered
    args.add(ni.args.pop)
  # Pull remaining args to reach arity
  for i in args.len .. self.arity-1:
    args.add(ni.evalNext())
  #debug("ARGS: " & $args)
  self.prok(ni, args)

proc resolve(self: Node, ni: Interpreter) =
  ## Go through tree and do lookups of words, replacing with the binding.
  case self.kind
  of niBlock, niParen, niCurly:
    for pos,child in mpairs(self.nodes):
      case child.kind
      of niBlock, niParen, niCurly:
        child.resolve(ni) # Recurse
      of niWord:
        let hit = ni.lookup(child.word)
        if hit.notNil:
          self.nodes[pos] = newBinding(hit)
      of niSetWord:
        let hit = ni.lookup(child.word)
        if hit.notNil:
          self.nodes[pos] = newSetBinding(hit)
      else:
        discard
  else:
    raiseRuntimeException("Can only resolve composite nodes, not: " & $self)

proc closureBlock(ni: Interpreter, node: Node): Node =
  case node.kind
  of niBlock:
    if not node.resolved:
      discard ni.resolveBlock(node)
    # TODO infix/arity
    return newValue(newBlockClosure(node, false, 0))
  else:
    raiseRuntimeException("Can only bind blocks, not: " & $node)

proc eval*(self: BlockClosure, ni: Interpreter): Node =
  debug("EVALCLOSURE")
  ## Let the interpreter do a given Block and return the result as a Node.
  ni.stack.add(newActivation(self))
  while not ni.endOfBlock:
    ni.args.add(ni.evalNext())
    debug("ARGS:" & $ni.args)
  discard ni.stack.pop
  result = ni.args.pop
  debug("POPRESULT: " & $result)
  ni.args = @[]

proc eval(self: Node, ni: Interpreter): Node =
  ## This is the heart of the Interpreter
  case self.kind
  of niWord:
    let binding = ni.lookup(self.word)
    if binding.isNil:
      raiseRuntimeException("Word not found: " & self.word)
    return binding.val.eval(ni)
  of niSetWord:
    debug("SETW:" & self.word)
    return ni.bindit(self.word, ni.evalNext()).val
  of niGetWord:
    return ni.lookup(self.word).val
  of niSymbolWord:
    return self
  of niValue:
    return case self.value.kind
    of niProc:
      self.value.procVal.eval(ni)
    of niClosure:
      self.value.closureVal.eval(ni)
    else:
      self
  of niBlock:
    return self
  of niParen:
    return ni.evalParen(self)
  of niCurly:
    return self # Produce a Context I think...
  of niBinding:
    # Eval of a niBinding is like a static fast niWord
    return self.binding.val.eval(ni)
  of niSetBinding:
    # Eval of a niSetBinding is like a static fast niSetWord
    result = ni.evalNext()
    self.binding.val = result

proc newWordOrValue(self: Parser): Node =
  ## Decide what to make, a word or value
  let token = self.token
  self.token = ""
  
  # Try values here...
  for p in self.valueParsers:
    let valueOrNil = p.parseValue(token)
    if valueOrNil.notNil:
      return valueOrNil

  # Then it must be a word
  if token[0] == ':':
    return newGetWord(token[1..^1])
  if token[^1] == ':':
    return newSetWord(token[0..^2])
  if token[0] == '\'':
    return newSymbolWord(token[1..^1])
  return newWord(token)

proc top(self: Parser): Node =
  self.stack[self.stack.high]

proc pop(self: Parser) =
  discard self.stack.pop()

proc push(self: Parser, n: Node) =
  if not self.stack.isEmpty:
    self.top.add(n)
  self.stack.add(n)

proc addNode(self: Parser) =
  if self.token.len > 0:
    self.top.add(self.newWordOrValue())
    self.token = ""

proc parse*(self: Parser, str: string): Node =
  var ch: char
  var currentValueParser: ValueParser
  var pos = 0
  self.stack = @[]
  self.token = ""
  # Wrap code in a block, well, ok... then we can just call primDo on it.
  self.push(newBlock())
  # Parsing is done in a single pass char by char, recursive descent
  while pos < str.len:
    ch = str[pos]
    inc pos
    # If we are inside a literal value let the valueParser decide when complete
    if currentValueParser.notNil:
      let found = currentValueParser.tokenReady(self.token, ch)
      if found.notNil:
        self.token = found
        self.addNode()
        currentValueParser = nil
      else:
        self.token.add(ch)
    else:
      # If we are not parsing a literal with a valueParser whitespace is consumed
      if currentValueParser.isNil and ch in Whitespace:
        # But first we make sure to finish the token if any
        self.addNode()
      else:
        # Check if a valueParser wants to take over, only 5 first chars are checked
        let tokenLen = self.token.len + 1
        if currentValueParser.isNil and tokenLen < 5:
          for p in self.valueParsers:
            if p.prefixLength == tokenLen and p.tokenStart(self.token, ch):
              currentValueParser = p
              break
        # If still no valueParser active we do regular token handling
        if currentValueParser.isNil:
          case ch
          # Comments are not included in the AST
          of '#':
            self.addNode()
            while not (str[pos] == '\l'):
              inc pos
          # Paren
          of '(':
            self.addNode()
            self.push(newParen())
          # Block
          of '[':
            self.addNode()
            self.push(newBlock())
          # Curly
          of '{':
            self.addNode()
            self.push(newCurly())
          of ')':
            self.addNode()
            self.pop
          # Block
          of ']':
            self.addNode()
            self.pop
          # Curly
          of '}':
            self.addNode()
            self.pop
          # Ok, otherwise we just collect the char
          else:
            self.token.add(ch)
        else:
          self.token.add(ch)
  self.addNode()
  self.top

proc eval*(ni: Interpreter, code: string): Node =
  ni.primDo(newParser().parse(code))


when isMainModule:
  # Just run a given file as argument
  import os
  let fn = commandLineParams()[0]
  let code = readFile(fn)
  discard newInterpreter().eval(code)
