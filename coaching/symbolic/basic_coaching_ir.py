"""Small, fail-closed text IR <-> BASIC projection for the first coaching lesson.

This recognizes ONE policy family, not arbitrary BASIC. Reverse extraction checks
every executable line; comments cannot attest behavior. Intent/provenance cannot
be inferred from code and remain in the authored IR / evidence ledger.
"""
from __future__ import annotations
import argparse
from dataclasses import dataclass
from pathlib import Path
import re


@dataclass(frozen=True)
class Lesson:
    melee_radius: int = 8
    hook_range: int = 60
    hook_during_melee: bool = True
    idle: str = "hold"
    bank_margin: int = 2
    ranged_movement: str = "hold"
    patrol_radius: int = 10
    waypoint_timeout_ticks: int = 128
    preserve_pull: bool = False

    def validate(self):
        if not (6 <= self.melee_radius <= 12 and 1 <= self.hook_range <= 60):
            raise ValueError("Invalid engagement range")
        if self.idle not in ("hold", "probe_lane") or not 1 <= self.bank_margin <= 8:
            raise ValueError("Unsupported idle behavior / bank margin")
        if type(self.hook_during_melee) is not bool:
            raise ValueError("hook_during_melee must be a boolean")
        if self.ranged_movement not in ("hold", "patrol"):
            raise ValueError("Unsupported ranged movement")
        if not 4 <= self.patrol_radius <= 14 or not 32 <= self.waypoint_timeout_ticks <= 256:
            raise ValueError("Invalid patrol bounds")
        if self.ranged_movement == "patrol" and self.idle != "probe_lane":
            raise ValueError("Patrol requires lane exploration")
        if self.ranged_movement == "patrol" and self.hook_range < self.melee_radius:
            raise ValueError("Patrol's committed melee hooks require hook range to cover acquisition")
        if self.ranged_movement == "hold" and (self.patrol_radius != 10 or self.waypoint_timeout_ticks != 128):
            raise ValueError("Inactive patrol settings must retain defaults")
        if type(self.preserve_pull) is not bool or (self.ranged_movement == "hold" and self.preserve_pull):
            raise ValueError("Pull commitment requires patrol")
        return self


def parse(text: str) -> Lesson:
    blocks = re.findall(r"```pudge-coaching\n(.*?)\n```", text, re.S)
    if len(blocks) != 1:
        raise ValueError("Expected exactly one pudge-coaching block")
    entries = [line.split(" = ", 1) for line in blocks[0].splitlines()]
    if any(len(e) != 2 for e in entries):
        raise ValueError("Expected key = value")
    values = dict(entries)
    legacy = {"melee_radius", "hook_range", "hook_during_melee", "idle", "bank_margin"}
    mobility_v1 = set(Lesson.__dataclass_fields__) - {"preserve_pull"}
    if len(values) != len(entries) or set(values) not in (legacy, mobility_v1, set(Lesson.__dataclass_fields__)):
        raise ValueError("Missing, repeated, or unknown semantic field")
    if values["hook_during_melee"] not in ("true", "false"):
        raise ValueError("Expected true / false")
    if values.get("preserve_pull", "false") not in ("true", "false"):
        raise ValueError("Expected true / false for preserve_pull")
    return Lesson(int(values["melee_radius"]), int(values["hook_range"]),
                  values["hook_during_melee"] == "true", values["idle"],
                  int(values["bank_margin"]), values.get("ranged_movement", "hold"),
                  int(values.get("patrol_radius", 10)),
                  int(values.get("waypoint_timeout_ticks", 128)),
                  values.get("preserve_pull", "false") == "true").validate()


def block(lesson: Lesson) -> str:
    lesson.validate()
    return "```pudge-coaching\n" + "\n".join(
        f"{key} = {str(value).lower() if isinstance(value, bool) else value}"
        for key, value in vars(lesson).items()) + "\n```\n"


