# Wii-style system shell for Aircade

- **Date:** 2026-09-19
- **Branch:** `wii-shell` (worktree at `../Aircade-wii-shell`, branched from `2be0b85`)
- **Status:** Design approved, ready for implementation planning

## Problem

Aircade is a Wii spinoff, but its interface is not one. The current build opens
straight into a single-screen launcher that also doubles as the gameplay HUD
(`NeonRushView`), and navigation is a two-way boolean switch in `ContentView`
between that launcher and the training lab. A recent restyle (`2be0b85`) moved
the palette toward Wii Sports — white panels, blue controls, light background —
but it is a modern Mac app wearing a sports colour scheme, not a recreation of
the Wii's system software.

We want the Wii *system menu* experience: a channel grid you point at with the
controller, avatars you build and that the games then use, and the sound and
motion vocabulary that made the original feel like a console rather than an
application.

## Goals

- A channel-grid home screen that replaces the current launcher.
- A hand cursor driven by the AirPod, with the mouse as an equal fallback.
- A parts-based 3D avatar creator whose output the games display.
- A single design system that every existing screen adopts.
- Synthesized interaction audio in the Wii's register.
- Zero change to game logic, motion mapping, collision, scoring, or timing.

## Non-goals

- No online features, no account system, no avatar sharing.
- No rework of the motion pipeline, calibration maths, or game rules.
- No Nintendo assets, fonts, audio, or trademarks (see Asset policy).
- No rewrite of the training lab's diagnostics panel beyond adopting the theme.
  It is a developer surface; it gets the palette, not a redesign.

## Decisions

Settled during brainstorming, with the reasoning that drove each one.

| Decision | Choice | Why |
|---|---|---|
| Build strategy | Shell-first, restyle existing screens in place | The prior restyle funnelled styling through one 35-line file, so its plumbing is reusable; a clean-room rewrite would put calibration and the smoke-test capture paths at risk simultaneously |
| Home layout | Large channel tiles with animated banners, no empty slots | Better use of a 1340×900 window than a literal 4×3 with six dead sockets |
| Grid size | 3×2 | Six channels exactly. Diagnostics is already a tab inside the training lab rather than a screen of its own, and Settings belongs on the corner button as it does on a Wii |
| Corner button | Lowercase italic `air` | Reads as a wordmark, fits the pill, legible at 38pt |
| Cursor input | Motion with mouse fallback, one cursor model | Every screen works with or without a controller, which also keeps headless capture working |
| Activation | Flick while hovering | Reuses `SwingDetector`'s tuned hysteresis and cooldown, and matches the swing vocabulary the game already teaches |
| Avatars | Full parts-based creator, rendered in SceneKit | "Same avatar style" requires real part variety and a head that turns |
| Editor layout | Wii-faithful: category strip, preview plus sliders, paged part grid, colour row | Every control stays visible at once, which matters when aiming a drifting pointer |
| Audio | Synthesized effects; music as a pluggable local file | Carries the feel without shipping copyrighted recordings |

## Asset policy

Everything ships original. The palette, proportions, gloss, corner radii, avatar
construction, and sound design are recreated to match the Wii's design language;
no Nintendo graphics, fonts, audio, or marks are bundled or downloaded. The
music slot reads any file the user places in `Resources/Music/`, which is
gitignored and never committed; when absent, a synthesized original plays.

## Architecture

### Module layout

Two new homes for pure logic, so the parts that can break invisibly are testable.

- **`AvatarCore`** (new SwiftPM target, no SwiftUI/SceneKit): `Avatar` value
  type, the part catalog, clamping rules, and `AvatarStore` persistence.
- **`MotionCore/Pointer.swift`** (added to the existing target): `PointerTracker`,
  a pure struct beside `OrientationTracker`, turning orientation into a screen
  point.

Both get unit tests. Cursor drift and a corrupt saved avatar are exactly the
failures a screenshot cannot catch.

### New files in the `Aircade` target

| File | Responsibility |
|---|---|
| `WiiTheme.swift` | Palette, gradients, gloss, radii, hairlines, type scale, `WiiButtonStyle`, panel and tile modifiers. Replaces `SportsTheme.swift` |
| `WiiShell.swift` | Root container: owns `Route`, the bottom bar, and channel open/close transitions |
| `ChannelGrid.swift` | The 3×2 home screen and its animated tile banners |
| `PointerModel.swift` | `ObservableObject` publishing one cursor point and hover target from either motion or mouse |
| `WiiCursorView.swift` | Hand cursor overlay and hover affordances |
| `AvatarScene.swift` | Builds a SceneKit head from an `Avatar`, rebuilding only changed features |
| `AvatarEditorView.swift` | The creator: category strip, live preview, sliders, paged part grid, colour row |
| `AvatarChannelView.swift` | Gallery of saved avatars; create, edit, delete, set favourite |
| `WiiAudio.swift` | Synthesized interaction effects and the optional music slot |

