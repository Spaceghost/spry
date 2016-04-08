# Spry Language Interpreter
#
# Copyright (c) 2015 Göran Krampe

import strutils, sequtils, tables, hashes

type
  ParseException* = object of Exception

  # The iterative parser builds a Node tree using a stack for nested blocks
  Parser* = ref object
    token: string                       # Collects characters into a token
    stack: seq[Node]                    # Lexical stack of block Nodes
    valueParsers*: seq[ValueParser]     # Registered valueParsers for literals

  # Base class for pluggable value parsers
  ValueParser* = ref object of RootObj
    token: string

  # Basic value parsers included by default, true false and nil are instead
  # regular system words referring to singleton values
  IntValueParser = ref object of ValueParser
  FloatValueParser = ref object of ValueParser
  StringValueParser = ref object of ValueParser

  # Nodes form an AST which we later eval directly using Interpreter
  Node* = ref object of RootObj
    tags*: Blok
  Word* = ref object of Node
    word*: string
  GetW* = ref object of Word
  EvalW* = ref object of Word

  # These are all concrete word types
  LitWord* = ref object of Word

  EvalWord* = ref object of EvalW
  EvalSelfWord* = ref object of EvalW
  EvalOuterWord* = ref object of EvalW
  EvalArgWord* = ref object of EvalW

  GetWord* = ref object of GetW
  GetSelfWord* = ref object of GetW
  GetOuterWord* = ref object of GetW
  GetArgWord* = ref object of GetW

  # And support for keyword syntactic sugar, only used during parsing
  KeyWord* = ref object of Node
    keys*: seq[string]
    args*: seq[Node]

  Value* = ref object of Node
  IntVal* = ref object of Value
    value*: int
  FloatVal* = ref object of Value
    value*: float
  StringVal* = ref object of Value
    value*: string
  BoolVal* = ref object of Value
  TrueVal* = ref object of BoolVal
  FalseVal* = ref object of BoolVal

  UndefVal* = ref object of Value
  NilVal* = ref object of Value

  # Abstract
  Composite* = ref object of Node
  SeqComposite* = ref object of Node
    nodes*: seq[Node]
    pos*: int

  # Concrete
  Paren* = ref object of SeqComposite
  Blok* = ref object of SeqComposite
  Curly* = ref object of SeqComposite
  Map* = ref object of Composite
    bindings*: ref OrderedTable[Node, Binding]

  # Dictionaries currently holds Bindings instead of the value directly.
  # This way we we can later reify Binding
  # so we can hold it and set/get its value without lookup
  Binding* = ref object of Node
    key*: Node
    val*: Node

  RuntimeException* = object of Exception

proc raiseRuntimeException*(msg: string) =
  raise newException(RuntimeException, msg)

method hash*(self: Node): Hash {.base.} =
  raiseRuntimeException("Nodes need to implement hash")

method `==`*(self: Node, other: Node): bool {.base.} =
  raiseRuntimeException("Nodes need to implement ==")

method hash*(self: Word): Hash =
  self.word.hash

method `==`*(self: Word, other: Node): bool =
  other of Word and (self.word == Word(other).word)

method hash*(self: IntVal): Hash =
  self.value.hash

method `==`*(self: IntVal, other: Node): bool =
  other of IntVal and (self.value == IntVal(other).value)

method hash*(self: FloatVal): Hash =
  self.value.hash

method `==`*(self: FloatVal, other: Node): bool =
  other of FloatVal and (self.value == FloatVal(other).value)

method hash*(self: StringVal): Hash =
  self.value.hash

method `==`*(self: StringVal, other: Node): bool =
  other of StringVal and (self.value == StringVal(other).value)

method hash*(self: TrueVal): Hash =
  hash(1)

method hash*(self: FalseVal): Hash =
  hash(0)

method value*(self: BoolVal): bool {.base.} =
  true

method value*(self: FalseVal): bool =
  false

method `==`*(self, other: TrueVal): bool =
  true

method `==`*(self, other: FalseVal): bool =
  true

method `==`*(self: TrueVal, other: FalseVal): bool =
  false

method `==`*(self: FalseVal, other: TrueVal): bool =
  false

#method `==`*(self: BoolVal, other: Node): bool =
#  other of BoolVal and (self == BoolVal(other))

#method `==`*(other: Node, self: BoolVal): bool =
#  other of BoolVal and (self == BoolVal(other))

#method `==`*(other, self: BoolVal): bool =
#  self == other

method hash*(self: NilVal): Hash =
  hash(1)

method `==`*(self: Nilval, other: Node): bool =
  other of NilVal

method hash*(self: UndefVal): Hash =
  hash(2)

method `==`*(self: Undefval, other: Node): bool =
  other of UndefVal


# Utilities I would like to have in stdlib
template isEmpty*[T](a: openArray[T]): bool =
  a.len == 0
template notEmpty*[T](a: openArray[T]): bool =
  a.len > 0
template notNil*[T](a:T): bool =
  not a.isNil
template debug*(x: untyped) =
  when true: echo(x)

# Extending the Parser from other modules
type ParserExt = proc(p: Parser)
var parserExts = newSeq[ParserExt]()

proc addParserExtension*(prok: ParserExt) =
  parserExts.add(prok)

# Ni representations
method `$`*(self: Node): string {.base.} =
  # Fallback if missing
  when defined(js):
    echo "repr not available in js"
  else:
    repr(self)

method `$`*(self: Binding): string =
  $self.key & " = " & $self.val

method `$`*(self: Map): string =
  result = "{"
  var first = true
  for k,v in self.bindings:
    if first:
      result.add($v)
      first = false
    else:
      result.add(" " & $v)
  return result & "}"

method `$`*(self: IntVal): string =
  $self.value

method `$`*(self: FloatVal): string =
  $self.value

method `$`*(self: StringVal): string =
  escape(self.value)

method `$`*(self: TrueVal): string =
  "true"

method `$`*(self: FalseVal): string =
  "false"

method `$`*(self: NilVal): string =
  "nil"

method `$`*(self: UndefVal): string =
  "undef"

proc `$`*(self: seq[Node]): string =
  self.map(proc(n: Node): string = $n).join(" ")

method `$`*(self: Word): string =
  self.word

method `$`*(self: EvalWord): string =
  self.word

