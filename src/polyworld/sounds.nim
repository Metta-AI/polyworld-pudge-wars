## Minimal one-shot audio for PolyWorld games.
##
## One OpenAL device, mono 16-bit buffers, and fire-and-forget
## playback. Effects can be synthesized in memory or loaded from a
## PCM WAV. Everything degrades to silence when no audio device
## exists, so headless boxes and CI never fail.

import std/[math, os, streams], openal

const
  SoundSampleRate* = 22050
    ## Mono synthesis rate: plenty for chip-style effects, tiny buffers.

type
  Synth* = object
    ## A float32 mix bus one effect is composed onto before quantizing.
    samples*: seq[float32]

  SoundBuffer* = object
    ## One uploaded OpenAL buffer, playable many times over.
    id: ALuint
    ok: bool

var
  soundDevice: ALCdevice
  soundContext: ALCcontext
  soundsOpen = false
  soundsMutedFlag = false
  soundsMasterGainFlag = 1.0'f32
  liveSources: seq[ALuint]
  uploadedBuffers: seq[ALuint]

proc soundsAvailable*(): bool =
  ## Returns whether an audio device is open.
  soundsOpen

proc setSoundsMuted*(muted: bool) =
  soundsMutedFlag = muted

proc soundsMuted*(): bool =
  soundsMutedFlag

proc setSoundsMasterGain*(gain: float32) =
  ## Scales every one-shot (0 silent .. 1 full). Independent of mute.
  soundsMasterGainFlag = clamp(gain, 0.0'f32, 1.0'f32)

proc soundsMasterGain*(): float32 =
  soundsMasterGainFlag

proc initSounds*(): bool =
  ## Opens the default output device. Returns false and leaves the
  ## module silent when there is no usable device.
  if soundsOpen:
    return true
  soundDevice = alcOpenDevice(nil)
  if soundDevice == nil:
    return false
  soundContext = soundDevice.alcCreateContext(nil)
  if soundContext == nil:
    discard alcCloseDevice(soundDevice)
    soundDevice = nil
    return false
  if not alcMakeContextCurrent(soundContext):
    alcDestroyContext(soundContext)
    discard alcCloseDevice(soundDevice)
    soundContext = nil
    soundDevice = nil
    return false
  soundsOpen = true
  true

proc tickSounds*() =
  ## Reclaims sources that finished playing. Call once per frame.
  if not soundsOpen:
    return
  var i = 0
  while i < liveSources.len:
    var state: ALenum
    alGetSourcei(liveSources[i], AL_SOURCE_STATE, addr state)
    if state != AL_PLAYING:
      alDeleteSources(1, addr liveSources[i])
      liveSources.del(i)
    else:
      inc i

proc closeSounds*() =
  ## Stops everything and closes the device.
  if not soundsOpen:
    return
  for source in liveSources.mitems:
    alSourceStop(source)
    alDeleteSources(1, addr source)
  liveSources.setLen(0)
  for id in uploadedBuffers.mitems:
    var bufferId = id
    alDeleteBuffers(1, addr bufferId)
  uploadedBuffers.setLen(0)
  alcDestroyContext(soundContext)
  discard alcCloseDevice(soundDevice)
  soundContext = nil
  soundDevice = nil
  soundsOpen = false

proc initSynth*(seconds: float32): Synth =
  ## An empty mix bus of the given length.
  Synth(samples: newSeq[float32](int(seconds * SoundSampleRate.float32)))