### Modified files

- `AircadeApp.swift` — `ContentView` delegates to `WiiShell`; command-line flags
  resolve to an initial route.
- `NeonRushView.swift` — loses its launcher; keeps countdown, HUD, pause, and
  results, restyled. This is the largest structural edit and the most likely
  merge conflict.
- `MotionModel.swift` — `showLab(_:)` becomes a shim onto the route; no other
  behavioural change.
- `CalibrationGuide.swift`, `SimpleCalibrationGuide.swift`,
  `ScriptedControllerSetup.swift`, `TrainingArena.swift` — adopt `WiiTheme`.
- `SportsTheme.swift` — deleted once all references move.

## Design system

Concrete values, so the look does not drift between screens.

```
Stage background   radial #FFFFFF → #EEF4F8 → #D7E3EC
Panel face         linear #FFFFFF → #E8F0F6
Hairline           #CCD9E3
Accent             #3FB6E8;  active fill #5EC8F0 → #2B93CC
Ink                #46596A;  secondary #6B8698
Bottom bar         #F4F8FB → #DBE6EE, top hairline #C3D2DD
Radii              tiles 18, panels 12, buttons full pill (height ÷ 2)
Gloss              top 46% of a surface: rgba(255,255,255,.90) → rgba(255,255,255,.20)
Elevation          0 2px 5px rgba(30,70,100,.10) + inset 0 1px 0 #FFF
```

Type uses **SF Pro Rounded** for channel names, headings, and buttons, with
standard SF Pro for body copy and all numeric/diagnostic text. This deliberately
reverses part of `2be0b85`, which replaced rounded display type with system
type. That was the right call for a Wii *Sports* look; the Wii *system menu* is
soft and rounded, and the reversal is intentional rather than accidental.

## Navigation

```swift
enum Route { case home, neonRush, duel, avatar, controller, lab, scripts, settings }
```

`WiiShell` owns the current route and renders the bottom bar on every screen:
the `air` corner button, the storage button, live controller status, and a
clock. Opening a channel zooms the tile into the screen; closing reverses it.
The `.duel` case exists from day one even though the multiplayer work has not
landed yet, so integrating it later is adding a tile rather than restructuring.

### Channels

Six tiles: Neon Rush, Saber Duel, Avatar, Controller, Training Lab, Scripted
Tests. Each banner animates — drifting blocks for Neon Rush, two crossed blades
for Saber Duel, a turning head for Avatar, the live angular-speed sparkline for
Training Lab.

Diagnostics is deliberately not a channel. It is already a segmented tab inside
`ArenaLayout` alongside "Play & calibrate", not a screen of its own, and
promoting it would mean inventing a surface that does not exist. Settings is
likewise not a tile: the `air` corner button opens it, which is both where a Wii
puts it and what keeps the grid at six.

## Pointer

`PointerTracker` consumes `MotionModel.saber` — already reference-relative,
grip-corrected, and smoothed — rather than raw attitude. Grip calibration and
recenter (R) therefore apply to the menu for free, and pointing the earbud
behaves the same way in a menu as it does in a game.

- Yaw maps to x, pitch to y, clamped at the edges. Default sensitivity spans the
  window width across ±22.5° of yaw and its height across ±13° of pitch, tunable
  in Settings.
- A 0.35° dead zone around the current point suppresses jitter without feeling
  sticky.
- `PointerModel` publishes one point. Motion drives it while a controller is
  live; when tracking is off or `sampleAge` exceeds 0.5 s it switches to the
  mouse silently. That threshold is not new — 0.5 s is already what the app
  treats as stale everywhere else, including the recenter button's enabled state
  and the lab's input hint. Views never learn which source is active.
- Channels publish their frames through a SwiftUI preference key; `PointerModel`
  hit-tests against them, so hover and selection are identical for both sources.
- Selection is a flick while hovering, via `SwingDetector`. Space and mouse click
  do the same thing everywhere.

## Avatars

### Model

