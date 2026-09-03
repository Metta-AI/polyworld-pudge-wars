## Shared fixed-north camera and minimap geometry for RTS games.

import
  std/math,
  vmath

const
  RtsCameraYaw* = 0.0'f32
  RtsCameraPitch* = 0.92'f32
  RtsOrbitPitchMin* = 0.22'f32
    ## Keep the eye above the ground; below this the camera clips through.
  RtsOrbitPitchMax* = 1.42'f32
    ## Just short of straight top-down so orbit still has a facing.
  RtsCameraDragPixels* = 6.0'f32
    ## Mouse travel that turns a click into a camera drag.
  RtsFieldOfView* = 45.0'f32

type MinimapViewRect* = object
  ## Describes the visible ground footprint inside a minimap rectangle.
  origin*: Vec2
  size*: Vec2

proc rtsClampedPitch*(pitch: float32): float32 =
  ## Clamps orbit pitch so the camera cannot go under the map.
  clamp(pitch, RtsOrbitPitchMin, RtsOrbitPitchMax)

proc rtsCameraRight*(yaw: float32): Vec3 =
  ## Ground-plane camera right at a given yaw (default 0 is +X).
  vec3(cos(yaw), 0, -sin(yaw))

proc rtsCameraLook*(yaw: float32): Vec3 =
  ## Ground-plane vector from the look-at toward the camera (yaw 0 is +Z).
  vec3(sin(yaw), 0, cos(yaw))

proc rtsGroundPan*(yaw: float32, delta: Vec2, speed: float32): Vec2 =
  ## Grab-the-map XZ pan. Subtract the result from `cameraTarget`.
  let
    right = rtsCameraRight(yaw)
    look = rtsCameraLook(yaw)
  vec2(
    (right.x * delta.x + look.x * delta.y) * speed,
    (right.z * delta.x + look.z * delta.y) * speed
  )

proc rtsCameraEye*(
    target: Vec3,
    distance: float32,
    yaw = RtsCameraYaw,
    pitch = RtsCameraPitch
): Vec3 =
  ## Returns the RTS camera position, optionally yawed/pitched for orbit.
  let p = rtsClampedPitch(pitch)
  target + vec3(
    sin(yaw) * cos(p),
    sin(p),
    cos(yaw) * cos(p)
  ) * distance

proc minimapWorldPoint*(
    pointer,
    origin,
    size: Vec2,
    worldHalfSize: float32
): Vec2 =
  ## Converts a minimap pixel into a clamped world XZ position.
  let ratio = clamp(
    (pointer - origin) / size,
    vec2(0),
    vec2(1)
  )
  vec2(
    ratio.x * worldHalfSize * 2 - worldHalfSize,
    ratio.y * worldHalfSize * 2 - worldHalfSize
  )

proc minimapViewport*(
    target: Vec3,
    distance,
    aspect: float32,
    origin,
    size: Vec2,
    worldHalfSize: float32
): MinimapViewRect =
  ## Approximates the camera's ground footprint in minimap pixels.
  let
    halfVerticalFov = RtsFieldOfView * PI.float32 / 360.0'f32
    cameraHeight = distance * sin(RtsCameraPitch)
    cameraForward = distance * cos(RtsCameraPitch)
    farOffset = cameraForward -
      cameraHeight / tan(RtsCameraPitch - halfVerticalFov)
    nearOffset = cameraForward -
      cameraHeight / tan(RtsCameraPitch + halfVerticalFov)
    halfHorizontalFov = arctan(tan(halfVerticalFov) * aspect)
    halfWidth = max(distance * tan(halfHorizontalFov), 1.0'f32)
    minimum = vec2(
      target.x - halfWidth,
      target.z + farOffset
    )
    maximum = vec2(
      target.x + halfWidth,
      target.z + nearOffset
    )
    worldSize = worldHalfSize * 2
    normalizedMinimum = clamp(
      (minimum + vec2(worldHalfSize)) / worldSize,
      vec2(0),
      vec2(1)
    )
    normalizedMaximum = clamp(
      (maximum + vec2(worldHalfSize)) / worldSize,
      vec2(0),
      vec2(1)
    )
  let rawSize = (normalizedMaximum - normalizedMinimum) * size
  result.size = vec2(
    clamp(rawSize.x, 4.0'f32, size.x),
    clamp(rawSize.y, 4.0'f32, size.y)
  )
  let rawOrigin = origin + normalizedMinimum * size
  result.origin = vec2(
    clamp(rawOrigin.x, origin.x, origin.x + size.x - result.size.x),
    clamp(rawOrigin.y, origin.y, origin.y + size.y - result.size.y)
  )