method `$`*(self: EvalSelfWord): string =
  "." & self.word

method `$`*(self: EvalOuterWord): string =
  ".." & self.word

method `$`*(self: GetWord): string =
  "^" & self.word

method `$`*(self: GetSelfWord): string =
  "^." & self.word

method `$`*(self: GetOuterWord): string =
  "^.." & self.word

method `$`*(self: LitWord): string =
  "'" & self.word

method `$`*(self: EvalArgWord): string =
  ":" & self.word

method `$`*(self: GetArgWord): string =
  ":^" & self.word

method `$`*(self: Blok): string =
  "[" & $self.nodes & "]"

method `$`*(self: Paren): string =
  "(" & $self.nodes & ")"

method `$`*(self: Curly): string =
  "{" & $self.nodes & "}"

method `$`*(self: KeyWord): string =
  result = ""
  for i in 0 .. self.keys.len - 1:
    result = result & self.keys[i] & " " & $self.args[i]

# Human string representations
method form*(self: Node): string {.base.} =
  # Default is to use $
  $self

method form*(self: StringVal): string =
  # No surrounding ""
  $self.value

# Map lookups
proc lookup*(self: Map, key: Node): Binding =
  self.bindings.getOrDefault(key)

proc makeBinding*(self: Map, key: Node, val: Node): Binding =
  result = Binding(key: key, val: val)
  self.bindings[key] = result

# Constructor procs
proc raiseParseException(msg: string) =
  raise newException(ParseException, msg)

proc newMap*(): Map =
  Map(bindings: newOrderedTable[Node, Binding]())

proc newEvalWord*(s: string): EvalWord =
  EvalWord(word: s)

proc newEvalSelfWord*(s: string): EvalSelfWord =
  EvalSelfWord(word: s)

proc newEvalOuterWord*(s: string): EvalOuterWord =
  EvalOuterWord(word: s)

proc newGetWord*(s: string): GetWord =
  GetWord(word: s)

proc newGetSelfWord*(s: string): GetSelfWord =
  GetSelfWord(word: s)

proc newGetOuterWord*(s: string): GetOuterWord =
  GetOuterWord(word: s)

proc newLitWord*(s: string): LitWord =
  LitWord(word: s)

proc newEvalArgWord*(s: string): EvalArgWord =
  EvalArgWord(word: s)

proc newGetArgWord*(s: string): GetArgWord =
  GetArgWord(word: s)

proc newKeyWord*(): KeyWord =
  KeyWord(keys: newSeq[string](), args: newSeq[Node]())

proc newBlok*(nodes: seq[Node]): Blok =
  Blok(nodes: nodes)

proc newBlok*(): Blok =
  Blok(nodes: newSeq[Node]())

proc newParen*(nodes: seq[Node]): Paren =
  Paren(nodes: nodes)

proc newParen*(): Paren =
  Paren(nodes: newSeq[Node]())

proc newCurly*(nodes: seq[Node]): Curly =
  Curly(nodes: nodes)

proc newCurly*(): Curly =
  Curly(nodes: newSeq[Node]())

proc newValue*(v: int): IntVal =
  IntVal(value: v)

proc newValue*(v: float): FloatVal =
  FloatVal(value: v)

proc newValue*(v: string): StringVal =
  StringVal(value: v)

proc newValue*(v: bool): BoolVal =
  if v:
    TrueVal()
  else:
    FalseVal()

proc newNilVal*(): NilVal =
  NilVal()

proc newUndefVal*(): UndefVal =
  UndefVal()

# AST manipulation
proc add*(self: SeqComposite, n: Node) =
  self.nodes.add(n)

proc add*(self: SeqComposite, n: openarray[Node]) =
  self.nodes.add(n)

proc contains*(self: SeqComposite, n: Node): bool =
  self.nodes.contains(n)

method concat*(self: SeqComposite, nodes: seq[Node]): SeqComposite {.base.} =
  raiseRuntimeException("Should not happen..." & $self & " " & $nodes)

method concat*(self: Blok, nodes: seq[Node]): SeqComposite =
  newBlok(self.nodes.concat(nodes))

method concat*(self: Paren, nodes: seq[Node]): SeqComposite =
  newParen(self.nodes.concat(nodes))

method concat*(self: Curly, nodes: seq[Node]): SeqComposite =
  newCurly(self.nodes.concat(nodes))

proc removeLast*(self: SeqComposite) =
  system.delete(self.nodes,self.nodes.high)

# Methods for the base value parsers
method parseValue*(self: ValueParser, s: string): Node {.procvar,base.} =
  nil

method parseValue*(self: IntValueParser, s: string): Node {.procvar.} =
  if (s.len > 0) and (s[0].isDigit or s[0]=='+' or s[0]=='-'):
    try:
      return newValue(parseInt(s))
    except ValueError:
      return nil

method parseValue*(self: FloatValueParser, s: string): Node {.procvar.} =
  if (s.len > 0) and (s[0].isDigit or s[0]=='+' or s[0]=='-'):
    try:
      return newValue(parseFloat(s))
    except ValueError:
      return nil

method parseValue(self: StringValueParser, s: string): Node {.procvar.} =
  # If it ends and starts with '"' then ok
  if s.len > 1 and s[0] == '"' and s[^1] == '"':
    result = newValue(unescape(s))

method prefixLength(self: ValueParser): int {.base.} = 0

method tokenReady(self: ValueParser, token: string, ch: char): string {.base.} =
  ## Return true if self wants to take over parsing a literal
  ## and deciding when its complete. This is used for delimited literals
  ## that can contain whitespace. Otherwise parseValue is needed.
  nil

method tokenStart(self: ValueParser, token: string, ch: char): bool {.base.} =
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


proc len(self: Node): int =
  0

proc len(self: SeqComposite): int =
  self.nodes.len

proc addKey(self: KeyWord, key: string) =
  self.keys.add(key)

proc addArg(self: KeyWord, arg: Node) =
  self.args.add(arg)

proc inBalance(self: KeyWord): bool =
  return self.args.len == self.keys.len

proc produceNodes(self: KeyWord): seq[Node] =
  result = newSeq[Node]()
  result.add(newEvalWord(self.keys.join()))
  result.add(self.args)

template top(self: Parser): Node =
  self.stack[self.stack.high]

