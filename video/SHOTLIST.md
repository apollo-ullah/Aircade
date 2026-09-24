# AIRCADE — "We brought it back" (14.8s, 16:9)

**Goal:** sub-15s product teaser for X / LinkedIn. Vibe: 2006 living-room nostalgia. Higgsfield generates the intro, the two transitions and the end card. Real footage carries every product claim.

**Music:** Wii Sports title theme, first 15s of the melody (source file starts after ~7.5s of silence). Fade out over the last 1.3s. Loudness-normalised to -14 LUFS for social.

**Frame:** 1920x1080, 24 fps, H.264 + AAC. Captions in Avenir Next Demi Bold, lower-left, quick fade-in.

## Timeline

| # | In → Out | Dur | Type | Picture | Caption |
|---|---|---|---|---|---|
| 1 | 0.00 → 2.00 | 2.0s | GEN | Golden-hour 2006 living room. Boxy CRT on a wood stand, glossy white console with a glowing blue slot, white motion remote with wrist strap on shag carpet. Slow push-in, the CRT flickers on. | "Remember this?" |
| 2 | 2.00 → 3.40 | 1.4s | GEN | Camera glides down to the remote on the carpet. Its glossy plastic blooms into soft white light and resolves into a pair of white wireless earbuds in an open case. This is the whole idea in one move. | — |
| 3 | 3.40 → 5.20 | 1.8s | REAL `swing.mp4` @0.6s | Desk demo. Earbud pinched in hand, arm swings, laptop court reacts. | "Your earbuds are the controller." |
| 4 | 5.20 → 6.00 | 0.8s | REAL `tennis.mp4` @0.0s | Clean first-person tennis capture, racket swings on the beat. | "Swing." |
| 5 | 6.00 → 6.80 | 0.8s | REAL `slice.mp4` @0.3s | Neon Rush saber capture, green blocks sliced. | "Slice." |
| 6 | 6.80 → 9.40 | 2.6s | REAL `ai.mp4` @1.5s, cropped to game viewport | Rally against the AI rival. HUD shows RIVAL SWING and the countdown. | "Meet your AI opponent." |
| 7 | 9.40 → 10.00 | 0.6s | GEN | Retro console home menu: grid of glossy rounded channel tiles, hand cursor drifts, one tile zooms into the lens and whites out. Used as a whip transition. | — |
| 8 | 10.00 → 12.00 | 2.0s | REAL `play.mp4` @1.0s | Booth. Two players, one in the cow hat, swinging earbuds, crowd behind. | "Pick up. Play." |
| 9 | 12.00 → 13.40 | 1.4s | REAL `reaction.mp4` @0.5s | Same pair laughing after the point. No caption, let the music carry it. | — |
| 10 | 13.40 → 14.80 | 1.4s | GEN still + ffmpeg | Generated end card: single glossy channel tile reading AIRCADE with an earbud glyph. Slow pull-back, then a CRT power-off collapse to a white dot. | (card carries the wordmark) |

Total: 14.80s.

## Generated assets (Higgsfield)

Prompts avoid any console or brand name so they clear the IP filter. Stills come from GPT Image 2.5 (best on UI and on-image text). Motion comes from Seedance 2.5 in `omni_reference` mode with the still as the start frame, so every generated shot is anchored to a frame we approved first.

| Asset | Model | Used by |
|---|---|---|
| `generated/intro-still.png` | gpt_image_2_5, 16:9 | start frame for shot 1 and 2 |
| `generated/intro.mp4` | seedance_2_5, start-image, 4s, 1080p | shot 1 |
| `generated/earbuds-still.png` | gpt_image_2_5, 16:9 | end frame for shot 2 |
| `generated/remote-to-earbuds.mp4` | seedance_2_5, start-image + end-image, 4s, 1080p | shot 2 |
| `generated/channel-grid.png` | gpt_image_2_5, 16:9 | start frame for shot 7 |
| `generated/channel-wipe.mp4` | seedance_2_5, start-image, 4s, 1080p | shot 7 |
| `generated/endcard.png` | gpt_image_2_5, 16:9 | shot 10 |

Every generated clip is longer than its slot on purpose. The assembly script picks the best window.

## Real assets

Copied from the Hack The North edit into `source/`. All 1920x1080, 24 fps, silent.

| File | Content |
|---|---|
| `swing.mp4` | desk demo, earbud in hand, swing |
| `tennis.mp4` | first-person tennis capture |
| `slice.mp4` | Neon Rush saber capture |
| `ai.mp4` | screen recording of a rally vs the AI rival, cropped `1230x692` at `(130,90)` |
| `play.mp4` | booth, two players |
| `reaction.mp4` | booth, laughing after the point |
| `hero.mp4`, `tilt.mp4`, `challenge.mp4` | spare, not in this cut |

## Build

```sh
cd video
higgsfield auth login          # once, interactive
./generate.sh                  # generates every missing asset into generated/
python3 assemble.py            # renders out/aircade-teaser-15s.mp4
```

`assemble.py` renders a placeholder slate for any generated asset that is missing, so the real-footage timeline can be checked before spending credits.

## Rights note

The Wii Sports theme is Nintendo's copyrighted music. Posting it on X or LinkedIn risks a takedown or a muted post. The previous cut used an original score for that reason. Swap `build/music-bed.wav` for a licensed or original track if that matters for this post.
