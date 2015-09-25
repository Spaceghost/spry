import ni, niparser, niextend

# Some helpers for tests below
proc show(code: string): string =
  result = $newParser().parse(code)
  echo("RESULT:" & $result)
  echo("---------------------")
proc run(code: string): string =
  result = $newInterpreter().eval(code)
  echo("RESULT:" & result)
  echo("---------------------")


# A bunch of tests for Parser
when true:
  # The different kinds of words
  assert(show("one") == "[one]")        # Eval word  
  assert(show(".one") == "[.one]")      # Eval word, only resolve locally
  assert(show("..one") == "[..one]")    # Eval word, start resolve in parent
  assert(show("^one") == "[^one]")      # Lookup word
  assert(show("^.one") == "[^.one]")    # Lookup word, only resolve locally
  assert(show("^..one") == "[^..one]")  # Lookup word, start resolve in parent
  assert(show(":one") == "[:one]")      # Arg word, pulls in from caller
  assert(show(":'one") == "[:'one]")    # Arg word, pulls in without eval
  assert(show("'one") == "['one]")      # Literal word
  assert(show("a at: 1 put: 2") == "[a at:put: 1 2]")  # Keyword syntactic sugar
  
  assert(show("""
red
green
blue""") == "[red green blue]")

  # The most trivial datatype, integer!
  assert(show("11") == "[11]")
  assert(show("+11") == "[11]")
  assert(show("-11") == "[-11]")

  # String
  assert(show("\"garf\"") == "[\"garf\"]")
  
  # Just nesting and mixing
  assert(show("one :two") == "[one :two]")
  assert(show("[]") == "[[]]")
  assert(show("()") == "[()]")
  assert(show("{}") == "[{}]")
  assert(show("one two [three]") == "[one two [three]]")
  assert(show("one (two) {four [three] five}") == "[one (two) {four [three] five}]")
  assert(show(":one [:two ['three]]") == "[:one [:two ['three]]]")    
  assert(show(":one [123 -4['three]+5]") == "[:one [123 -4 ['three] 5]]")
  
  # Keyword syntax sugar
  assert(show("[1 2] at: 0 put: 1") == "[[1 2] at:put: 0 1]")
  assert(show("4 timesRepeat: [echo 34]") == "[4 timesRepeat: [echo 34]]")
  assert(show("[3 < 4] whileTrue: [5 timesRepeat: [echo 42]]") == "[[3 < 4] whileTrue: [5 timesRepeat: [echo 42]]]")
  assert(show("[3 4] at: [1 2 [hey]] put: [5 timesRepeat: [echo 42]]") == "[[3 4] at:put: [1 2 [hey]] [5 timesRepeat: [echo 42]]]")


  assert(show(">") == "[>]")
  assert(show("10.30") == "[10.3]")
    
  # A real Rebol code sample, but with assignment words replaced with "=" assignment
  assert(show("""loop 10 [print "hello"]

if time > 10:30 [send jim news]

sites = [
    http://www.rebol.com [save %reb.html data]
    http://www.cnn.com   [print data]
    ftp://www.amiga.com  [send cs@org.foo data]
]

foreach [site action] sites [
    data = read site
    do action
]""") == """[loop 10 [print "hello"] if time > 10:30 [send jim news] sites = [http://www.rebol.com [save %reb.html data] http://www.cnn.com [print data] ftp://www.amiga.com [send cs@org.foo data]] foreach [site action] sites [data = read site do action]]""")

