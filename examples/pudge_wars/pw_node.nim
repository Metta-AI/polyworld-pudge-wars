## Headless wasm32 harness: runs the exact sim + replay verifier under
## Node so native and WASM determinism can be diffed without a browser.
## Build: nim c -d:emscripten -d:headless examples/pudge_wars/pw_node.nim

import game

runHeadless()