proc currentKeyword(self: Parser): KeyWord =
  # If there is a KeyWord on the stack return it, otherwise nil
  if self.top of KeyWord:
    return KeyWord(self.top)
  else:
    return nil

proc closeKeyword(self: Parser)
proc pop(self: Parser) =
  if self.currentKeyword().notNil:
    self.closeKeyword()
  discard self.stack.pop()

proc addNode(self: Parser)
proc closeKeyword(self: Parser) =
  let keyword = self.currentKeyword()
  discard self.stack.pop()
  let nodes = keyword.produceNodes()
  SeqComposite(self.top).removeLast()
  SeqComposite(self.top).add(nodes)

proc doAddNode(self: Parser, node: Node) =
  # If we are collecting a keyword, we get nil until its ready
  let keyword = self.currentKeyword()
  if keyword.isNil:
    # Then we are not parsing a keyword
    SeqComposite(self.top).add(node)
  else:
    if keyword.inBalance():
      self.closeKeyword()
      self.doAddNode(node)
    else:
      keyword.args.add(node)

proc push(self: Parser, n: Node) =
  if not self.stack.isEmpty:
    self.doAddNode(n)
  self.stack.add(n)


proc newWord(self: Parser, token: string): Node =
  let len = token.len
  let first = token[0]

  # All arg words (unique for Ni) are preceded with ":"
  if first == ':' and len > 1:
    if token[1] == '^':
      if token.len < 3:
        raiseParseException("Malformed get argword, missing at least 1 character")
      # Then its a get arg word
      return newGetArgWord(token[2..^1])
    else:
      return newEvalArgWord(token[1..^1])

  # All lookup words are preceded with "^"
  if first == '^' and len > 1:
    if token[1] == '.':
      # Local or parent
      if len > 2:
        if token[2] == '.':
          if len > 3:
            return newGetOuterWord(token[3..^1])
          else:
            raiseParseException("Malformed parent lookup word, missing at least 1 character")
        else:
          return newGetSelfWord(token[2..^1])
      else:
        raiseParseException("Malformed local lookup word, missing at least 1 character")
    else:
      return newGetWord(token[1..^1])

  # All literal words are preceded with "'"
  if first == '\'':
    if len < 2:
      raiseParseException("Malformed literal word, missing at least 1 character")
    else:
      return newLitWord(token[1..^1])

  # All keywords end with ":"
  if len > 1 and token[^1] == ':':
    if self.isNil:
      # We have no parser, this is a call from the interpreter
      return newEvalWord(token)
    else:
      if self.currentKeyword().isNil:
        # Then its the first key we parse, push a KeyWord
        self.push(newKeyWord())
      if self.currentKeyword().inBalance():
        # keys and args balance so far, so we can add a new key
        self.currentKeyword().addKey(token)
      else:
        raiseParseException("Malformed keyword syntax, expecting an argument")
      return nil

  # A regular eval word then, possibly prefixed with . or ..
  if first == '.':
    # Local or parent
    if len > 1:
      if token[1] == '.':
        if len > 2:
          return newEvalOuterWord(token[2..^1])
        else:
          raiseParseException("Malformed parent eval word, missing at least 1 character")
      else:
        return newEvalSelfWord(token[1..^1])
    else:
      raiseParseException("Malformed local eval word, missing at least 1 character")
  else:
    return newEvalWord(token)

template newWord*(token: string): Node =
  newWord(nil, token)

proc newWordOrValue(self: Parser): Node =
  ## Decide what to make, a word or value
  let token = self.token
  self.token = ""

  # Try all valueParsers...
  for p in self.valueParsers:
    let valueOrNil = p.parseValue(token)
    if valueOrNil.notNil:
      return valueOrNil

  # Then it must be a word
  return newWord(self, token)

proc addNode(self: Parser) =
  # If there is a token we figure out what to make of it
  if self.token.len > 0:
    let node = self.newWordOrValue()
    if node.notNil:
      self.doAddNode(node)

proc parse*(self: Parser, str: string): Node =
  var ch: char
  var currentValueParser: ValueParser
  var pos = 0
  self.stack = @[]
  self.token = ""
  # Wrap code in a block and later return last element as result.
  var blok = newBlok()
  self.push(blok)
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
            while (pos < str.len) and (str[pos] != '\l'):
              inc pos
          # Paren
          of '(':
            self.addNode()
            self.push(newParen())
          # Block
          of '[':
            self.addNode()
            self.push(newBlok())
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
          # Just collect for current value parser
          self.token.add(ch)
  self.addNode()
  if self.currentKeyword().notNil:
    self.closeKeyword()
  blok.nodes[^1]


type
  # Ni interpreter
  Interpreter* = ref object
    currentActivation*: Activation  # Execution spaghetti stack
    rootActivation*: RootActivation # The first one
    root*: Map               # Root bindings
    trueVal*: Node
    falseVal*: Node
    undefVal*: Node
    nilVal*: Node

  # Node type to hold Nim primitive procs
  ProcType* = proc(ni: Interpreter): Node
  NimProc* = ref object of Node
    prok*: ProcType
    infix*: bool
    arity*: int

  # An executable Ni function
  Funk* = ref object of Blok
    infix*: bool
    parent*: Activation

  # The activation record used by the Interpreter.
  # This is a so called Spaghetti Stack with only a parent pointer so that they
  # can get garbage collected if not referenced by any other record anymore.
  Activation* = ref object of Node  # It's a Node since we can reflect on it!
    last*: Node                     # Remember for infix
    infixArg*: Node                 # Used to hold the infix arg, if pulled
    returned*: bool                 # Mark return
    parent*: Activation
    pos*: int          # Which node we are at
    body*: SeqComposite   # The composite representing code (Blok, Paren, Funk)

  # We want to distinguish different activations
  BlokActivation* = ref object of Activation
    locals*: Map  # This is where we put named args and locals
  FunkActivation* = ref object of BlokActivation
  ParenActivation* = ref object of Activation
  CurlyActivation* = ref object of BlokActivation
  RootActivation* = ref object of BlokActivation


# Forward declarations to make Nim happy
proc funk*(ni: Interpreter, body: Blok, infix: bool): Node
method eval*(self: Node, ni: Interpreter): Node {.base.}
method evalDo*(self: Node, ni: Interpreter): Node {.base.}

