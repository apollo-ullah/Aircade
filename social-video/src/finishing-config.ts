/**
 * Editable finishing controls for the Aircade social cut.
 *
 * The source windows, shot order, composition length, and playback timing remain
 * fixed in video.tsx. These values only control presentation.
 */
export const finishing = {
  grade: {
    human:
      'brightness(.93) contrast(1.12) saturate(.93) sepia(.025)',
    gameplayForeground:
      'brightness(.97) contrast(1.08) saturate(.96)',
    gameplayBackground:
      'blur(34px) brightness(.39) contrast(1.08) saturate(.98)',
    endCard:
      'brightness(.7) contrast(1.08) saturate(.92) sepia(.02)',
    grainOpacity: 0.038,
    vignetteOpacity: 0.34,
  },
  transitions: {
    frames: 8,
    pushPixels: 16,
  },
  captions: {
    fontSize: 70,
    bottom: 78,
    maxWidth: 1260,
    background: 'rgba(3, 8, 15, .74)',
    accent: '#39d8ff',
    reactionAccent: '#ffd43b',
    cues: [
      {from: 15, duration: 34, lines: ['LIKE THIS.'], emphasis: 'THIS.', reaction: true},
      {from: 55, duration: 32, lines: ['OH, YEAH.'], emphasis: 'YEAH.', reaction: true},
      {
        from: 172,
        duration: 47,
        lines: ["HE'S RETURNING", 'THE BALL.'],
        emphasis: 'RETURNING',
      },
      {
        from: 230,
        duration: 34,
        lines: ['YOU HAVE TO', 'LOCATE IT'],
        emphasis: 'LOCATE IT',
      },
      {
        from: 266,
        duration: 20,
        lines: ['TO THE OTHER SIDE.'],
        emphasis: 'OTHER SIDE.',
        bottom: 250,
      },
    ],
  },
  audio: {
    roomVolume: 0.9,
    impactVolume: 0.56,
    confirmVolume: 0.54,
  },
} as const;