proc envelope(t, duration, attack, decay: float32): float32 =
  ## Linear attack, exponential-ish decay; zero outside the note.
  if t < 0 or t >= duration:
    return 0
  let rise = if attack <= 0: 1.0'f32 else: min(t / attack, 1.0'f32)
  let fall =
    if decay <= 0:
      1.0'f32
    else:
      exp(-max(t - attack, 0.0'f32) / decay)
  rise * fall

proc addTone*(
    synth: var Synth,
    frequency: float32,
    start = 0.0'f32,
    duration = 0.15'f32,
    gain = 0.5'f32,
    attack = 0.004'f32,
    decay = 0.06'f32,
    square = false
) =
  ## Mixes one sine (or square) note into the bus.
  let
    first = max(int(start * SoundSampleRate.float32), 0)
    last = min(
      int((start + duration) * SoundSampleRate.float32),
      synth.samples.len
    )
  for i in first ..< last:
    let
      t = float32(i - first) / SoundSampleRate.float32
      phase = TAU.float32 * frequency * t
      wave =
        if square:
          (if sin(phase) >= 0: 1.0'f32 else: -1.0'f32) * 0.6'f32
        else:
          sin(phase)
    synth.samples[i] += wave * gain * envelope(t, duration, attack, decay)

proc addSweep*(
    synth: var Synth,
    fromFrequency, toFrequency: float32,
    start = 0.0'f32,
    duration = 0.2'f32,
    gain = 0.5'f32,
    attack = 0.004'f32,
    decay = 0.09'f32
) =
  ## Mixes a pitch glide into the bus.
  let
    first = max(int(start * SoundSampleRate.float32), 0)
    last = min(
      int((start + duration) * SoundSampleRate.float32),
      synth.samples.len
    )
  var phase = 0.0'f32
  for i in first ..< last:
    let
      t = float32(i - first) / SoundSampleRate.float32
      blendT = t / max(duration, 0.0001'f32)
      frequency = fromFrequency + (toFrequency - fromFrequency) * blendT
    phase += TAU.float32 * frequency / SoundSampleRate.float32
    synth.samples[i] += sin(phase) * gain * envelope(t, duration, attack, decay)

proc addNoise*(
    synth: var Synth,
    start = 0.0'f32,
    duration = 0.1'f32,
    gain = 0.4'f32,
    attack = 0.001'f32,
    decay = 0.035'f32,
    rough = 1.0'f32
) =
  ## Mixes a filtered noise burst into the bus. `rough` blends between
  ## dark rumble (near 0) and bright hiss (1).
  let
    first = max(int(start * SoundSampleRate.float32), 0)
    last = min(
      int((start + duration) * SoundSampleRate.float32),
      synth.samples.len
    )
  # Deterministic cheap noise: xorshift so effects sound identical
  # across runs and platforms.
  var state = 0x9E3779B9'u32
  var held = 0.0'f32
  for i in first ..< last:
    state = state xor (state shl 13)
    state = state xor (state shr 17)
    state = state xor (state shl 5)
    let white = float32(cast[int32](state)) / float32(int32.high)
    held += (white - held) * clamp(rough, 0.02'f32, 1.0'f32)
    let t = float32(i - first) / SoundSampleRate.float32
    synth.samples[i] += held * gain * envelope(t, duration, attack, decay)

proc uploadPcm(pcm: var seq[int16], sampleRate: int32): SoundBuffer =
  ## Uploads mono 16-bit PCM to OpenAL.
  if not soundsOpen or pcm.len == 0:
    return SoundBuffer(ok: false)
  var id: ALuint
  discard alGetError()
  alGenBuffers(1, addr id)
  if alGetError() != AL_NO_ERROR:
    return SoundBuffer(ok: false)
  alBufferData(
    id,
    AL_FORMAT_MONO16,
    addr pcm[0],
    ALsizei(pcm.len * 2),
    ALsizei(sampleRate)
  )
  if alGetError() != AL_NO_ERROR:
    alDeleteBuffers(1, addr id)
    return SoundBuffer(ok: false)
  uploadedBuffers.add id
  SoundBuffer(id: id, ok: true)

proc toBuffer*(synth: Synth): SoundBuffer =
  ## Quantizes the bus to mono 16-bit and uploads it to OpenAL.
  if not soundsOpen or synth.samples.len == 0:
    return SoundBuffer(ok: false)
  var pcm = newSeq[int16](synth.samples.len)
  for i, sample in synth.samples:
    pcm[i] = int16(clamp(sample, -1.0'f32, 1.0'f32) * 32200.0'f32)
  uploadPcm(pcm, SoundSampleRate)

proc loadWavBuffer*(path: string): SoundBuffer =
  ## Loads a PCM WAV as a one-shot buffer. Stereo is folded to mono.
  ## Returns an empty buffer when the file is missing or not PCM.
  if not soundsOpen or not fileExists(path):
    return SoundBuffer(ok: false)
  let stream = newFileStream(path, fmRead)
  if stream == nil:
    return SoundBuffer(ok: false)
  defer:
    stream.close()
  if stream.readStr(4) != "RIFF":
    return SoundBuffer(ok: false)
  discard stream.readUint32()
  if stream.readStr(4) != "WAVE":
    return SoundBuffer(ok: false)
  var
    channels = 0'i32
    sampleRate = 0'i32
    bits = 0'i32
    pcm = newSeq[int16]()
    foundFmt = false
    foundData = false
  while not stream.atEnd:
    let
      chunkId = stream.readStr(4)
      chunkSize = int(stream.readUint32())
    if chunkId.len < 4:
      break
    if chunkId == "fmt ":
      let format = stream.readUint16()
      channels = int32(stream.readUint16())
      sampleRate = int32(stream.readUint32())
      discard stream.readUint32()
      discard stream.readUint16()
      bits = int32(stream.readUint16())
      if chunkSize > 16:
        stream.setPosition(stream.getPosition() + chunkSize - 16)
      if format != 1'u16 or channels < 1 or sampleRate <= 0 or
          (bits != 8 and bits != 16):
        return SoundBuffer(ok: false)
      foundFmt = true
    elif chunkId == "data":
      if not foundFmt:
        return SoundBuffer(ok: false)
      let
        bytesPerSample = bits div 8
        frameSize = bytesPerSample * channels
      if frameSize <= 0 or chunkSize < frameSize:
        return SoundBuffer(ok: false)
      let frames = chunkSize div frameSize
      var raw = newSeq[uint8](chunkSize)
      if stream.readData(addr raw[0], chunkSize) != chunkSize:
        return SoundBuffer(ok: false)
      pcm.setLen(frames)
      if bits == 16:
        for i in 0 ..< frames:
          var mix = 0'i32
          for ch in 0 ..< channels:
            let
              at = (i * channels + ch) * 2
              sample = cast[int16](uint16(raw[at]) or (uint16(raw[at + 1]) shl 8))
            mix += int32(sample)
          pcm[i] = int16(mix div channels)
      else:
        for i in 0 ..< frames:
          var mix = 0'i32
          for ch in 0 ..< channels:
            let sample = int32(raw[i * channels + ch]) - 128
            mix += sample * 256
          pcm[i] = int16(mix div channels)
      if chunkSize mod 2 == 1 and not stream.atEnd:
        discard stream.readChar()
      foundData = true
      break
    else:
      stream.setPosition(stream.getPosition() + chunkSize)
      if chunkSize mod 2 == 1 and not stream.atEnd:
        discard stream.readChar()
  if not foundData:
    return SoundBuffer(ok: false)
  uploadPcm(pcm, sampleRate)

proc bufferReady*(buffer: SoundBuffer): bool =
  ## True when the buffer was uploaded and can be played.
  buffer.ok

proc playBuffer*(buffer: SoundBuffer, gain = 1.0'f32, pitch = 1.0'f32) =
  ## Fire-and-forget playback; the source is reclaimed by tickSounds.
  if not soundsOpen or soundsMutedFlag or not buffer.ok:
    return
  if liveSources.len >= 32:
    return # Never let a burst of events open unbounded sources.
  var source: ALuint
  discard alGetError()
  alGenSources(1, addr source)
  if alGetError() != AL_NO_ERROR:
    return
  alSourcei(source, AL_BUFFER, cast[ALint](buffer.id))
  alSourcef(
    source,
    AL_GAIN,
    clamp(gain * soundsMasterGainFlag, 0.0'f32, 2.0'f32)
  )
  alSourcef(source, AL_PITCH, clamp(pitch, 0.25'f32, 4.0'f32))
  alSourcePlay(source)
  liveSources.add source
