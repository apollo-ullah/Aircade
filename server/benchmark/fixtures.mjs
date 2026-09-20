import { legalShots, canonicalState, stateHash } from '../providers/contract.mjs';

// Versioned synthetic states, frozen before any calls. They cover opening,
// sustained rallies, misses, five previous targets, and incoming/idle phases.
// They are not measured hardware samples or a labelled tactical-quality dataset.
export const fixtureVersion = 'five-lane-states-v1';
export const fixtures = Object.freeze(Array.from({ length: 20 }, (_, index) => {
  const body = {
    difficulty: 'rival', score: [0, 480, 1440, 3600][Math.floor(index / 5)],
    misses: Math.floor(index / 5), longestRally: [0, 2, 6, 12][Math.floor(index / 5)],
    incomingBallX: index < 5 ? null : [-3.1, -1.55, 0, 1.55, 3.1][index % 5],
    opponentAttemptX: index < 5 ? null : [-2.3, -1.55, 0, 1.1, 2.9][index % 5],
    previousReturnX: index === 0 ? null : legalShots[(index + 2) % 5].targetX,
    candidates: legalShots.map(shot => ({ ...shot }))
  };
  const state = canonicalState(body);
  return Object.freeze({ id: `state-${String(index + 1).padStart(2, '0')}`, body, inputHash: stateHash(state) });
}));
