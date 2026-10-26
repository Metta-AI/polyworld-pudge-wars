## Wall-clock pacing only. Physics, cooldowns and replay hashes stay at 32 Hz.
import content

const HumanTickRate* = 28'i32
  ## 87.5% speed gives humans about 14% more reaction time. Bots in the same match
  ## share this clock; policy-only evaluation keeps its existing speed.

proc wallTickRate*(humanPaced: bool): int32 =
  if humanPaced: HumanTickRate else: TickRate

proc wallTickNanoseconds*(humanPaced: bool): int64 =
  1_000_000_000'i64 div int64(wallTickRate(humanPaced))