# String representations
method `$`*(self: NimProc): string =
  if self.infix:
    result = "nimi"
  else:
    result = "nim"
  return result & "(" & $self.arity & ")"

method `$`*(self: Funk): string =
  when true:
    if self.infix:
      result = "funci "
    else:
      result = "func "
    return result & "[" & $self.nodes & "]"
  else:
    return "[" & $self.nodes & "]"

method `$`*(self: Activation): string =
  return "activation [" & $self.body & " " & $self.pos & "]"

# Base stuff for accessing

# Indexing Composites
proc `[]`*(self: Map, key: Node): Node =
  if self.bindings.hasKey(key):
    return self.bindings[key].val

proc `[]`*(self: SeqComposite, key: Node): Node =
  self.nodes[IntVal(key).value]

proc `[]`*(self: SeqComposite, key: IntVal): Node =
  self.nodes[key.value]

proc `[]`*(self: SeqComposite, key: int): Node =
  self.nodes[key]

proc `[]=`*(self: Map, key, val: Node) =
  discard self.makeBinding(key, val)

proc `[]=`*(self: SeqComposite, key, val: Node) =
  self.nodes[IntVal(key).value] = val

proc `[]=`*(self: SeqComposite, key: IntVal, val: Node) =
  self.nodes[key.value] = val

proc `[]=`*(self: SeqComposite, key: int, val: Node) =
  self.nodes[key] = val

# Indexing Activaton
proc `[]`*(self: Activation, i: int): Node =
  self.body.nodes[i]

proc len*(self: Activation): int =
  self.body.nodes.len

# Constructor procs
proc newNimProc*(prok: ProcType, infix: bool, arity: int): NimProc =
  NimProc(prok: prok, infix: infix, arity: arity)

proc newFunk*(body: Blok, infix: bool, parent: Activation): Funk =
  Funk(nodes: body.nodes, infix: infix, parent: parent)

proc newRootActivation(root: Map): RootActivation =
  RootActivation(body: newBlok(), locals: root)

proc newActivation*(funk: Funk): FunkActivation =
  FunkActivation(body: funk)

proc newActivation*(body: Blok): Activation =
  BlokActivation(body: body)

proc newActivation*(body: Paren): ParenActivation =
  ParenActivation(body: body)

proc newActivation*(body: Curly): CurlyActivation =
  result = CurlyActivation(body: body)
  result.locals = newMap()

# Stack iterator walking parent refs
iterator stack*(ni: Interpreter): Activation =
  var activation = ni.currentActivation
  while activation.notNil:
    yield activation
    activation = activation.parent

proc getLocals(self: BlokActivation): Map =
  if self.locals.isNil:
    self.locals = newMap()
  self.locals

method hasLocals(self: Activation): bool {.base.} =
  true

method hasLocals(self: ParenActivation): bool =
  false

method outer(self: Activation): Activation {.base.} =
  # Just go caller parent, which works for Paren and Blok since they are
  # not lexical closures.
  self.parent

method outer(self: FunkActivation): Activation =
  # Instead of looking at my parent, which would be the caller
  # we go to the activation where I was created, thus a Funk is a lexical
  # closure.
  Funk(self.body).parent

# Walk maps for lookups and binds. Skips parens since they do not have
# locals and uses outer() that will let Funks go to their "lexical parent"
iterator mapWalk(first: Activation): Activation =
  var activation = first
  while activation.notNil:
    while not activation.hasLocals():
      activation = activation.outer()
    yield activation
    activation = activation.outer()

# Walk activations for pulling arguments, here we strictly use
# parent to walk only up through the caller chain. Skipping paren activations.
iterator callerWalk(first: Activation): Activation =
  var activation = first
  # First skip over immediate paren activations
  while not activation.hasLocals():
    activation = activation.parent
  # Then pick parent
  activation = activation.parent
  # Then we start yielding
  while activation.notNil:
    yield activation
    activation = activation.parent
    # Skip paren activations
    while not activation.hasLocals():
      activation = activation.parent

# Methods supporting the Nim math primitives with coercions
method `+`(a: Node, b: Node): Node {.inline,base.} =
  raiseRuntimeException("Can not evaluate " & $a & " + " & $b)
method `+`(a: IntVal, b: IntVal): Node {.inline.} =
  newValue(a.value + b.value)
method `+`(a: IntVal, b: FloatVal): Node {.inline.} =
  newValue(a.value.float + b.value)
method `+`(a: FloatVal, b: IntVal): Node {.inline.} =
  newValue(a.value + b.value.float)
method `+`(a: FloatVal, b: FloatVal): Node {.inline.} =
  newValue(a.value + b.value)

method `-`(a: Node, b: Node): Node {.inline,base.} =
  raiseRuntimeException("Can not evaluate " & $a & " - " & $b)
method `-`(a: IntVal, b: IntVal): Node {.inline.} =
  newValue(a.value - b.value)
method `-`(a: IntVal, b: FloatVal): Node {.inline.} =
  newValue(a.value.float - b.value)
method `-`(a: FloatVal, b: IntVal): Node {.inline.} =
  newValue(a.value - b.value.float)
method `-`(a: FloatVal, b: FloatVal): Node {.inline.} =
  newValue(a.value - b.value)

method `*`(a: Node, b: Node): Node {.inline,base.} =
  raiseRuntimeException("Can not evaluate " & $a & " * " & $b)
method `*`(a: IntVal, b: IntVal): Node {.inline.} =
  newValue(a.value * b.value)
method `*`(a: IntVal, b: FloatVal): Node {.inline.} =
  newValue(a.value.float * b.value)
method `*`(a: FloatVal, b: IntVal): Node {.inline.} =
  newValue(a.value * b.value.float)
method `*`(a: FloatVal, b: FloatVal): Node {.inline.} =
  newValue(a.value * b.value)

method `/`(a: Node, b: Node): Node {.inline,base.} =
  raiseRuntimeException("Can not evaluate " & $a & " / " & $b)
method `/`(a: IntVal, b: IntVal): Node {.inline.} =
  newValue(a.value / b.value)
method `/`(a: IntVal, b: FloatVal): Node {.inline.} =
  newValue(a.value.float / b.value)
method `/`(a: FloatVal, b: IntVal): Node {.inline.} =
  newValue(a.value / b.value.float)
method `/`(a,b: FloatVal): Node {.inline.} =
  newValue(a.value / b.value)

