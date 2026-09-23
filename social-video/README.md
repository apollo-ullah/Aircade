# Aircade social video

Renders a 12-second, 16:9 LinkedIn video from the supplied Hack the North footage.

```bash
npm install
npm run render:final
```

Final output: `out/aircade-social-final.mp4`

Editable finishing controls are in `src/finishing-config.ts`. Caption text and
timing, grade intensity, transition duration, and mix levels can all be changed
there without touching the fixed clip order or source windows.

The pipeline keeps these useful intermediates:

- `public/room-audio-mastered.wav` — reversible dialogue cleanup; the original
  `room-audio.m4a` remains untouched.
- `out/aircade-social-mezzanine.mp4` — high-quality CRF 14 picture before the
  final audio loudness pass.

The two sound effects are Kenney CC0 assets. The room audio comes from the supplied event footage.
