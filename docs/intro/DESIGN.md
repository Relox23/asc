# Intro cutscene ("Awaken") — design

What happens after the player presses **Awaken** on the soul core select
screen: a ~42 s cinematic, fully in-engine, authored in Blender and played
back in Roblox.

Blender is the authoring tool for everything that moves or has a shape:
every mesh, the character animation, the camera, the space backdrop (star,
galaxy and nebula layout), the rift, the timing of impact frames, flashes and
camera shakes. A Python exporter bakes the Blender scene into a Luau data
module (`IntroData`) plus an FBX of the meshes (`IntroAssets.fbx`). The Roblox
runtime (`src/IntroCutscene`) only *plays back* that data and adds what can
only exist in the engine (GUI bars and impact frames, particles, beams,
lighting, the real map and the player's real avatar).

This document is the contract between those pieces. Names, units and formats
here are binding; if something has to change, change it here first.

---------------------------------------------------------------------------
## 1. Storyboard and timeline

Times are seconds from the moment Awaken is pressed. Blender runs at
**30 fps**, frame 1 = t 0.0, so `frame = round(t * 30) + 1`.
Total length **42.5 s** (frames 1–1276).

Two **stages** (places where things happen):

* **space** — the void, far away from the island (see §2). t 0.0 – 18.6
* **world** — the sky above Sylverune and the ground there. t 18.6 – 42.5

| t (s) | Shot | What we see | Camera |
| --- | --- | --- | --- |
| 0.0–1.5 | S0 Ignite | Screen goes black, cinematic bars slide in (0–1.0). In the centre the soul core ignites: a faint heartbeat glow growing to full brightness. | Close, soul core centred, static with tiny drift. |
| 1.5–10.0 | S1 Deep space | The soul core falls (moves down through space, slow spin). Around it, deep space reveals itself: first a few stars, then thousands (2.0–7.0), nebula clouds bloom (3.0–8.0), three galaxies swirl together from scattered dust into spiral arms (4.0–9.5). A comet tail in the core's colour grows behind it (3.0–9.0). Dust motes stream upward past the camera (the sense of falling). | Slow orbit around the core at ~12 studs, slightly below it looking up past it at the sky, falling with it. Gentle FOV breathing. |
| 10.0–12.5 | S2 Reveal | Camera swings round behind/above the core. Ahead, far below: an earth-like planet, half destroyed like a crescent moon (molten fracture face, debris ring). | One continuous swing (no cut): 180° orbit + rise, ends looking down past the core at the planet. |
| 12.5–15.0 | S3 Approach | Falling toward the planet, which looms larger. | Behind and above the core ("over the shoulder"), slight shake. |
| 15.0–16.6 | S3 Crack | In front of (below) the core, space itself cracks: bright jagged lines spread like breaking glass, flickering, with small flashes. | Same, slow push-in. Shake 0.4. |
| 16.6–17.6 | S3 Rift | The crack shatters: shards burst outward and tumble away, an opening tears open with a glowing violet-white rim. Through it: the island's forest seen from high above. | Push in, FOV widens. |
| 17.6–18.6 | S4 Enter | The core dives into the rift, the view through the rift fills the screen, white flash at 18.5. | Follows core into the rift. |
| 18.6–21.0 | W1 Exit | Above Sylverune, sky. A rift is open in the sky (the other side). The soul core shoots out of it as a streak of light, slows, and at 20.3–21.0 bursts into the shape of the player's character (light condensing into the body; flash 20.9). | Below the rift looking up, then tracks the falling core. |
| 21.0–25.0 | W2 Notice | The player falls (spread-eagle, slow tumble), looks around, looks up: from the rift a sword appears (crystals colourless) and tumbles after them, catching up. | Orbiting close shots of the falling player; cut at 23.0 to a low angle looking up at player + sword + rift. |
| 25.0–28.0 | W3 Struggle | The player reaches for the spinning sword, misses, flails, the sword spins past the hand twice; at 27.6 the player's hand closes on the blade/grip. | Handheld-style close shots with shake; cut at 26.5. |
| 28.0–29.6 | W4 Resonance | Contact → impact frames (28.0–28.9: alternating black/white frames with radial speed lines, silhouettes), glow-explosion sphere in the core colour expands (28.9–29.4), white-core flash 29.0. The player reappears holding the sword whose crystals now glow in the soul core's colour. | Static close-up during impact frames, then pulled back by the blast. |
| 29.6–31.6 | W5 Swing | The player swings the sword in front of them (bright slash arc), then flips it horizontal under their feet. | Medium side shot. |
| 31.6–35.0 | W6 Surf & brake | Standing on the blade like a surfboard, diving toward the forest at speed (speed lines, wind streaks). From 33.0 they brake with everything they have: lean back, blade tilted up, sparks and a glowing wake, decelerating hard; stops dead ~4 studs above the ground at 35.0. | Chase cam behind/side, then front low angle for the brake. Shake builds. |
| 35.0–38.0 | W7 Shockwave | The stop releases a huge shockwave: ring of light and dust racing outward along the ground, and wind hitting every tree, bending them away (wave travels outward ~160 studs/s), grass flattening. | Cut at 35.1 to a far wide shot (~260 studs away, elevated) showing the circle and the forest bending. |
| 38.0–42.5 | W8 Step off | Cut close: the player steps off the hovering blade, drops to the ground (lands 39.2), turns, reaches out and grabs the floating sword (40.6), lowers it to their side (hero stance). Bars slide out 41.5–42.5. End: control returns to the player. | Medium close, slow push; final frame matches the default gameplay camera roughly. |

### Markers (events)

Blender `scene.timeline_markers`; the exporter writes them sorted by time.
A marker name is `kind` or `kind:arg1:arg2` (args are numbers or words).

| Marker | Meaning |
| --- | --- |
| `bars:in:<seconds>` / `bars:out:<seconds>` | Cinematic bars slide in/out over the given time. |
| `fade:from_black:<s>` / `fade:to_black:<s>` | Full-screen black fade. |
| `flash:white:<s>` / `flash:core:<s>` | Full-screen flash (white, or soul core colour) that fades over `<s>`. |
| `shake:<magnitude>:<s>` | Camera shake (studs of jitter at the camera, decays over `<s>`). |
| `impact:white` / `impact:black` / `impact:off` | Impact-frame mode from this moment until the next `impact:*` marker (see §6.4). |
| `speedlines:on` / `speedlines:off` | Screen-space speed lines. |
| `stage:world` | Switch from the space stage to the world stage (exactly t 18.6). |
| `cut` | The camera jumps; never interpolate across this time. |
| `wind:<strength>` | Shockwave wind starts now (tree bending, §7.3). |
| `shockwave` | Shockwave ring + dust spawn at the sword's position. |
| `resonate` | Sword crystals switch from colourless to the soul core colour (the `resonance` channel does the fade; this marker triggers burst particles). |
| `morph` | Soul core → character (particles, character becomes visible). |
| `sound:<name>` | Play sound `<name>` from `Config.SOUNDS` (ignored if no id). |
| `end` | Cutscene over (t 42.5). |

Cuts (all also exported as `cuts`): 10.0 is NOT a cut (continuous swing).
Cuts at 18.6, 23.0, 26.5, 35.1, 38.0.

---------------------------------------------------------------------------
## 2. Coordinates, units and stages

* 1 Blender unit = 1 stud. Blender is Z-up, the character faces +Y.
* **Blender → Roblox** for scene positions/rotations (a proper rotation):
  `R(x, y, z) = (x, z, -y)`. Matrix `C = [[1,0,0],[0,0,1],[0,-1,0]]`.
  Rotations: `Rrbx = C · Rbl · Cᵀ`. Quaternions: convert via matrix.
  Blender +Y (forward) → Roblox −Z (= `CFrame.LookVector` of an unrotated
  CFrame). Blender +Z → Roblox +Y.
* Each stage has an **origin CFrame** in Roblox; a Blender stage coordinate
  `p` lands at `origin * CFrame.new(R(p))`, rotations likewise
  (`origin * CFrame(R-converted rotation)`).
  * `space` origin: `Config.SPACE_ORIGIN`, default
    `CFrame.new(0, 3000, 40000)` (far past the world border, nothing else there).
  * `world` origin: the landing point on the ground at Sylverune (§7.1),
    rotated about Y so Blender +Y points from the landing point toward the
    island centre (the hub), i.e. the character ends up facing the hub.
* Space-stage geometry that is "at infinity" (dome, stars, galaxies, nebula)
  is parented to the empty **SkyAnchor**, which copies the camera's location
  every frame (Blender: Copy Location constraint; Roblox: re-pivot every
  frame). So the sky never parallaxes, like a real skybox.
* **Assets** (from `IntroAssets.fbx`) follow the asset library convention of
  the map generator: modelled with the ground point/pivot at the origin and
  their front toward Blender −Y; the importer-proof marker meshes
  `<Asset>__Origin/__Up/__Front` (see `tools/blender/kit.py`,
  `src/IslandMapGenerator/AssetLibrary.luau`). Asset-local offsets are
  `fromBlender(x, y, z) = (-x, z, y)`, which is `R` followed by a 180° turn
  about Y. Therefore the Roblox CFrame for an asset whose Blender object has
  world rotation `Rbl` and location `p` is
  `origin * CFrame.new(R(p)) * Rrbx * CFrame.Angles(0, math.pi, 0)`
  (`Convert.assetCF` does this).

---------------------------------------------------------------------------
## 3. Blender scene objects (names are binding)

All live in the scene built by `tools/blender/intro/scene.py`. Custom
properties (`obj["name"]`) are animated with keyframes and exported as scalar
channels. `visible` is always a channel (0/1, constant interpolation) —
`hide_render` is keyed from it.

| Object | Stage | Asset | Channels besides transform | Notes |
| --- | --- | --- | --- | --- |
| `Camera` | both | — | `fov` (vertical FOV, degrees) | `sensor_fit = VERTICAL`, sensor 24 mm; `fov` must be keyed consistently with `lens` (exporter computes fov from lens, never trust the prop). |
| `SkyAnchor` | space | — | — | Copy Location of Camera. Parent of `SpaceDome`, starfield, galaxies, nebulae. |
| `SpaceDome` | space | `SpaceDome` | — | Inverted sphere r = 1000, black. Child of SkyAnchor. |
| `Starfield` | space | (procedural) | `stars` 0–1, `nebula` 0–1, `galaxies` 0–1, `twinkle` 0–1 | Points generated by `space.py` (§5); child of SkyAnchor. |
| `SoulCore` | space + world (until morph) | `SoulCore` | `glow` 0–3, `pulse` 0–1, `tail` 0–1 (comet tail length), `visible` | Diameter ~3 studs. |
| `Planet` | space | `ShatteredPlanet` | `visible` | Radius 320. Debris pieces are part of the asset. Slow rotation. |
| `Rift` | space | `Rift` | `crack` 0–1, `open` 0–1, `visible` | Plane facing +Z (the core falls through it from above). |
| `SkyRift` | world | `Rift` | `crack`, `open`, `visible` | Same asset, high above the landing point, opening facing down (−Z). |
| `CharacterRoot` | world | (player's avatar) | `visible`, `form` 0–1 (0 = light, 1 = solid body) | Armature object `CharacterRig` (§4) — its object transform *is* the HumanoidRootPart. |
| `Sword` | world | `ResonanceSword` | `resonance` 0–1 (0 colourless, 1 core colour), `glow` 0–3, `held` 0/1, `visible` | When `held` = 1, Blender uses a Child Of constraint to the `RightHand` bone with the grip offset (§4.3); the exporter bakes the world transform anyway, the runtime may use the grip instead. |
| `Shockwave` | world | `Shockwave` | `opacity` 0–1, `visible` | Ring on the ground; scale animates (uniform). |
| `Blast` | world | (runtime sphere) | `opacity` 0–1, `visible` | Glow explosion sphere (resonance). Scale = diameter in studs / 2. |
| `SlashArc` | world | `SlashArc` | `opacity` 0–1, `visible` | Crescent trail mesh of the swing. |

The world stage in Blender also has a **preview-only** environment (ground
plane, ~120 instances of the map's tree meshes appended from
`assets/IslandAssets.blend`, the stone circle) so renders show the bending
forest. It is not exported.

---------------------------------------------------------------------------
## 4. Character rig (R15)

`tools/blender/intro/rig.py` builds `CharacterRig`: an armature + block
mannequin parts (preview only) with exactly the R15 Motor6D names as bones.

### 4.1 Joint layout (Roblox character space, relative to HumanoidRootPart centre; feet at y = −3.0)

| Bone (= Motor6D) | Parent bone | Part it moves | Pivot (x, y, z) |
| --- | --- | --- | --- |
| `Root` | — | LowerTorso | (0, −0.3, 0) |
| `Waist` | Root | UpperTorso | (0, −0.3, 0) |
| `Neck` | Waist | Head | (0, 1.3, 0) |
| `LeftShoulder` | Waist | LeftUpperArm | (−1.25, 1.1, 0) |
| `LeftElbow` | LeftShoulder | LeftLowerArm | (−1.5, −0.05, 0) |
| `LeftWrist` | LeftElbow | LeftHand | (−1.5, −0.95, 0) |
| `RightShoulder` | Waist | RightUpperArm | (1.25, 1.1, 0) |
| `RightElbow` | RightShoulder | RightLowerArm | (1.5, −0.05, 0) |
| `RightWrist` | RightElbow | RightHand | (1.5, −0.95, 0) |
| `LeftHip` | Root | LeftUpperLeg | (−0.5, −0.8, 0) |
| `LeftKnee` | LeftHip | LeftLowerLeg | (−0.5, −2.0, 0) |
| `LeftAnkle` | LeftKnee | LeftFoot | (−0.5, −2.85, 0) |
| `RightHip` | Root | RightUpperLeg | (0.5, −0.8, 0) |
| `RightKnee` | RightHip | RightLowerLeg | (0.5, −2.0, 0) |
| `RightAnkle` | RightKnee | RightFoot | (0.5, −2.85, 0) |

Character right = Roblox +X, forward = Roblox −Z (= Blender +Y), up = +Y.
Mannequin part sizes (preview): LowerTorso 2×0.5×1 centred (0,−0.55,0);
UpperTorso 2×1.6×1 (0,0.5,0); Head 1.2³ (0,1.9,0); UpperArm 0.9×1.2×0.9
(±1.5,0.55,0); LowerArm 0.85×0.9×0.85 (±1.5,−0.5,0); Hand 0.8×0.4×0.8
(±1.5,−1.15,0); UpperLeg 0.9×1.2×0.9 (±0.5,−1.4,0); LowerLeg 0.85×0.9×0.85
(±0.5,−2.45,0); Foot 0.9×0.15×1.1 (±0.5,−2.93,−0.1).

### 4.2 Bone axes = Roblox joint axes

Every bone points straight up (+Z in Blender, tail = head + (0,0,0.25)) with
roll 0, so its local axes are exactly Roblox's (X right, Y up, Z back).
Pose bones use `rotation_mode = 'XYZ'` (and may use `location` for `Root`
only). Blender XYZ Euler means `R = Rz(γ)·Ry(β)·Rx(α)`. The Roblox Motor6D
`Transform` for that bone is therefore
`CFrame.new(loc) * CFrame.Angles(0,0,γ) * CFrame.Angles(0,β,0) * CFrame.Angles(α,0,0)`
— identical numbers, no axis conversion. (The exporter writes quaternions in
this joint space; see §8.)

Standard R15 rig attachments have identity orientation, so `Transform`
rotations act in character axes exactly as in Blender.

### 4.3 Sword grip

The sword asset is modelled with the grip centre at the origin and the blade
along Blender +Z (asset-local Roblox +Y), edge facing ±X.
Grip in the hand: `RightHand.CFrame * CFrame.new(0, -0.15, 0) * CFrame.Angles(-math.pi/2, 0, 0)`
(blade points forward along the hand's −Z when the arm hangs down, like a
Roblox tool). Blender uses the same offset for the Child Of constraint.

### 4.4 Avatar differences

Real avatars differ in size. The runtime offsets the root by
`(Humanoid.HipHeight + HRP.Size.Y/2) − 3.0` along the stage's up so feet land
where the mannequin's do. R6 avatars get a best-effort mapping (§7.2).

### 4.5 Pose library

`tools/blender/intro/poses.py`: `POSES = {name: {bone: (x°, y°, z°), ...}}`
(degrees, joint space, unlisted bones = 0) plus `ROOT_LOC` offsets where
needed, and helpers `key_pose(rig, frame, name, blend=None, jitter=0, seed=0)`.
Required poses: `stand`, `fall_spread`, `fall_tumble_a`, `fall_tumble_b`,
`look_around`, `look_up_reach`, `reach_right`, `flail_a`, `flail_b`,
`grab_blade`, `struggle_a`, `struggle_b`, `resonance_brace`,
`resonance_burst`, `sword_ready`, `swing_wind`, `swing_follow`,
`mount_crouch`, `surf_stance`, `brake_lean`, `brake_strain`, `stop_impact`,
`step_off`, `land_crouch`, `reach_sword`, `hold_sword_low`, `hero`.

---------------------------------------------------------------------------
## 5. Space backdrop (`tools/blender/intro/space.py`)

Deterministic (seeded) generation, used by the Blender preview *and* exported
to `IntroData.starfield`, so Roblox shows exactly the same sky.
Positions are Blender coordinates relative to `SkyAnchor`.

* **Stars**: 1600, on a shell r 850–960 (uniform on sphere, slight density
  boost in a galactic band). Each: position, size (0.6–3.2 studs, power-law,
  few big ones), colour (temperature: blue-white / white / warm),
  `appear` 0–1 (the `stars` channel value at which it starts to fade in over
  0.08), `twinkle` phase.
* **Galaxies**: 3. Each: centre, normal, radius (70–140), arms 2–4, twist,
  ~350 points with `from` (scattered cloud position) and `to` (spiral
  position, both relative to the centre in the galaxy's own frame), size,
  colour (core yellow-white → arm blue/pink), `delay` 0–0.3. Shown with
  channel `galaxies` g: point progress `u = smoothstep(clamp((g−delay)/0.7))`,
  position `lerp(from, to, u)` rotated about the galaxy normal by
  `(1−u)·twist` radians; brightness `u`.
* **Nebulae**: 8 soft clouds: centre, radius (120–260), colour (violet, deep
  blue, teal, magenta), `appear`. Shown with channel `nebula`.

---------------------------------------------------------------------------
## 6. Assets (`IntroAssets.fbx`)

Built by `tools/blender/intro/assets_intro.py` with `kit.py`
(`kit.Asset(name).bm(style)`, `kit.finish` adds markers; exported at 1/10 with
`exporter.export`). Pieces keep their object names in Studio, so runtime code
can find specific pieces by name (`<Asset>__<Style>[_n]`).

| Asset | Pieces (styles) | Size / notes |
| --- | --- | --- |
| `SpaceDome` | `Void` | Inverted (normals inward) UV sphere, r 1000 (diameter 2000 < 2048 limit), 32×16. |
| `SoulCore` | `CoreGlow` (inner orb r 0.8, tinted neon), `CoreShell` (faceted crystal shell r 1.3, glass), `CoreRing` (two thin orbit rings r 1.9, tinted neon) | Pivot = centre. |
| `ShatteredPlanet` | `Ocean`, `Land`, `LandDry`, `Ice`, `Cloud`, `Crust` (exposed rock face), `Magma` (glowing fracture surface), `PlanetCore` (glowing core sphere), `Debris` (30–50 rocks in a ring/arc where the missing half was) | Sphere r 320 with ~45 % carved away by a large offset sphere → crescent. Pivot = planet centre. Front (−Y) = the destroyed side. |
| `Rift` | `Crack_01`…`Crack_14` (each a thin jagged bright strip, style `Crack`), `Shard_01`…`Shard_16` (triangular glass shards filling the opening, style `Shard`), `RiftRim` (jagged torn ring, style `RiftEdge`), `RiftView` (disc inside the rim, textured with the forest seen from above, style `RiftView`) | Opening radius ~14 studs, lying in the Blender XY plane, facing +Z, pivot = centre. Crack segments ordered by distance from the centre so `crack` can reveal them progressively. Shards keep their own pivots (centroid) so the runtime can fling them. |
| `ResonanceSword` | `Blade` (steel, white-silver), `Crystal` (crystal inlays along the fuller + a crystal in the guard and pommel; colourless glass, tinted at runtime), `Guard` (dark metal + gold trim: styles `Guard`, `Gold`), `Grip` (wrapped leather) | Total length ~5.2 studs (blade 3.9). Grip centre at origin, blade along +Z. |
| `Shockwave` | `Wave` | Flat torus/ring, radius 1 (scaled at runtime), lying in XY. |
| `SlashArc` | `Arc` | Crescent ribbon, radius ~5, tapering ends. |

`RiftView` texture: `docs/intro/rift_view.png` (1024², rendered from the
generated map by `tools/blender/render_map.py`, view `rift_view` = straight
down onto the Sylverune clearing from ~900 studs). Embedded in the FBX
(`path_mode='COPY', embed_textures=True`). If Studio drops the texture, the
runtime falls back to `Config.RIFT_VIEW_IMAGE` (an image id the user can
upload) or a procedural green-blue swirl.

Styles (runtime colour/material; `Tint` = soul core colour):

| Style | Look |
| --- | --- |
| `Void` | Color 0,0,0, SmoothPlastic, CastShadow off |
| `CoreGlow`, `CoreRing` | Neon, Tint |
| `CoreShell` | Glass, transparency 0.35, white-ish tint blend |
| `Ocean` (28,70,140 SmoothPlastic), `Land` (70,120,60 Grass), `LandDry` (150,120,80 Sand), `Ice` (230,240,250 Ice), `Cloud` (245,245,250 SmoothPlastic, transp 0.15), `Crust` (70,55,50 Basalt), `Magma` (255,110,30 Neon), `PlanetCore` (255,220,140 Neon), `Debris` (85,75,70 Basalt) | planet |
| `Crack` | Neon white (230,240,255) |
| `Shard` | Glass (200,220,255), transparency 0.3, reflectance 0.3 |
| `RiftEdge` | Neon violet (190,140,255) |
| `RiftView` | keep imported texture, SmoothPlastic, no shadow |
| `Blade` | Metal (210,215,225), reflectance 0.2 |
| `Crystal` | Glass colourless (225,235,245) → Neon Tint as `resonance` → 1 |
| `Guard` (40,40,48 Metal), `Gold` (214,172,74 Foil), `Grip` (60,40,30 Fabric) | sword |
| `Wave` | Neon white→Tint, transparency from `opacity` |
| `Arc` | Neon Tint, transparency from `opacity` |

No collisions anywhere (CanCollide/CanTouch/CanQuery false), CastShadow off
for glow pieces.

---------------------------------------------------------------------------
## 7. Roblox runtime (`src/IntroCutscene`, a ModuleScript for ReplicatedStorage)

### 7.0 Public API

```lua
local Intro = require(game.ReplicatedStorage:WaitForChild("IntroCutscene"))
Intro.Play({
	color = Color3.fromRGB(120, 200, 255), -- soul core colour (required)
	onFinished = function() end,            -- optional
})                                          -- yields until the cutscene ends
Intro.IsPlaying() -> boolean
Intro.Finished -- RBXScriptSignal-like (BindableEvent.Event), fires with color
```

`Play` must be called from a LocalScript. Calling it while already playing
does nothing. In Studio only, pressing **F7** during a play test replays the
intro with `Config.TEST_COLOR` (for testing without the soul core screen).

When it finishes it fires the RemoteEvent `IntroCutscene_Finished` (created by
the server script) with the colour, so server code can give the real sword.
The included server script (`Server.server.luau`, `RunContext = Server`) does
that by default: builds a Tool from the `ResonanceSword` asset, tints the
crystals and equips it (`Config.GIVE_SWORD = false` turns it off).

### 7.1 Landing point (world origin)

`Config.LANDING`: `"auto"` (default) or a Vector3. Auto = the Sylverune
spawn circle: `ReplicatedStorage.IslandLayout.Landmarks.ForestSpawn` (X, Z)
moved 14 studs toward the hub (so the fall misses the floating crystal over
the circle), ground height by raycast (terrain + parts, ignoring characters);
fallback to the `IslandSpawn_Forest` SpawnLocation or the character's spawn.
At Play start the client calls `player:RequestStreamAroundAsync(landing)`
(pcall) so the forest is loaded before the world stage.

### 7.2 Modules

| Module | Job |
| --- | --- |
| `init` | API, main loop (`RunService.RenderStepped`), `Update(t)` = pure state-at-time function, marker dispatch (each marker fires once when `t` passes it), start/stop/cleanup (always restores everything, even on error). |
| `Config` | Settings (§7.5). |
| `IntroData` | Generated by the exporter. Never hand-edited. |
| `Convert` | Blender→Roblox math (§2): `pos`, `rotFromQuat`, `cf(stageOrigin, pos, quat)`, `assetCF(...)`. |
| `Timeline` | Sampling baked tracks at any `t` (§8): Catmull-Rom positions, slerp rotations, linear scalars, step channels for `visible`/`held`, never interpolating across `cuts`. |
| `Assets` | Client-side loader of `IntroAssets` (ReplicatedStorage, or Workspace as fallback) using the marker scheme; styles of §6; `Tint` colouring; procedural fallbacks when an asset is missing so the cutscene still works without the import. |
| `SpaceStage` | Builds the space stage at `SPACE_ORIGIN`: dome, stars, galaxies (point parts), nebulae (ParticleEmitters with the built-in smoke texture), planet, rift (cracks revealed in order by `crack`, shards flung outward and faded by `open`, rim + view scaled in by `open`), soul core + comet tail (Beams + Trail + sparkle emitter, length from `tail`), falling dust motes around the camera. `SkyAnchor` follows the camera every frame. |
| `WorldStage` | Sky rift, soul core (world part), sword (pieces, `resonance` colour blend, `glow`, `held` → grip weld to RightHand), blast sphere, slash arc, shockwave ring + dust, speed streaks, tree bending (§7.3), `workspace.GlobalWind` gust. |
| `CharacterRig` | Takes over the player's character: anchors HRP, stops/blocks animations (disables `Animate`, stops Animator tracks), disables controls, hides (`LocalTransparencyModifier`) during the space stage; each frame sets HRP CFrame and every Motor6D `Transform` from the data in `RunService.PreSimulation` (after the Animator, so it isn't overwritten); `form` → transparency + glow highlight; R6 mapping (`Root`·`Waist` → RootJoint, `Neck` → Neck, `*Shoulder` → `* Shoulder`, `*Hip` → `* Hip`, conjugated by each R6 C0 rotation); restores everything at the end and leaves the character standing at the final root position, unanchored. |
| `Screen` | ScreenGui (`IgnoreGuiInset`, DisplayOrder 100): cinematic bars (2.39:1 letterbox), black fades, colour flashes, impact frames, speed lines (Frames rotated around the centre with UIGradient taper — no image assets). |
| `LightingFX` | Saves and restores every Lighting property and post effect it touches. Space look: ClockTime chosen for side light on the planet, black ambient, strong Bloom (Neon glow), ColorCorrection, no Atmosphere/Clouds (disabled, restored after). World stage: back to the saved look + a slight warm ColorCorrection. Sets `Lighting:SetAttribute("CutsceneActive", true)` while playing (the map's `IslandAtmosphere` script pauses while it is set). |
| `Server.server.luau` | RemoteEvent + giving the sword (§7.0). |

### 7.3 Tree bending (shockwave wind)

Trees: models under `workspace.Island.Forest.Trees` (and any model with a
`Trunk`/`Bark` piece) within `Config.WIND_RADIUS` (320) of the landing point,
measured on the ground plane. For a tree at distance `d`, with `τ = t − t_wind − d / 160`:

```
f(τ) = 0                                          for τ < 0
f(τ) = (1 − e^(−τ/0.12)) · e^(−τ/1.1) · cos(2π·τ/1.6)   for τ ≥ 0
θ = A(d)·f(τ),  A(d) = 0.42 · clamp(1 − d/340, 0.15, 1)   (radians)
```

Rotate the tree about its base (pivot), axis = horizontal, perpendicular to
the direction from the landing point to the tree, tilting *away* from the
landing point. Restore the original pivot when τ > 4.5. Blender's preview
forest uses the same formula (keyframed), so renders match.

### 7.4 Impact frames

Anime-style two-tone frames, built entirely in the GUI (no image assets):

* A full-screen `ViewportFrame` (ZIndex below the bars) shows *silhouettes*:
  clones of the player's character (set `Character.Archivable = true` before
  cloning, restore after) and the sword, posed every frame like the real ones,
  seen through a `Camera` inside the ViewportFrame that copies the world
  camera's CFrame and FieldOfView.
* `impact:white` → `BackgroundColor3` white, `Ambient`/`LightColor` black and
  `ImageColor3` black: black silhouettes on white.
  `impact:black` → background black, models white (`Ambient`/`LightColor`
  white, `ImageColor3` white): white silhouettes on black.
* On top: 24–40 radial speed lines (thin Frames rotated about the screen
  centre, tapered with `UIGradient` transparency), opposite colour to the
  background, re-randomised every frame for a jittery hand-drawn feel.
* `impact:off` hides it all. A short `flash:*` normally follows.

### 7.5 Config

```lua
SPACE_ORIGIN = CFrame.new(0, 3000, 40000),
LANDING = "auto",                  -- or Vector3
LANDING_OFFSET_TO_HUB = 14,
WIND_RADIUS = 320,
GIVE_SWORD = true,
TEST_IN_STUDIO_KEY = Enum.KeyCode.F7,
TEST_COLOR = Color3.fromRGB(120, 200, 255),
RIFT_VIEW_IMAGE = "",              -- optional rbxassetid:// fallback for the rift view
SOUNDS = { ignite = "", whoosh = "", crack = "", rift = "", impact = "", resonance = "", shockwave = "", wind = "", land = "" },
ALLOW_SKIP = false,
```

---------------------------------------------------------------------------
## 8. `IntroData.luau` format

Generated by `tools/blender/intro/export_intro.py`. Plain Lua table, numbers
rounded (positions 0.001, quaternions 1e-5, scalars 1e-4).

```lua
return {
	version = 1,
	fps = 30,                -- Blender frame rate
	duration = 42.5,         -- seconds
	markers = { { t = 0.0, name = "bars:in:1.0" }, ... },   -- sorted
	cuts = { 18.6, 23.0, 26.5, 35.1, 38.0 },
	stageSwitch = 18.6,      -- time of "stage:world"
	tracks = {
		[name] = {
			stage = "space" | "world" | "camera",  -- camera: stage chosen by t vs stageSwitch
			rate = 30,       -- samples per second
			t0 = 1.5,        -- time of the first sample
			n = 256,         -- number of samples
			pos = { x1, y1, z1, x2, ... },         -- Blender stage coords (world space in Blender)
			rot = { w1, x1, y1, z1, w2, ... },     -- Blender world rotation quaternions (hemisphere-continuous)
			scale = { s1, s2, ... } | nil,          -- uniform scale (nil = always 1)
			channels = { glow = { ... }, visible = { ... }, ... },  -- one value per sample
		},
	},
	character = {
		rate = 30, t0 = 18.6, n = 718,
		root = { pos = {...}, rot = {...} },     -- CharacterRoot (HRP centre) like a track
		joints = { Root = { w,x,y,z, ... }, Waist = {...}, ... },  -- joint-space quats (§4.2)
		rootLoc = { x,y,z, ... },                 -- Root bone location (joint space), may be all 0
		channels = { visible = {...}, form = {...} },
	},
	starfield = {
		stars = { x, y, z, size, r, g, b, appear, phase, ... },   -- 9 numbers per star
		galaxies = { { center = {x,y,z}, normal = {x,y,z}, radius = r, twist = a,
			points = { fx, fy, fz, tx, ty, tz, size, r, g, b, delay, ... } }, ... },  -- 11 per point; from/to in the galaxy frame
		nebulae = { { center = {x,y,z}, radius = r, color = {r,g,b}, appear = a }, ... },
	},
	world = {
		windStart = 35.1,           -- seconds
		landingHeight = 0,          -- Blender z of the ground at the landing point
	},
}
```

Sampling rules (`Timeline`): sample index `i = (t − t0) · rate`; outside
`[t0, t0 + (n−1)/rate]` clamp to the end samples. Positions: centripetal
Catmull-Rom over samples i−1…i+2; rotations: slerp between i and i+1;
scalars: linear; `visible`/`held`/any channel whose name starts with `is` or
equals `visible`/`held`: step (value of sample `floor(i)`). If a cut lies
inside (sample(i), sample(i+1)], use the sample on the same side of the cut
as `t` (no blending across cuts).

The exporter also writes `tools/tests/intro_parity.json`: Blender-evaluated
values at 200 random sub-frame times (camera/sword/root pos + rot, a few
joints, a few channels) for the parity test (§9).

---------------------------------------------------------------------------
## 9. Verification

* `luau-analyze` clean (all of `src/IntroCutscene`).
* **Mock run** (`tools/tests/intro_driver.luau`): the Roblox mock gains the
  client APIs used (LocalPlayer with an R15 character, CurrentCamera,
  RunService signals + PreSimulation, GUI classes, post effects, Highlight,
  Beam/Trail/Attachment, Sound, ContextActionService/UserInputService
  stubs). The driver plays the whole cutscene with a fake clock at 60 Hz,
  asserts no errors and no mock warnings, checks that the character ends
  unanchored with controls restored, Lighting and Camera restored exactly,
  no leftover instances, and prints instance counts per stage.
* **Parity**: Luau `Timeline` vs `intro_parity.json` — position error
  < 0.05 studs (camera < 0.02), rotation error < 0.5°, scalar < 0.01.
* **Visual**: `tools/blender/intro/render_preview.py` renders the Blender
  animatic (stills at key times + an MP4 at 640×360). A runtime check renders
  what the Luau code builds at the same key times (mock dump → Blender, like
  `render_map.py`) to compare side by side.

---------------------------------------------------------------------------
## 10. Files

```
tools/blender/intro/
  rig.py            R15 mannequin + armature
  poses.py          pose library + keying helpers
  space.py          stars / galaxies / nebulae generation
  assets_intro.py   IntroAssets meshes
  scene.py          the cutscene: objects, keyframes, markers, camera
  export_intro.py   IntroAssets.fbx + IntroData.luau + parity fixture
  render_preview.py animatic stills + mp4
  build_intro.py    entry point: python tools/blender/intro/build_intro.py [--render]
assets/IntroAssets.{fbx,obj,blend}, assets/IntroScene.blend
src/IntroCutscene/  init.luau, Config.luau, IntroData.luau, Convert.luau, Timeline.luau,
                    Assets.luau, SpaceStage.luau, WorldStage.luau, CharacterRig.luau,
                    Screen.luau, LightingFX.luau, Server.server.luau
dist/IntroCutscene.rbxmx
docs/intro/  DESIGN.md (this), rift_view.png, previews
```