method `<`(a: Node, b: Node): Node {.inline,base.} =
  raiseRuntimeException("Can not evaluate " & $a & " < " & $b)
method `<`(a: IntVal, b: IntVal): Node {.inline.} =
  newValue(a.value < b.value)
method `<`(a: IntVal, b: FloatVal): Node {.inline.} =
  newValue(a.value.float < b.value)
method `<`(a: FloatVal, b: IntVal): Node {.inline.} =
  newValue(a.value < b.value.float)
method `<`(a,b: FloatVal): Node {.inline.} =
  newValue(a.value < b.value)
method `<`(a,b: StringVal): Node {.inline.} =
  newValue(a.value < b.value)

method `<=`(a: Node, b: Node): Node {.inline,base.} =
  raiseRuntimeException("Can not evaluate " & $a & " <= " & $b)
method `<=`(a: IntVal, b: IntVal): Node {.inline.} =
  newValue(a.value <= b.value)
method `<=`(a: IntVal, b: FloatVal): Node {.inline.} =
  newValue(a.value.float <= b.value)
method `<=`(a: FloatVal, b: IntVal): Node {.inline.} =
  newValue(a.value <= b.value.float)
method `<=`(a,b: FloatVal): Node {.inline.} =
  newValue(a.value <= b.value)
method `<=`(a,b: StringVal): Node {.inline.} =
  newValue(a.value <= b.value)

method `eq`(a: Node, b: Node): Node {.base.} =
  raiseRuntimeException("Can not evaluate " & $a & " == " & $b)
method `eq`(a: IntVal, b: IntVal): Node {.inline.} =
  newValue(a.value == b.value)
method `eq`(a: IntVal, b: FloatVal): Node {.inline.} =
  newValue(a.value.float == b.value)
method `eq`(a: FloatVal, b: IntVal): Node {.inline.} =
  newValue(a.value == b.value.float)
method `eq`(a, b: FloatVal): Node {.inline.} =
  newValue(a.value == b.value)
method `eq`(a, b: StringVal): Node {.inline.} =
  newValue(a.value == b.value)
method `eq`(a, b: BoolVal): Node {.inline.} =
  newValue(a.value == b.value)

method `&`(a: Node, b: Node): Node {.inline,base.} =
  raiseRuntimeException("Can not evaluate " & $a & " & " & $b)
method `&`(a, b: StringVal): Node {.inline.} =
  newValue(a.value & b.value)
method `&`(a, b: SeqComposite): Node {.inline.} =
  a.add(b.nodes)
  return a

# Support procs for eval()
template pushActivation*(ni: Interpreter, activation: Activation) =
  activation.parent = ni.currentActivation
  ni.currentActivation = activation

template popActivation*(ni: Interpreter) =
  ni.currentActivation = ni.currentActivation.parent

proc atEnd*(self: Activation): bool {.inline.} =
  self.pos == self.len

proc next*(self: Activation): Node {.inline.} =
  if self.atEnd:
    raiseRuntimeException("End of current block, too few arguments?")
  else:
    result = self[self.pos]
    inc(self.pos)

method doReturn*(self: Activation, ni: Interpreter) {.base.} =
  ni.currentActivation = self.parent
  if ni.currentActivation.notNil:
    ni.currentActivation.returned = true

method doReturn*(self: FunkActivation, ni: Interpreter) =
  ni.currentActivation = Funk(self.body).parent

method lookup(self: Activation, key: Node): Binding {.base.} =
  # Base implementation needed for dynamic dispatch to work
  nil

method lookup(self: BlokActivation, key: Node): Binding =
  if self.locals.notNil:
    return self.locals.lookup(key)

proc lookup(ni: Interpreter, key: Node): Binding =
  for activation in mapWalk(ni.currentActivation):
    let hit = activation.lookup(key)
    if hit.notNil:
      return hit

proc lookupLocal(ni: Interpreter, key: Node): Binding =
  return ni.currentActivation.lookup(key)

proc lookupParent(ni: Interpreter, key: Node): Binding =
  # Silly way of skipping to get to parent
  var inParent = false
  for activation in mapWalk(ni.currentActivation):
    if inParent:
      return activation.lookup(key)
    else:
      inParent = true

method makeBinding(self: Activation, key: Node, val: Node): Binding {.base.} =
  nil

method makeBinding(self: BlokActivation, key: Node, val: Node): Binding =
  self.getLocals().makeBinding(key, val)

proc makeBinding(ni: Interpreter, key: Node, val: Node): Binding =
  # Bind in first activation with locals
  for activation in mapWalk(ni.currentActivation):
    return activation.makeBinding(key, val)

proc setBinding(ni: Interpreter, key: Node, value: Node): Binding =
  result = ni.lookup(key)
  if result.notNil:
    result.val = value
  else:
    result = ni.makeBinding(key, value)

method infix(self: Node): bool {.base.} =
  false

method infix(self: Funk): bool =
  self.infix

method infix(self: NimProc): bool =
  self.infix

method infix(self: Binding): bool =
  return self.val.infix

proc argParent(ni: Interpreter): Activation =
  # Return first activation up the parent chain that was a caller
  for activation in callerWalk(ni.currentActivation):
    return activation

proc parentArgInfix*(ni: Interpreter): Node =
  ## Pull the parent infix arg
  let act = ni.argParent()
  act.last

proc argInfix*(ni: Interpreter): Node =
  ## Pull the infix arg
  ni.currentActivation.last

proc parentArg*(ni: Interpreter): Node =
  ## Pull next argument from parent activation
  let act = ni.argParent()
  act.next()

proc arg*(ni: Interpreter): Node =
  ## Pull next argument from activation
  ni.currentActivation.next()

template evalArgInfix*(ni: Interpreter): Node =
  ## Pull the infix arg and eval
  ni.currentActivation.last.eval(ni)

proc evalArg*(ni: Interpreter): Node =
  ## Pull next argument from activation and eval
  ni.currentActivation.next().eval(ni)

proc makeWord*(self: Interpreter, word: string, value: Node) =
  discard self.root.makeBinding(newEvalWord(word), value)

proc boolVal(val: bool, ni: Interpreter): Node =
  if val:
    result = ni.trueVal
  else:
    result = ni.falseVal

