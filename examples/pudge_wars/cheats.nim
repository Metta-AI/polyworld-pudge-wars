## Warcraft 3-style typed cheat codes.
##
## Type the letters while playing — no console, no Enter. The human
## seat accumulates keystrokes; a matching suffix fires the effect.
## Sim-mutating codes go through `IntentCheat` / `ActionCheat` so
## live play, the tape, and the network stay hash-exact. Map reveal
## (`iseedeadpeople`) is local presentation, like fog itself.

import std/strutils

type
  CheatKind* = enum
    CheatGreed
      ## greedisgood: gold plus maxed shop permanents.
    CheatGold
      ## keysersoze: gold only.
    CheatGoods
      ## leafittome: maxed shop permanents (the lumber analog).
    CheatGod
      ## whosyourdaddy: toggle immunity and one-shot hits.
    CheatMana
      ## thereisnospoon / warpten: toggle ability cooldowns off.
    CheatCool
      ## thedudeabides: reset cooldowns once.
    CheatPower
      ## ihavethepower: max hook upgrades and a full heal.
    CheatWin
      ## allyourbasearebelongtous: your team hits the kill goal.
    CheatLose
      ## somebodysetupusthebomb: the other team hits the kill goal.

  CheatMatch* = object
    found*: bool
    kind*: CheatKind
    reveal*: bool
      ## True for `iseedeadpeople`: client fog, not a sim action.

const
  CheatGoldAmount* = 500'i32
    ## Default purse for greedisgood / keysersoze. WC3's gold grant.
  CheatFlagGod* = 1'i32
  CheatFlagMana* = 2'i32
  CheatBufferCap* = 32

  # Longest first so a short code cannot steal a longer suffix.
  CheatTable = [
    ("allyourbasearebelongtous", CheatWin, false),
    ("somebodysetupusthebomb", CheatLose, false),
    ("thereisnospoon", CheatMana, false),
    ("iseedeadpeople", CheatGreed, true),
    ("whosyourdaddy", CheatGod, false),
    ("thedudeabides", CheatCool, false),
    ("ihavethepower", CheatPower, false),
    ("greedisgood", CheatGreed, false),
    ("keysersoze", CheatGold, false),
    ("leafittome", CheatGoods, false),
    ("warpten", CheatMana, false)
  ]

proc matchCheatBuffer*(buffer: string): CheatMatch =
  ## Returns the first (longest) WC3-style code that is a suffix of
  ## `buffer`. Empty when nothing matches.
  for entry in CheatTable:
    if buffer.endsWith(entry[0]):
      return CheatMatch(
        found: true, kind: entry[1], reveal: entry[2]
      )

proc validCheatKind*(kindId: int32): bool =
  kindId >= int32(CheatKind.low.ord) and kindId <= int32(CheatKind.high.ord)
