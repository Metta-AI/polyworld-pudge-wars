## Fresh Meat combat one-shots. Files live in
## polyworld_data/sounds/pudge_wars. Display-side only; the sim never
## hears anything. Playback is gated in graphics to the local hero and
## the current play camera. HUD, pings, runes, and match stingers stay
## silent. Audio starts muted.

import content, polyworld/sounds

type
  GameSound* = enum
    SndHookThrow
    SndHookLatch
    SndHookClash
    SndMelee
    SndKill
    SndDeath

const
  EffectFiles: array[GameSound, string] = [
    "hook_throw",
    "hook_latch",
    "hook_clash",
    "melee",
    "kill",
    "death"
  ]

var
  buffers: array[GameSound, SoundBuffer]
  audioReady = false

proc loadClip(name: string): SoundBuffer =
  let path = soundPath(name)
  result = loadWavBuffer(path)
  if not bufferReady(result):
    echo "audio: missing or unreadable ", path

proc initGameAudio*(muted: bool) =
  ## Opens the device and loads the recorded set. Silent no-op
  ## when no audio device exists.
  if not initSounds():
    echo "audio: no output device, staying silent"
    return
  for kind in GameSound:
    buffers[kind] = loadClip(EffectFiles[kind])
  setSoundsMuted(muted)
  audioReady = true

proc closeGameAudio*() =
  audioReady = false
  closeSounds()

proc tickGameAudio*() =
  tickSounds()

proc gameAudioMuted*(): bool =
  soundsMuted()

proc toggleGameAudioMute*() =
  setSoundsMuted(not soundsMuted())

proc playGameSound*(kind: GameSound, gain = 1.0'f32, pitch = 1.0'f32) =
  if audioReady:
    playBuffer(buffers[kind], gain, pitch)
