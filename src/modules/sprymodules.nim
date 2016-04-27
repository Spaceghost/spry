import spryvm

# Spry Modules module
proc addModules*(spry: Interpreter) =
  # Modules Spry support code
  discard spry.evalRoot """[
    # Load a Module from a string
    loadString: = func [:code
      map = eval deserialize code
      loadMap: map as: ((map at: '_meta) at: 'name)
    ]

    loadString:as: = func [:code :name
      loadMap: eval deserialize code as: name
    ]

    loadFile: = func [loadString: readFile :fileName]

    loadFile:as: = func [loadString: readFile :fileName as: :name]

    loadMap:as: = func [:map :name
      root at: name put: map
      true
    ]

    existsFile "spry.spry" if: [
      echo "Loading spry.sy ..."
      loadFile: "spry.sy"
    ]
  ]"""

