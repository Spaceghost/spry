
import spryvm, modules/sprycore, modules/sprylib, modules/spryextend, modules/spryos, modules/spryio,
 modules/spryoo, modules/sprydebug, modules/sprystring, modules/sprymodules, modules/spryreflect,
 modules/spryblock, modules/spryui

var spry = newInterpreter()

# Add extra modules
spry.addCore()
spry.addExtend()
spry.addOS()
spry.addIO()
spry.addOO()
spry.addDebug()
spry.addString()
spry.addModules()
spry.addReflect()
spry.addBlock()
spry.addLib()
spry.addUI()

discard spry.eval("""[
#!/usr/bin/env spry

# A sample Spry application that is a trivial file editor

# First we need to initialize libui
uiInit

# Variable holding file contents
content = ""

# Variable holding last path
path = ""

# File handling funcs
openContent = func [
  ..path = (win openFile)
  content = readFile path
  contentEntry text: content
]
saveContent = func [:path
  content = (contentEntry text)
  writeFile path content
]

# Build menu
menu = newMenu "File"
menu onShouldQuit: [do closeHandler]

item = (menu menuAppendItem: "Open ...")
item onMenuItemClicked: [openContent]

item = (menu menuAppendItem: "Save as ...")
item onMenuItemClicked: [
  ..path = (win saveFile)
  saveContent path
]

item = (menu menuAppendQuitItem)

helpMenu = newMenu "Help"
item = (helpMenu menuAppendItem: "Help")
item onMenuItemClicked: [
  win message: "Sorry..." title: "No help to get"
]

helpMenu menuAppendAboutItem

# Create a new Window
win = newWindow "Braindead editor" 640 400 true
win windowMargin: 1

# Create a multiline text entry field for content
contentEntry = newMultilineEntryText

# And a vertical box to put stuff in
layout = newVerticalBox
buttons = newHorizontalBox

# Some buttons and their handlers
saveit = newButton "Save"
saveit onClicked: [
  echo ("PATH:", path)
  saveContent path
]

clearit = newButton "Clear"
clearit onClicked: [contentEntry text: ""]

quitit = newButton "Quit"
quitit onClicked: [do closeHandler]

# Put things in the boxes
layout padding: 1
layout append: contentEntry stretch: 1
layout append: buttons stretch: 0
buttons append: saveit stretch: 0
buttons append: clearit stretch: 0
buttons append: quitit stretch: 0

# Add box to window
win windowSetChild: layout

# Set initial text
contentEntry text: content

# Close handler
closeHandler = [
  win message: "Bye bye" title: "Braindead editor"
  controlDestroy win
  uiQuit
]

# Set a handler on closing window
win onClosing: closeHandler

# Show the window
win show

# Enter libui's event loop
win uiMain]""")
