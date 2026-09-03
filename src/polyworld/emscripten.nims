## Shared Emscripten compile recipe for Polyworld games.

import
  std/[os, strformat, strutils]

proc setupEmscripten*(exampleDir: string) =
  ## Configures the wasm backend and writes the bundle next to the game.
  when defined(emscripten):
    let
      repoDir = exampleDir / ".." / ".."
      bundledData = repoDir / "polyworld_data"
      siblingData = repoDir / ".." / "polyworld_data"
      dataDir =
        if dirExists(bundledData): bundledData
        else: siblingData
      outputDir = exampleDir / "emscripten"
      defaultShell = repoDir / "src" / "polyworld" / "emscripten.html"
      gameShell = exampleDir / "webshell.html"
      # A game may brand its own loading page.
      shellFile = if fileExists(gameShell): gameShell else: defaultShell
      manifestFile = exampleDir / "webdata.txt"
    # A game that lists its assets ships a small bundle; without a
    # manifest the whole data folder is packed.
    var preloads = ""
    if fileExists(manifestFile):
      for line in readFile(manifestFile).splitLines():
        let entry = line.strip()
        if entry.len == 0 or entry.startsWith("#"):
          continue
        preloads.add(
          &" --preload-file {dataDir / entry}@/polyworld_data/{entry}"
        )
    else:
      preloads = &" --preload-file {dataDir}@/polyworld_data"
    if not dirExists(outputDir):
      mkDir(outputDir)
    switch("nimcache", outputDir / "tmp")
    switch("threads", "off")
    --os:linux
    --cpu:wasm32
    --cc:clang
    when defined(windows):
      --clang.exe:emcc.bat
      --clang.linkerexe:emcc.bat
      --clang.cpp.exe:emcc.bat
      --clang.cpp.linkerexe:emcc.bat
    else:
      --clang.exe:emcc
      --clang.linkerexe:emcc
      --clang.cpp.exe:emcc
      --clang.cpp.linkerexe:emcc
    --listCmd
    --gc:arc
    --exceptions:goto
    --define:noSignalHandler
    --debugger:native
    --define:noAutoGLerrorCheck
    --define:flatty64
    when not defined(debug):
      --define:release
    switch(
      "passL",
      (&"""
      -o {outputDir / projectName()}.html
      {preloads}
      --pre-js {repoDir / "src" / "polyworld" / "webinputs.js"}
      --shell-file {shellFile}
      -s ASYNCIFY
      -s FETCH
      -s USE_WEBGL2=1
      -s MAX_WEBGL_VERSION=2
      -s MIN_WEBGL_VERSION=1
      -s FULL_ES3=1
      -s GL_ENABLE_GET_PROC_ADDRESS=1
      -s ALLOW_MEMORY_GROWTH
      --profiling
      """).replace("\n", " ")
    )
    if paramStr(1) == "run" or paramStr(1) == "r":
      setCommand("c")
      echo "To run the Emscripten build, use:"
      echo "emrun " & outputDir / (projectName() & ".html")
