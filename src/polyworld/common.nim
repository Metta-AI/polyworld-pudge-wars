## Shared paths and constants for Polyworld.
## Native games load assets from `./polyworld_data` when that folder is in
## the repo, otherwise from the historical sibling `../polyworld_data`.
## Wasm packs that folder at /polyworld_data.

import std/os

const
  DataRoot* =
    when defined(emscripten):
      "/polyworld_data"
    elif dirExists("polyworld_data"):
      "polyworld_data"
    else:
      "../polyworld_data"