```swift
public struct Avatar: Codable, Equatable {
    public var schemaVersion: Int
    public var nickname: String
    public var favouriteColor: Int
    public var skinTone: Int
    public var faceShape: Int
    public var hair, eyebrows, eyes, nose, mouth: Feature
    public var glasses, facialHair: Feature?
    public var height, weight: Double        // 0...1
}

public struct Feature: Codable, Equatable {
    public var index: Int
    public var colorIndex: Int
    public var size, verticalPosition, spacing, rotation: Double   // 0...1, clamped
}
```

Catalog sizes: 8 face shapes, 32 hairstyles, 24 eyebrow shapes, 48 eye shapes,
12 noses, 24 mouths, 20 glasses, 6 facial hair, 12 favourite colours, 6 skin
tones. Catalog indices are append-only and pinned by test, so adding parts later
cannot silently change the appearance of an avatar someone already saved.

### Rendering

The head is a scaled sphere; features are flat shapes drawn as Core Graphics
paths into textures and applied to slightly curved planes positioned on the
face. That is the Mii construction — flat features on a smooth 3D head — and it
keeps part authoring to vector code rather than 3D assets. `AvatarScene` diffs
the incoming `Avatar` against the last one and rebuilds only the features that
changed, so dragging a slider does not rebuild the head every frame.

### Persistence

`AvatarStore` writes JSON to the same Application Support directory
`MotionModel` already resolves, honouring `AIRCADE_LOG_DIRECTORY` so smoke tests
stay hermetic. It holds multiple avatars and a favourite. The favourite appears
on the Avatar channel tile and, once multiplayer lands, over each player's score
in the Saber Duel HUD.

## Audio

`WiiAudio` synthesizes hover, click, channel open, channel close, and save
sounds into buffers at startup and plays them on a dedicated `AVAudioEngine`,
following the pattern `GameAudio` already uses to stay off the motion and render
path. Music is optional and loops if present.

## Compatibility and error handling

The command-line flags are the binding constraint. `GameSmoke` and
`ScriptedGameCheck` drive the app headless, capture bitmaps of the first
window's content view, and assert on game state; a new root shell sits directly
in their path. `WiiShell` therefore resolves an initial route from
`CommandLine`, jumping straight into the relevant channel and skipping home.
`motion.showLab(true)` keeps working as a shim onto `.lab`.

Rules that prevent the pointer from trapping anyone:

- No screen is reachable only by pointing. Mouse and keyboard reach everything,
  which is also what keeps headless capture working.
- Losing the controller mid-menu drops to the mouse and shows a hint in the
  bottom bar. It never freezes or blocks.
- Opening a channel pauses a running game, matching existing sheet behaviour.
- Flick-to-select is suppressed for 500 ms after the pointer re-acquires input,
  and the cursor jumps to the new pose rather than sweeping to it. This mirrors
  the existing rule that the first returning pose cannot score a connecting
  slash; without it, the flick made while reconnecting would sweep the cursor
  across the grid and open whatever it landed on.
- Unreadable, corrupt, or newer-schema `avatars.json` loads a default avatar and
  appends a line to the existing events log. It never crashes and never applies
  a partially-decoded avatar.

## Testing

- **`PointerTracker`**: axis mapping, edge clamping, dead zone, recenter reset,
  stale input reported as lost.
- **`AvatarCore`**: encode/decode round trip, out-of-range sliders clamp, corrupt
  JSON falls back to default, catalog indices pinned.
- **Existing 20 tests**: the regression signal. They cover game logic, so a
  genuinely presentation-only change leaves them green without edits.
- **Smoke flags**: re-run `--smoke-test`, `--game-smoke-test`,
  `--scripted-game-test`, and `--scripted-repro` to confirm the shell did not
  break automated capture.

## Integration with the multiplayer work

Uncommitted work in the main checkout adds a two-player Saber Duel and an iOS
companion controller (`ControllerLink`, `iOS/AircadeController.xcodeproj`),
touching `AircadeApp.swift`, `NeonRushView.swift`, `MotionModel.swift`, and
`Package.swift`. This branch was cut from `2be0b85` into a separate worktree so
that work is untouched.

Expected conflicts on rebase, and how each resolves:

- `Package.swift` — both sides add targets; additive, trivial.
- `AircadeApp.swift` — their three-way `ContentView` switch is replaced by the
  shell's route; their `.multiplayer` branch becomes `Route.duel`.
- `NeonRushView.swift` — their Saber Duel header button is removed, because
  Saber Duel becomes a channel.

## Out of scope for this spec

Rendering the channel grid in SceneKit for true 3D tile wobble and zoom. The
grid's tile rendering will be kept behind a small interface so this can be
swapped in later as a contained follow-up if the SwiftUI version feels flat.
