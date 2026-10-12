# Properties that matter

## ParticleEmitter
| Property | Notes / good start |
|---|---|
| Rate | 0 for bursts (use ctx.Emit). |
| Lifetime | NumberRange. Sparks 0.2-0.45, glow 0.3-0.6, smoke 0.8-1.5. |
| Speed | NumberRange. Sparks 20-40, smoke 1-4. |
| SpreadAngle | Vector2. (180,180) = all directions. (15,15) = cone. |
| Size / Transparency | NumberSequence. Pop then shrink; fade in last 30-50%. |
| Color | ColorSequence. Use 2-3 keypoints for value contrast. |
| LightEmission | 1 = additive glow (energy). 0 = normal (smoke/dust). |
| LightInfluence | 0 = ignores scene lighting (energy). 0.5-1 for matter. |
| Brightness | >1 boosts glow. 1-3 typical. |
| Drag | High (5-8) makes bursts snap out then hang. |
| Acceleration | Gravity for debris (y -30 to -80), rise for smoke (y 2-6). |
| Squash | NumberSequence; stretches particles. Pair with VelocityParallel for streaks. |
| Orientation | FacingCamera (default), VelocityParallel (streaks), VelocityPerpendicular (flat discs). |
| Rotation / RotSpeed | Random rotation hides texture repetition. |
| FlipbookLayout / Mode / Framerate | For animated sheets (Grid2x2/4x4/8x8). OneShot for bursts. |
| ZOffset | Push core layers forward so they draw over smoke. |
| Shape / ShapeStyle / ShapeInOut | Emit from a volume or surface, e.g. Disc + Outward for ground rings. |
| EmissionDirection | NormalId the emitter points along (e.g. Top for upward dust). |
| LockedToPart | true for projectile cores. |
| TimeScale | Set by ctx.Emit; don't set manually. |

## Beam
Attachment0/1, Width0/1, CurveSize0/1 (arcs), Segments (smoothness), Texture,
TextureMode (Stretch/Wrap/Static), TextureSpeed (scrolling energy), LightEmission,
Brightness, FaceCamera, Transparency (NumberSequence), ZOffset.

## Trail
Attachment0/1, Lifetime (0.1-0.3 for weapons), WidthScale (taper to 0), MinLength,
FaceCamera, Texture, LightEmission, Transparency, Color.

## Highlight
FillColor, FillTransparency, OutlineColor, OutlineTransparency, DepthMode.
Good for hit flashes and buffs: tween FillTransparency from ~0.4 to 1.

## Neon parts (flashes, rings)
Material Neon, Anchored, CanCollide/CanQuery/CanTouch/CastShadow false.
Cylinder axis is local X: size (thickness, diameter, diameter).

## Mesh templates (cloned from ReplicatedStorage/VFX/Meshes)
- Templates are already Anchored with collisions/queries/shadows off.
- Energy look: Material Neon + Color. Matter look: Slate/Concrete/Ice + Color.
- Gradient look: set `TextureID` to a gradient texture; MeshFactory meshes run U
  along the shape, so a horizontal gradient fades along a slash.
- Animate with ctx.Tween on Size, Transparency, CFrame. Size scales the mesh.
- MeshFactory shapes lie flat with Y up; rotate the CFrame to the swing/impact plane.
  Crescent is centered on +X.

## MeshParticles.Burst(ctx, template, count, config)
Non-blocking. Simulated client-side; respects slow-mo.

| Config | Type | Default | Notes |
|---|---|---|---|
| Origin | Vector3 | ctx.CFrame.Position | |
| Direction | Vector3 | up | center of the emission cone |
| Spread | number (deg) | 45 | cone half-angle, 0-180 |
| Speed | NumberRange/number | 20 | studs/sec |
| Lifetime | NumberRange/number | 1 | seconds; Linger must cover the max |
| Drag | number | 0 | exponential slowdown |
| Acceleration | Vector3 | (0,-60,0) | gravity; debris uses -80 to -110 |
| SpinSpeed | NumberRange/number | 360 | degrees/sec, random axis |
| Scale | number | 1 | multiplies template size |
| Size | NumberSequence/number | 1 | multiplier over lifetime; shrink to 0 at the end |
| Transparency | NumberSequence/number | 0 | over lifetime |
| SpawnRadius | number | 0 | random offset from Origin |