def generate(lesson: Lesson) -> str:
    lesson.validate()
    code = f"""' Generated from the coaching IR. Engine performs sustained melee after attackTarget.
' Holding and hooking are independent of melee selection; no economy or learned opponent model.
meleeRadius = {lesson.melee_radius}
hookRange = {lesson.hook_range}
hookDuringMelee = {int(lesson.hook_during_melee)}
probeLane = {int(lesson.idle == 'probe_lane')}
bankMargin = {lesson.bank_margin}

if selfHp <= 0 or selfHooked = 1 then
  end
end if
best = -1
bestD2 = 2147483647
i = 0
while i < objectCount()
  if objectKind(i) = 1 and objectTeam(i) <> selfTeam then
    if objectAlive(i) = 1 and objectShielded(i) = 0 then
      dx = objectX(i) - selfX
      dy = objectY(i) - selfY
      d2 = dx * dx + dy * dy
      if d2 < bestD2 then
        best = i
        bestD2 = d2
      end if
    end if
  end if
  i = i + 1
wend

melee = 0
if best >= 0 then
  if objectLayer(best) = selfLayer and selfLayer <> 2 then
    if bestD2 <= meleeRadius * meleeRadius and objectHooked(best) = 0 then
      melee = attackTarget(objectId(best))
    end if
  end if
end if

if melee = 0 then
  halt()
end if
if best >= 0 then
  if bestD2 <= hookRange * hookRange then
    if hookReady = 1 and (melee = 0 or hookDuringMelee = 1) then
      safeHookTo(objectX(best), objectY(best))
    end if
    end
  end if
end if

' Probe is a lane hypothesis, never a hidden enemy coordinate.
if probeLane = 1 and selfLayer = selfTeam then
  stageX = riverWest - bankMargin
  aimX = stageX + hookRange
  if selfTeam = 1 then
    stageX = riverEast + bankMargin
    aimX = stageX - hookRange
  end if
  sx = stageX - selfX
  sy = homeY - selfY
  if sx * sx + sy * sy > 4 then
    walkTo(stageX, homeY)
  else
    if hookReady = 1 then
      safeHookTo(aimX, homeY)
    end if
  end if
end if
"""
    if lesson.ranged_movement == "hold":
        return code  # Preserve the first lesson's executable artifacts byte-for-byte.
    selection = code[:code.index("if melee = 0 then\n")]
    pull = """' Preserve a nearby pull until attackTarget can take over.
preservePull = 1
if best >= 0 then
  if objectLayer(best) = selfLayer and selfLayer <> 2 then
    if bestD2 <= meleeRadius * meleeRadius and objectHooked(best) = 1 then
      halt()
      patrolActive = 0
      end
    end if
  end if
end if
""" if lesson.preserve_pull else ""
    return selection + f"""' Mobility contract: melee commits; otherwise seek another firing angle.
patrolRadius = {lesson.patrol_radius}
waypointTimeoutTicks = {lesson.waypoint_timeout_ticks}
if melee = 1 then
  if hookReady = 1 and hookDuringMelee = 1 then
    safeHookTo(objectX(best), objectY(best))
  end if
  patrolActive = 0
  end
end if

{pull}' The engine preserves BASIC globals between decisions. This is option state,
' not an opponent belief. Four waypoints stay in the home lane and on our bank.
if selfLayer = selfTeam then
  px = patrolX - selfX
  py = patrolY - selfY
  if patrolActive = 0 or px * px + py * py <= 4 or worldTick >= patrolUntil then
    if patrolActive = 0 then
      patrolLeg = selfId mod 4
    else
      patrolLeg = (patrolLeg + 1) mod 4
    end if
    inset = bankMargin
    if patrolLeg = 1 or patrolLeg = 2 then
      inset = inset + 4
    end if
    patrolX = riverWest - inset
    if selfTeam = 1 then
      patrolX = riverEast + inset
    end if
    patrolY = homeY - patrolRadius
    if patrolLeg >= 2 then
      patrolY = homeY + patrolRadius
    end if
    if patrolY < 20 then
      patrolY = 20
    end if
    if patrolY > 107 then
      patrolY = 107
    end if
    patrolUntil = worldTick + waypointTimeoutTicks
    patrolActive = 1
  end if
  walkTo(patrolX, patrolY)
else
  patrolActive = 0
  halt()
end if

' Hook selection is independent of navigation. A failed safe shot never stops
' movement. Native hook windup briefly stops motion without clearing its goal.
if hookReady = 1 then
  if best >= 0 and bestD2 <= hookRange * hookRange then
    safeHookTo(objectX(best), objectY(best))
  else
    if selfLayer = selfTeam then
      aimX = selfX + hookRange
      if selfTeam = 1 then
        aimX = selfX - hookRange
      end if
      if aimX < 0 then
        aimX = 0
      end if
      if aimX > 127 then
        aimX = 127
      end if
      safeHookTo(aimX, selfY)
    end if
  end if
end if
"""


def executable(text: str) -> list[str]:
    # Generated subset has no string literals; apostrophe starts a BASIC comment.
    return [" ".join(line.split("'", 1)[0].lower().split())
            for line in text.splitlines() if line.split("'", 1)[0].strip()]