# A template reducing boilerplate for registering nim primitives
template nimPrim*(name: string, infix: bool, arity: int, body: stmt): stmt {.immediate, dirty.} =
  ni.makeWord(name, newNimProc(
    proc (ni: Interpreter): Node = body, infix, arity))

proc newInterpreter*(): Interpreter =
  let ni = Interpreter(root: newMap())
  result = ni

  # Singletons
  ni.trueVal = newValue(true)
  ni.falseVal = newValue(false)
  ni.nilVal = newNilVal()
  ni.undefVal = newUndefVal()
  ni.makeWord("false", ni.falseVal)
  ni.makeWord("true", ni.trueVal)
  ni.makeWord("undef", ni.undefVal)
  ni.makeWord("nil", ni.nilVal)

  # Reflection words
  # Access to current Activation
  nimPrim("activation", false, 0):
    ni.currentActivation

  # Access to closest scope
  nimPrim("locals", false, 0):
    for activation in mapWalk(ni.currentActivation):
      return BlokActivation(activation).getLocals()

  # Access to closest object
  nimPrim("self", false, 0):
    ni.undefVal

  # Creation of Ni types without literal syntax
  nimPrim("object", false, 1):
    ni.undefVal

  # Tags
  nimPrim("tag:", true, 2):
    result = evalArgInfix(ni)
    let tag = evalArg(ni)
    if result.tags.isNil:
      result.tags = newBlok()
    result.tags.add(tag)
  nimPrim("tag?", true, 2):
    let node = evalArgInfix(ni)
    let tag = evalArg(ni)
    if node.tags.isNil:
      return ni.falseVal
    return boolVal(node.tags.contains(tag), ni)
  nimPrim("tags", true, 1):
    let node = evalArgInfix(ni)
    if node.tags.isNil:
      return ni.falseVal
    return node.tags
  nimPrim("tags:", true, 2):
    result = evalArgInfix(ni)
    result.tags = Blok(evalArg(ni))

  # Lookups
  nimPrim("?", true, 1):
    let val = evalArgInfix(ni)
    newValue(not (val of UndefVal))

  # Assignments
  nimPrim("=", true, 2):
    result = evalArg(ni) # Perhaps we could make it eager here? Pulling in more?
    discard ni.setBinding(argInfix(ni), result)

  # Basic math
  nimPrim("+", true, 2):  evalArgInfix(ni) + evalArg(ni)
  nimPrim("-", true, 2):  evalArgInfix(ni) - evalArg(ni)
  nimPrim("*", true, 2):  evalArgInfix(ni) * evalArg(ni)
  nimPrim("/", true, 2):  evalArgInfix(ni) / evalArg(ni)

  # Comparisons
  nimPrim("<", true, 2):  evalArgInfix(ni) < evalArg(ni)
  nimPrim(">", true, 2):  evalArgInfix(ni) > evalArg(ni)
  nimPrim("<=", true, 2):  evalArgInfix(ni) <= evalArg(ni)
  nimPrim(">=", true, 2):  evalArgInfix(ni) >= evalArg(ni)
  nimPrim("==", true, 2):  eq(evalArgInfix(ni), evalArg(ni))
  nimPrim("!=", true, 2):  newValue(not BoolVal(eq(evalArgInfix(ni), evalArg(ni))).value) #boolVal(evalArgInfix(ni) != evalArg(ni), ni) #newValue(not BoolVal(evalArgInfix(ni) == evalArg(ni)).value)

  # Booleans
  nimPrim("not", false, 1): newValue(not BoolVal(evalArg(ni)).value)
  nimPrim("and", true, 2):
    let arg1 = BoolVal(evalArgInfix(ni)).value
    let arg2 = arg(ni) # We need to make sure we consume this one, since "and" is shortcutting
    newValue(arg1 and BoolVal(arg2.eval(ni)).value)
  nimPrim("or", true, 2):
    let arg1 = BoolVal(evalArgInfix(ni)).value
    let arg2 = arg(ni) # We need to make sure we consume this one, since "or" is shortcutting
    newValue(arg1 or BoolVal(arg2.eval(ni)).value)

  # Concatenation
  nimPrim(",", true, 2):
    let val = evalArgInfix(ni)
    if val of StringVal:
      return val & evalArg(ni)
    elif val of Blok:
      return Blok(val).concat(SeqComposite(evalArg(ni)).nodes)
    elif val of Paren:
      return Paren(val).concat(SeqComposite(evalArg(ni)).nodes)
    elif val of Curly:
      return Curly(val).concat(SeqComposite(evalArg(ni)).nodes)

  # Conversions
  nimPrim("asFloat", true, 1):
    let val = evalArgInfix(ni)
    if val of FloatVal:
      return val
    elif val of IntVal:
      return newValue(toFloat(IntVal(val).value))
    else:
      raiseRuntimeException("Can not convert to float")
  nimPrim("asInt", true, 1):
    let val = evalArgInfix(ni)
    if val of IntVal:
      return val
    elif val of FloatVal:
      return newValue(toInt(FloatVal(val).value))
    else:
      raiseRuntimeException("Can not convert to int")

  # Basic blocks
  # Rebol head/tail collides too much with Lisp IMHO so not sure what to do with
  # those.
  # at: and at:put: in Smalltalk seems to be pick/poke in Rebol.
  # change/at is similar in Rebol but work at current pos.
  # Ni uses at/put instead of pick/poke and read/write instead of change/at

  # Left to think about is peek/poke (Rebol has no peek) and perhaps pick/drop
  # The old C64 Basic had peek/poke for memory at:/at:put: ... :) Otherwise I
  # generally associate peek with lookahead.
  # Idea here: Use xxx? for infix funcs, arity 1, returning booleans
  # ..and xxx! for infix funcs arity 0.
  nimPrim("size", true, 1):
    newValue(SeqComposite(evalArgInfix(ni)).nodes.len)
  nimPrim("at:", true, 2):
    ## Ugly, but I can't get [] to work as methods...
    let comp = evalArgInfix(ni)
    if comp of SeqComposite:
      return SeqComposite(comp)[evalArg(ni)]
    elif comp of Map:
      return Map(comp)[evalArg(ni)]
  nimPrim("at:put:", true, 3):
    let comp = evalArgInfix(ni)
    let key = evalArg(ni)
    let val = evalArg(ni)
    if comp of SeqComposite:
      SeqComposite(comp)[key] = val
    elif comp of Map:
      Map(comp)[key] = val
    return comp
  nimPrim("read", true, 1):
    let comp = SeqComposite(evalArgInfix(ni))
    comp[comp.pos]
  nimPrim("write:", true, 2):
    result = evalArgInfix(ni)
    let comp = SeqComposite(result)
    comp[comp.pos] = evalArg(ni)
  nimPrim("add:", true, 2):
    result = evalArgInfix(ni)
    let comp = SeqComposite(result)
    comp.add(evalArg(ni))
  nimPrim("removeLast", true, 1):
    result = evalArgInfix(ni)
    let comp = SeqComposite(result)
    comp.removeLast()
  nimPrim("contains:", true, 2):
    let comp = SeqComposite(evalArgInfix(ni))
    newValue(comp.contains(evalArg(ni)))

  # Positioning
  nimPrim("reset", true, 1):  SeqComposite(evalArgInfix(ni)).pos = 0 # Called change in Rebol
  nimPrim("pos", true, 1):    newValue(SeqComposite(evalArgInfix(ni)).pos) # ? in Rebol
  nimPrim("pos:", true, 2):    # ? in Rebol
    result = evalArgInfix(ni)
    let comp = SeqComposite(result)
    comp.pos = IntVal(evalArg(ni)).value

  # Streaming
  nimPrim("next", true, 1):
    let comp = SeqComposite(evalArgInfix(ni))
    if comp.pos == comp.nodes.len:
      return ni.undefVal
    result = comp[comp.pos]
    inc(comp.pos)
  nimPrim("prev", true, 1):
    let comp = SeqComposite(evalArgInfix(ni))
    if comp.pos == 0:
      return ni.undefVal
    dec(comp.pos)
    result = comp[comp.pos]
  nimPrim("end?", true, 1):
    let comp = SeqComposite(evalArgInfix(ni))
    newValue(comp.pos == comp.nodes.len)

  # These are like in Rebol/Smalltalk but we use infix like in Smalltalk
  nimPrim("first", true, 1):  SeqComposite(evalArgInfix(ni))[0]
  nimPrim("second", true, 1): SeqComposite(evalArgInfix(ni))[1]
  nimPrim("third", true, 1):  SeqComposite(evalArgInfix(ni))[2]
  nimPrim("fourth", true, 1): SeqComposite(evalArgInfix(ni))[3]
  nimPrim("fifth", true, 1):  SeqComposite(evalArgInfix(ni))[4]
  nimPrim("last", true, 1):
    let nodes = SeqComposite(evalArgInfix(ni)).nodes
    nodes[nodes.high]

  #discard root.makeBinding("bind", newNimProc(primBind, false, 1))
  nimPrim("func", false, 1):    ni.funk(Blok(evalArg(ni)), false)
  nimPrim("funci", false, 1):   ni.funk(Blok(evalArg(ni)), true)
  nimPrim("do", false, 1):      evalArg(ni).evalDo(ni)
  nimPrim("^", false, 1):       arg(ni)
  nimPrim("eva", false, 1):     evalArg(ni)
  nimPrim("eval", false, 1):    evalArg(ni).eval(ni)
  nimPrim("parse", false, 1):   newParser().parse(StringVal(evalArg(ni)).value)

  # serialize & deserialize
  nimPrim("serialize", false, 1):
    newValue($evalArg(ni))
  nimPrim("deserialize", false, 1):
    newParser().parse(StringVal(evalArg(ni)).value)

  # Control structures
  nimPrim("return", false, 1):
    ni.currentActivation.returned = true
    evalArg(ni)
  nimPrim("if", false, 2):
    if BoolVal(evalArg(ni)).value:
      return SeqComposite(evalArg(ni)).evalDo(ni)
    else:
      discard arg(ni) # Consume the block
      return ni.nilVal
  nimPrim("ifelse", false, 3):
    if BoolVal(evalArg(ni)).value:
      let res = SeqComposite(evalArg(ni)).evalDo(ni)
      discard arg(ni) # Consume second block
      return res
    else:
      discard arg(ni) # Consume first block
      return SeqComposite(evalArg(ni)).evalDo(ni)
  nimPrim("timesRepeat:", true, 2):
    let times = IntVal(evalArgInfix(ni)).value
    let fn = SeqComposite(evalArg(ni))
    for i in 1 .. times:
      result = fn.evalDo(ni)
      # Or else non local returns don't work :)
      if ni.currentActivation.returned:
        return
  nimPrim("whileTrue:", true, 2):
    let blk1 = SeqComposite(evalArgInfix(ni))
    let blk2 = SeqComposite(evalArg(ni))
    while BoolVal(blk1.evalDo(ni)).value:
      result = blk2.evalDo(ni)
      # Or else non local returns don't work :)
      if ni.currentActivation.returned:
        return
  nimPrim("whileFalse:", true, 2):
    let blk1 = SeqComposite(evalArgInfix(ni))
    let blk2 = SeqComposite(evalArg(ni))
    while not BoolVal(blk1.evalDo(ni)).value:
      result = blk2.evalDo(ni)
      # Or else non local returns don't work :)
      if ni.currentActivation.returned:
        return

  # This is hard, because evalDo of fn wants to pull its argument from
  # the parent activation, but there is none here. Hmmm.
  #nimPrim("do:", true, 2):
  #  let comp = SeqComposite(evalArgInfix(ni))
  #  let blk = SeqComposite(evalArg(ni))
  #  for node in comp.nodes:
  #    result = blk.evalDo(node, ni)

  # Parallel
  #nimPrim("parallel", true, 1):
  #  let comp = SeqComposite(evalArgInfix(ni))
  #  parallel:
  #    for node in comp.nodes:
  #      let blk = Blok(node)
  #      discard spawn blk.evalDo(ni)

  # Some scripting prims
  nimPrim("quit", false, 1):    quit(IntVal(evalArg(ni)).value)

  # Create and push root activation
  ni.rootActivation = newRootActivation(ni.root)
  ni.pushActivation(ni.rootActivation)