# Tests for Interpreter
when true:
  # Parse properly, show renders the Node tree
  assert(show("3 + 4") == "[3 + 4]")
  # And run
  assert(run("3 + 4") == "7")

  # A block is just a block, no evaluation
  assert(show("[3 + 4]") == "[[3 + 4]]")

  # But we can use do to evaluate it
  assert(show("do [3 + 4]") == "[do [3 + 4]]")
  assert(run("do [4 + 3]") == "7")
  
  # But we need to use func to make a closure from it
  assert(run("func [3 + 4]") == "[3 + 4]")
  # Which will evaluate
  assert(run("do func [3 + 4]") == "7")
  
  # Assignment is a prim
  assert(run("x = 5") == "5")
  assert(run("x = 5 x") == "x") # Peculiarity, a word is not evaluated by default
  assert(run("x = 5 eval x") == "5") # But we can eval it
  assert(run("f = func [3 + 4] f") == "7") # Functions are evaluated though
  
  # Nil vs undef
  assert(run("eval x") == "undef")
  assert(run("x = 5 x = undef eval x") == "undef")
  assert(run("x = 5 x = nil eval x") == "nil")
  
  # Precedence and basic math
  assert(run("3 * 4") == "12")
  assert(run("3 + 1.5") == "4.5")
  assert(run("5 - 3 + 1") == "3") # Left to right
  assert(run("3 + 4 * 2") == "14") # Yeah
  assert(run("3 + (4 * 2)") == "11") # Thank god
  assert(run("3 / 2") == "1.5") # Goes to float
  assert(run("3 / 2 * 1.2") == "1.8") # 
  assert(run("3 + 3 * 1.5") == "9.0") # Goes to float
  
  # And we can nest also, since a block has its own Activation
  # Note that only last result of block is used so "1 + 7" is dead code
  assert(run("5 + do [3 + do [1 + 7 1 + 9]]") == "18")

  # Strings
  assert(run("\"ab[c\"") == "\"ab[c\"")
  assert(run("\"ab\" & \"cd\"") == "\"abcd\"")

  # Set and get variables
  assert(run("x = 4 5 + x") == "9")
  assert(run("x = 1 x = x eval x") == "1")
  assert(run("x = 4 return x") == "4")  
  assert(run("x = 1 x = (x + 2) eval x") == "3")
  assert(run("x = 4 k = do [y = (x + 3) eval y] k + x") == "11")
  assert(run("x = 1 do [x = (x + 1)] eval x") == "2")

  # Use parse word
  assert(run("parse \"3 + 4\"") == "[3 + 4]")
  assert(run("do parse \"3 + 4\"") == "7")

  # Boolean
  assert(run("true") == "true")
  assert(run("not true") == "false")
  assert(run("false") == "false")
  assert(run("not false") == "true")
  assert(run("3 < 4") == "true")
  assert(run("3 > 4") == "false")
  assert(run("not (3 > 4)") == "true")
  assert(run("false or false") == "false")
  assert(run("true or false") == "true")
  assert(run("false or true") == "true")
  assert(run("true or true") == "true")
  assert(run("false and false") == "false")
  assert(run("true and false") == "false")
  assert(run("false and true") == "false")
  assert(run("true and true") == "true")
  assert(run("3 > 4 or (3 < 4)") == "true")
  assert(run("3 > 4 and (3 < 4)") == "false")
  assert(run("7 > 4 and (3 < 4)") == "true")
  assert(run("7 >= 4") == "true")
  assert(run("4 >= 4") == "true")
  assert(run("3 >= 4") == "false")
  assert(run("7 <= 4") == "false")
  assert(run("4 <= 4") == "true")
  assert(run("3 <= 4") == "true")
  assert(run("3 == 4") == "false")
  assert(run("4 == 4") == "true")
  assert(run("3.0 == 4.0") == "false")
  assert(run("4 == 4.0") == "true")
  assert(run("4.0 == 4") == "true")
  assert(run("4.0 != 4") == "false")
  assert(run("4.1 != 4") == "true")
  assert(run("\"abc\" == \"abc\"") == "true")
  assert(run("\"abc\" == \"AAA\"") == "false")
  assert(run("true == true") == "true")
  assert(run("false == true") == "false")
  

  # Block indexing and positioning
  assert(run("[3 4] len") == "2")
  assert(run("[] len") == "0")
  assert(run("[3 4] first") == "3")
  assert(run("[3 4] second") == "4")
  assert(run("[3 4] last") == "4")
  assert(run("[3 4] at: 0") == "3")
  assert(run("[3 4] at: 1") == "4")
  assert(run("[3 4] at: 1") == "4")
  assert(run("[3 4] at: 0 put: 5") == "[5 4]")
  assert(run("x = [3 4] x at: 1 put: 5 eval x") == "[3 5]")
  assert(run("x = [3 4] x read") == "3")
  assert(run("x = [3 4] x pos: 1 x read") == "4")
  assert(run("x = [3 4] x pos: 1 x reset x read") == "3")
  assert(run("x = [3 4] x next") == "3")
  assert(run("x = [3 4] x next x next") == "4")
  assert(run("x = [3 4] x next x end?") == "false")
  assert(run("x = [3 4] x next x next x end?") == "true")
  assert(run("x = [3 4] x next x next x next") == "undef")
  assert(run("x = [3 4] x next x next x prev") == "4")  
  assert(run("x = [3 4] x next x next x prev x prev") == "3")  
  assert(run("x = [3 4] x pos") == "0")
  assert(run("x = [3 4] x next x pos") == "1")
  assert(run("x = [3 4] x write: 5") == "[5 4]")
  assert(run("x = [3 4] x add: 5 eval x") == "[3 4 5]")
  assert(run("x = [3 4] x removeLast eval x") == "[3]")
  assert(run("[3 4] & [5 6]") == "[3 4 5 6]")

  # Data as code
  assert(run("code = [1 + 2 + 3] code at: 2 put: 10 do code") == "14")
  
  # if and ifelse and echo
  assert(run("x = true if x [true]") == "true")
  assert(run("x = true if x [12]") == "12")
  assert(run("if false [12]") == "nil")
  assert(run("x = false if x [true]") == "nil")
  assert(run("if (3 < 4) [\"yay\"]") == "\"yay\"")
  assert(run("if (3 > 4) [\"yay\"]") == "nil")
  assert(run("ifelse (3 > 4) [\"yay\"] ['ok]") == "'ok")
  assert(run("ifelse (3 > 4) [true] [false]") == "false")
  assert(run("ifelse (4 > 3) [true] [false]") == "true")
  
  # loops
  assert(run("x = 0 5 timesRepeat: [x = (x + 1)] eval x") == "5")
  assert(run("x = 0 0 timesRepeat: [x = (x + 1)] eval x") == "0")
  assert(run("x = 0 5 timesRepeat: [x = (x + 1)] eval x") == "5")
  assert(run("x = 0 [x > 5] whileFalse: [x = (x + 1)] eval x") == "6")
  assert(run("x = 10 [x > 5] whileTrue: [x = (x - 1)] eval x") == "5")
  
  # func
  assert(run("z = func [3 + 4] z") == "7")
  assert(run("x = func [3 + 4] eval ^x") == "[3 + 4]")
  assert(run("x = func [3 + 4] 'x") == "'x")
  assert(run("x = func [3 + 4] ^x write: 5 x") == "9")
  assert(run("x = func [3 + 4 return 1 8 + 9] x") == "1")
  # Its a non local return so it returns all the way, thus it works deep down
  assert(run("x = func [3 + 4 do [ 2 + 3 return 1 1 + 1] 8 + 9] x") == "1")
  
  # func args
  assert(run("do [:a] 5") == "5")
  assert(run("x = func [:a a + 1] x 5") == "6")
  assert(run("x = func [:a + 1] x 5") == "6") # Slicker than the above!
  assert(run("x = func [:a :b eval b] x 5 4") == "4")
  assert(run("x = func [:a :b a + b] x 5 4") == "9")
  assert(run("x = func [:a + :b] x 5 4") == "9") # Again, slicker
  assert(run("z = 15 x = func [:a :b a + b + z] x 1 2") == "18")
  assert(run("z = 15 x = func [:a + :b + z] x 1 2") == "18") # Slick indeed
  assert(run("do [:b + 3] 4") == "7") # Muhahaha!
  assert(run("do [:b + :c - 1] 4 3") == "6") # Muhahaha!
  assert(run("d = 5 do [:x] d") == "5")
  assert(run("d = 5 do [:^x] d") == "d")
  # x will be a Word, need val and key prims to access it!
  #assert(run("a = \"ab\" do [:'x & \"c\"] a") == "\"ac\"") # x becomes "a"
  assert(run("a = \"ab\" do [:x & \"c\"] a") == "\"abc\"") # x becomes "ab"

  # . and ..
  assert(run("d = 5 do [eval ^d]") == "5")
  assert(run("d = 5 do [eval ^.d]") == "undef")
  assert(run("d = 5 do [eval ^..d]") == "5")
  assert(run("d = 5 do [eval d]") == "5")
  assert(run("d = 5 do [eval .d]") == "undef")
  assert(run("d = 5 do [eval ..d]") == "5")
  # Scoped assignment doesn't work yet
  #assert(run("d = 5 do [ .d = 3 ..d + .d]") == "8")
  #assert(run("d = 5 do [ d = 3 ..d + d]") == "6")
  #assert(run("d = 5 do [ ..d = 3 ..d + d]") == "6")

  # func infix works too, and with 3 or more arguments too...
  assert(run("xx = func [:a :b a + b + b] xx 2 (xx 5 4)") == "28") # 2 + (5+4+4) + (5+4+4)
  assert(run("xx = funci [:a :b a + b] 5 xx 2") == "7") # 5 + 7
  assert(run("xx = funci [:a + :b] 5 xx 2") == "7") # 5 + 7
  assert(run("xx = funci [:a :b a + b + b] 5 xx (4 xx 2)") == "21") # 5 + (4+2+2) + (4+2+2)
  assert(run("xx = funci [:a + :b + b] (5 xx 4) xx 2") == "17") # 5+4+4 + 2+2
  assert(run("pick2add = funci [:block :b :c block at: b + (block at: c)] [1 2 3] pick2add 0 2") == "4") # 1+3
  assert(run("pick2add = funci [:block at: :b + (block at: :c)] [1 2 3] pick2add 0 2") == "4") # 1+3
  
  # Variadic and dynamic args
  # Does not work since there is a semantic glitch - who is the argParent?
  #assert(run("sum = 0 sum-until-zero = func [[:a > 0] whileTrue: [sum = sum + a]] (sum-until-zero 1 2 3 0 4 4)") == "6")
  # This func does not pull second arg if first is < 0.
  assert(run("add = func [ if (:a < 0) [return nil] return (a + :b) ] add -4 3") == "3")
  assert(run("add = func [ if (:a < 0) [return nil] return (a + :b) ] add 1 3") == "4")
  
  # Macros, they need to be able to return multipe nodes...
  assert(run("z = 5 foo = func [:^a return func [a + 10]] fupp = foo z z = 3 fupp") == "13")
  
  # func closures. Creates two different funcs closing over two values of a
  assert(run("c = func [:a func [a + :b]] d = (c 2) e = (c 3) (d 1 + e 1)") == "7") # 3 + 4
  
  # Ok, but now we can do arguments so...
  assert(run("""
  factorial = func [ifelse (:n > 0) [n * factorial (n - 1)] [1]]
  factorial 12
  """) == "479001600")

  # Implement simple for loop
  assert(run("""
  for = func [:n :m :blk
    x = n
    [x <= m] whileTrue: [
      do blk x
      x = (x + 1)]]
  r = 0
  for 2 5 [r = (r + :i)]
  eval r
  """) == "14")
  
  # Implementing Smalltalk do: in Ni
  assert(run("""
  do: = funci [:blk :fun
    blk reset
    [blk end?] whileFalse: [do fun (blk next)]
  ]
  r = 0 y = [1 2 3]
  y do: [r = (r + :e)]
  eval r""") == "6")
  
  # Implementing detect:, note that we use the internal streaming of blocks
  # so we need to do call reset first. Also note the use of return which
  # is a non local return in Smalltalk style, so it will return from the
  # whole func.
  assert(run("""
  detect: = funci [:blk :pred
    blk reset
    [blk end?] whileFalse: [
      n = (blk next)
      if do pred n [return n]]
    return nil
  ]
  [1 2 3 4] detect: [:each > 2]
  """) == "3")

  # Implementing select:
  assert(run("""
  select: = funci [:blk :pred
    result = []
    blk reset
    [blk end?] whileFalse: [
      n = (blk next)
      if do pred n [result add: n]]
    return result
  ]
  [1 2 3 4] select: [:each > 2]
  """) == "[3 4]")
    

when true:
  # Demonstrate extension from extend.nim
  assert(show("'''abc'''") == "[\"abc\"]")
  assert(run("reduce [1 + 2 3 + 4]") == "[3 7]")  
  



