# Wii-style demo audio library

577 audio files: 487 effects/voice cues, 86 jingles, and 4 complete music tracks.

Open index.html in a browser to search and audition files. Only one sound plays at a time. Original files are in music/ and packs/; ZIP backups are in archives/. manifest.json lists all audio files and licenses.

Suggested starting points:
- Lobby / menus: Local Forecast (publisher describes this as a clean loop).
- Quirky waiting screen: Local Forecast - Elevator.
- Friendly gameplay: Carefree.
- Comic minigames: Monkeys Spinning Monkeys (publisher describes this as loopable).
- Menu navigation: interface-sounds and ui-audio.
- Collision / hit / landing: impact-sounds.
- Score feedback / arcade actions: digital-audio.
- Countdown / round announcements: voiceover-pack and voiceover-pack-fighter.
- Wins / losses / results: music-jingles.

Keep the music credits from CREDITS.md in your game credits. Kenney packs are CC0. These are reusable alternatives, not Nintendo soundtrack recordings. The full library is stored in the main Aircade worktree. Local Forecast.mp3 is also staged in build/Resources/Music/ in Aircade-integration and Aircade-wii-shell, matching their existing WiiAudio.startMusic() lookup beside build/Aircade.app. Those builds can use it for home-screen music when audio is enabled. Sound effects have not yet been mapped into gameplay. Playback in the app has not been verified.

Validation: archive integrity checked, OGG signatures verified, and all four MP3 tracks parsed with ffprobe. The library has not been individually auditioned in full.