proc atEnd*(ni: Interpreter): bool {.inline.} =
  return ni.currentActivation.atEnd

proc funk*(ni: Interpreter, body: Blok, infix: bool): Node =
  result = newFunk(body, infix, ni.currentActivation)

method canEval*(self: Node, ni: Interpreter):bool {.base.} =
  false

method canEval*(self: EvalWord, ni: Interpreter):bool =
  let binding = ni.lookup(self)
  if binding.isNil:
    return false
  else:
    return binding.val.canEval(ni)

method canEval*(self: Binding, ni: Interpreter):bool =
  return self.val.canEval(ni)

method canEval*(self: Funk, ni: Interpreter):bool =
  true

method canEval*(self: NimProc, ni: Interpreter):bool =
  true

method canEval*(self: EvalArgWord, ni: Interpreter):bool =
  # Since arg words have a side effect they are "actions"
  true

method canEval*(self: GetArgWord, ni: Interpreter):bool =
  # Since arg words have a side effect they are "actions"
  true

method canEval*(self: Paren, ni: Interpreter):bool =
  true

method canEval*(self: Curly, ni: Interpreter):bool =
  true

# The heart of the interpreter - eval
method eval(self: Node, ni: Interpreter): Node =
  raiseRuntimeException("Should not happen")

method eval(self: Word, ni: Interpreter): Node =
  ## Look up
  let binding = ni.lookup(self)
  if binding.isNil:
    raiseRuntimeException("Word not found: " & $self)
  return binding.val.eval(ni)

