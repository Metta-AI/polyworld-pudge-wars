## Fresh Meat WAV clips load through the engine sound module.

import
  polyworld/sounds,
  ../examples/pudge_wars/content

echo "Testing recorded clips upload when a device exists"
if initSounds():
  for name in ["hook_throw", "hook_latch", "splash", "voice_laugh"]:
    let buf = loadWavBuffer(soundPath(name))
    doAssert bufferReady(buf), "failed to load " & soundPath(name)
  closeSounds()
  echo "  uploaded hook, latch, splash, and voice"
else:
  echo "  no output device, skipped upload"

echo "test_pw_audio: all checks passed"
