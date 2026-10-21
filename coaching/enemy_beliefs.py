"""Enemy location judgments from visible sightings, never hidden world state."""
from collections import deque


ZONES = {
    f"{side}_{lane}": {"label": f"{side.title()} · {lane}", "x": x, "y": y, "width": w, "height": h}
    for side, x, w in (("west", 0, 53), ("river", 53, 22), ("east", 75, 53))
    for lane, y, h in (("north", 0, 48), ("mid", 48, 32), ("south", 80, 48))
}
LOCATION_CRITERIA = {key: f"{z['label']}: x in [{z['x']}, {z['x'] + z['width']}), y in [{z['y']}, {z['y'] + z['height']})."
                     for key, z in ZONES.items()} | {"unknown": "Insufficient evidence to locate this enemy, or respawning/outside the mapped arena."}


class EnemyBeliefs:
    def __init__(self):
        self.tracks = {}
        self.predictions = {}
        self.tick = 0
        self.visible_ids = set()

    def observe(self, obs):
        self.tick = obs["tick"]
        self.visible_ids = set()
        for player in obs["visible"]["pudges"]:
            if player["team"] == obs["self"]["team"]:
                continue
            self.visible_ids.add(player["id"])
            track = self.tracks.setdefault(player["id"], {"id": player["id"], "slot": player["slot"], "samples": deque(maxlen=12)})
            sample = {k: player[k] for k in ("x", "y", "hp", "max_hp", "alive", "team")}
            sample["tick"] = self.tick
            track["last"] = sample
            if not track["samples"] or self.tick - track["samples"][-1]["tick"] >= 8:
                track["samples"].append(sample)

    def context(self):
        return [{"id": t["id"], "slot": t["slot"], "visible_now": t["id"] in self.visible_ids,
                 "last_seen": t["last"], "recent_sightings": list(t["samples"])} for t in self.tracks.values()]

    def questions(self):
        questions = {}
        for identifier, track in self.tracks.items():
            if not track["last"]["alive"] or self.tick - track["last"]["tick"] > 32 * 15:
                continue
            for horizon in ("now", "next"):
                if horizon == "now" and identifier in self.visible_ids:
                    continue
                when = "at the observation's current tick" if horizon == "now" else "two seconds (64 ticks) after the observation's current tick"
                questions[f"enemy_{identifier}_{horizon}"] = {
                    "type": "choice", "instructions":
                        f"Where is enemy ID {identifier} most likely to be {when}? "
                        "Use ONLY the supplied visible sightings, observed health, movement trend and time since last sighting. "
                        "Coordinates are tiles; north is lower y. The banks are separated by the river; blink can cross it. "
                        "Allow for changes of direction and unobserved movement. Last seen is evidence, not a current position. "
                        "Choose unknown when evidence is too old or insufficient. Do not invent unseen observations.",
                    "criteria": LOCATION_CRITERIA,
                }
        return questions

    def accept(self, payload, request, tick):
        for key in request["questions"]:
            if not key.startswith("enemy_"):
                continue
            answer = payload["answers"][key]
            self.predictions[key] = {"tick": tick, "confidence": answer["confidence"],
                                     "probabilities": dict(answer["probabilities"])}

    def view(self, enabled=True):
        enemies = []
        for identifier, track in self.tracks.items():
            last = track["last"]
            forecasts = {}
            if enabled:
                for horizon in ("now", "next"):
                    prediction = self.predictions.get(f"enemy_{identifier}_{horizon}")
                    if prediction and 0 <= self.tick - prediction["tick"] <= 64:
                        # A new sighting supersedes an estimate of a hidden position.
                        if horizon == "now" and last["tick"] > prediction["tick"]:
                            continue
                        forecasts[horizon] = prediction
            enemies.append({"id": identifier, "slot": track["slot"], "visible": identifier in self.visible_ids,
                            "last_seen": last, "age_seconds": round((self.tick - last["tick"]) / 32, 1),
                            "trail": list(track["samples"]), "forecasts": forecasts})
        return {"zones": ZONES, "enemies": enemies, "tick": self.tick}