method eval(self: GetWord, ni: Interpreter): Node =
  ## Look up only
  let hit = ni.lookup(self)
  if hit.isNil: ni.undefVal else: hit.val

method eval(self: GetSelfWord, ni: Interpreter): Node =
  ## Look up only
  let hit = ni.lookupLocal(self)
  if hit.isNil: ni.undefVal else: hit.val

method eval(self: GetOuterWord, ni: Interpreter): Node =
  ## Look up only
  let hit = ni.lookupParent(self)
  if hit.isNil: ni.undefVal else: hit.val

method eval(self: EvalWord, ni: Interpreter): Node =
  ## Look up only
  let hit = ni.lookup(self)
  if hit.isNil: ni.undefVal else: hit.val.eval(ni)

method eval(self: EvalSelfWord, ni: Interpreter): Node =
  ## Look up only
  let hit = ni.lookupLocal(self)
  if hit.isNil: ni.undefVal else: hit.val.eval(ni)

method eval(self: EvalOuterWord, ni: Interpreter): Node =
  ## Look up only
  let hit = ni.lookupParent(self)
  if hit.isNil: ni.undefVal else: hit.val.eval(ni)

method eval(self: LitWord, ni: Interpreter): Node =
  ## Evaluating a LitWord means creating a new word by stripping off \'
  newWord(self.word)

method eval(self: EvalArgWord, ni: Interpreter): Node =
  var arg: Node
  let previousActivation = ni.argParent()
  if ni.currentActivation.body.infix and ni.currentActivation.infixArg.isNil:
    arg = previousActivation.last # arg = parentArgInfix(ni)
    ni.currentActivation.infixArg = arg
  else:
    arg = previousActivation.next() # parentArg(ni)
  # This evaluation needs to be done in parent activation!
  let here = ni.currentActivation
  ni.currentActivation = previousActivation
  let ev = arg.eval(ni)
  ni.currentActivation = here
  discard ni.setBinding(self, ev)
  return ev

method eval(self: GetArgWord, ni: Interpreter): Node =
  var arg: Node
  let previousActivation = ni.argParent()
  if ni.currentActivation.body.infix and ni.currentActivation.infixArg.isNil:
    arg = previousActivation.last # arg = parentArgInfix(ni)
    ni.currentActivation.infixArg = arg
  else:
    arg = previousActivation.next() # parentArg(ni)
  discard ni.setBinding(self, arg)
  return arg

method eval(self: NimProc, ni: Interpreter): Node =
  return self.prok(ni)

proc eval(current: Activation, ni: Interpreter): Node =
  ## This is the inner chamber of the heart :)
  ni.pushActivation(current)
  while not current.atEnd:
    let next = current.next()
    # Then we eval the node if it canEval
    if next.canEval(ni):
      current.last = next.eval(ni)
      if current.returned:
        ni.currentActivation.doReturn(ni)
        return current.last
    else:
      current.last = next
  if current.last of Binding:
    current.last = Binding(current.last).val
  ni.popActivation()
  return current.last

method eval(self: Funk, ni: Interpreter): Node =
  newActivation(self).eval(ni)

method eval(self: Paren, ni: Interpreter): Node =
  newActivation(self).eval(ni)

method eval(self: Curly, ni: Interpreter): Node =
  let activation = newActivation(self)
  discard activation.eval(ni)
  return activation.locals

method evalDo(self: Node, ni: Interpreter): Node =
  raiseRuntimeException("Do only works for sequences")

method evalDo(self: Blok, ni: Interpreter): Node =
  newActivation(self).eval(ni)

method evalDo(self: Paren, ni: Interpreter): Node =
  newActivation(self).eval(ni)

method evalDo(self: Curly, ni: Interpreter): Node =
  # Calling do on a curly doesn't do the locals trick
  newActivation(self).eval(ni)

proc evalRootDo*(self: Blok, ni: Interpreter): Node =
  # Evaluate a node in the root activation
  # Ugly... First pop the root activation
  ni.popActivation()
  # This will push it back and... pop it too
  ni.rootActivation.body = self
  ni.rootActivation.pos = 0
  result = ni.rootActivation.eval(ni)
  # ...so we need to put it back
  ni.pushActivation(ni.rootActivation)

method eval(self: Blok, ni: Interpreter): Node =
  self

method eval(self: Value, ni: Interpreter): Node =
  self

method eval(self: Map, ni: Interpreter): Node =
  self

method eval(self: Binding, ni: Interpreter): Node =
  self.val

proc eval*(ni: Interpreter, code: string): Node =
  ## Evaluate code in a new activation
  SeqComposite(newParser().parse(code)).evalDo(ni)

proc evalRoot*(ni: Interpreter, code: string): Node =
  ## Evaluate code in the root activation, presume it is a block
  Blok(newParser().parse(code)).evalRootDo(ni)



when isMainModule and not defined(js):
  # Just run a given file as argument, the hash-bang trick works also
  import os
  let fn = commandLineParams()[0]
  let code = readFile(fn)
  discard newInterpreter().eval("[" & code & "]")