def extract(code: str) -> Lesson:
    lines = executable(code)
    names = ("meleeradius", "hookrange", "hookduringmelee", "probelane", "bankmargin")
    values = []
    for name, line in zip(names, lines):
        match = re.fullmatch(name + r" = (\d+)", line)
        if not match:
            raise ValueError("Unsupported BASIC projection")
        values.append(int(match[1]))
    if len(values) != 5 or values[2] not in (0, 1) or values[3] not in (0, 1):
        raise ValueError("Incomplete / invalid BASIC projection")
    lesson = Lesson(values[0], values[1], bool(values[2]),
                    "probe_lane" if values[3] else "hold", values[4]).validate()
    radius = [re.fullmatch(r"patrolradius = (\d+)", line) for line in lines]
    timeout = [re.fullmatch(r"waypointtimeoutticks = (\d+)", line) for line in lines]
    radius = [int(m[1]) for m in radius if m]
    timeout = [int(m[1]) for m in timeout if m]
    if radius or timeout:
        if len(radius) != 1 or len(timeout) != 1:
            raise ValueError("Incomplete / ambiguous movement contract")
        lesson = Lesson(*values[:2], bool(values[2]), "probe_lane" if values[3] else "hold",
                        values[4], "patrol", radius[0], timeout[0],
                        "preservepull = 1" in lines).validate()
    if lines != executable(generate(lesson)):
        raise ValueError("Unrecognized executable change; cannot claim semantic equivalence")
    return lesson


def describe(lesson: Lesson) -> str:
    if lesson.ranged_movement == "patrol":
        return f"""# Code-derived behavioral IR — movement and hooking

1. Situation: nearest visible living unshielded enemy; same non-water layer and
   within {lesson.melee_radius} tiles affords melee acquisition. Dead/hooked self yields.
2. Belief: hidden enemies remain unknown. Blind casts test the current horizontal
   lane. patrolLeg, patrolX/Y, patrolUntil and patrolActive retain option progress,
   not learned beliefs. No enemy position is inferred from this memory.
3. Goal: executable precedence commits to nearby melee over patrol. The coaching
   rationale cannot be recovered from executable code alone.
4. Skills: sustain melee with attackTarget; safeHookTo within {lesson.hook_range};
   otherwise traverse four own-bank waypoints, homeY ± {lesson.patrol_radius}, clamped
   to Y 20–107. Bank inset alternates {lesson.bank_margin} and {lesson.bank_margin + 4}.
   Advance within two tiles or after {lesson.waypoint_timeout_ticks} ticks. Initial
   leg is selfId mod 4; acquiring melee resets option activation.
   Nearby-pull commitment is {str(lesson.preserve_pull).lower()}: when enabled,
   hold for a hooked enemy within the same melee acquisition envelope, then
   acquire melee when the pull releases. This does not identify the hook owner.
5. Strategy: melee acquisition suppresses patrol. Hook during melee is
   {str(lesson.hook_during_melee).lower()}. Outside melee, walk and independently
   hook the nearest visible in-range target; otherwise probe horizontally from
   the current position. A rejected hook does not suppress movement.
6. Execution: BASIC globals retain patrol progress. Engine owns pathfinding,
   collision and windup. Off home bank without melee, halt; still try visible
   targets. No economy, dodging, leading, obstacle perception or opponent model.
7. Update: revise text IR offline, regenerate, reverse-check, evaluate. Patrol
   is a bounded search heuristic, not a guarantee of a clear shot or continuous motion.

{block(lesson)}"""
    return f"""# Code-derived behavioral IR

1. Situation: nearest fog-visible living unshielded enemy butcher; integer tile
   distance; same layer and not in water for melee. Dead/hooked self emits nothing.
2. Belief: no persistent opponent belief. An unseen enemy is unknown. Probe mode
   assumes a possible target across the spawn lane; it does not observe one.
3. Goal: executable precedence favors engagement over idle behavior. The original
   human rationale and desired outcome CANNOT be recovered from this code.
4. Skills: select nearest enemy; engage within {lesson.melee_radius} tiles with
   attackTarget; throw within {lesson.hook_range} tiles using safeHookTo. Engine
   sustains attacks. Idle mode is {lesson.idle}, with bank margin {lesson.bank_margin}.
5. Strategy: acquire melee first, independently throw when ready; hook during melee
   is {str(lesson.hook_during_melee).lower()}. If no in-range visible target, apply
   idle behavior. Target selection has no persistence, motion lead, or fallback
   after a blocked hook. Probe mode stages on the home lane, then throws across it.
6. Execution: no purchases, upgrades, rot, blinks, rescues or generic policy imports.
   halt clears attack and movement outside melee. Hook windup briefly interrupts
   melee even when both skills are selected. Engine controls pathing and collisions.
7. Update: no runtime learning. Change the authored IR, generate, verify, evaluate.

These are recovered behavior contracts, not recovered intent or proof of strength.

{block(lesson)}"""


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("direction", choices=["generate", "extract", "verify"])
    p.add_argument("source", type=Path)
    p.add_argument("output", type=Path, nargs="?")
    a = p.parse_args()
    source = a.source.read_text()
    if a.direction == "generate":
        result = generate(parse(source))
    else:
        lesson = extract(source)
        result = describe(lesson) if a.direction == "extract" else block(lesson)
    if a.output:
        a.output.write_text(result)
    else:
        print(result)


if __name__ == "__main__":
    main()
