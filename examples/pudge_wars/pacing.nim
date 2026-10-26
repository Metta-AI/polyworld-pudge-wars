## Wall-clock pacing only. Physics, cooldowns and replay hashes stay at 32 Hz.
import content

const HumanTickRate* = TickRate
  ## Humans and bots share the full 32-tick wall clock.

proc wallTickRate*(humanPaced: bool): int32 =
  if humanPaced: HumanTickRate else: TickRate

proc wallTickNanoseconds*(humanPaced: bool): int64 =
  1_000_000_000'i64 div int64(wallTickRate(humanPaced))
