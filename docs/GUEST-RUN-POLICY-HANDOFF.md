# Guest and result policy integration

Packet B implements policy/storage only. The coordinator still owns the game callbacks, local-best writes, and guest/profile presentation.

## Callback contract

At the beginning of a real game, retain the ID returned by:

```swift
let context = players.beginRun(game: .neonRush, mode: game.difficulty.rawValue,
                               simulated: isDemo)
// Tennis: game: .tennis, mode: "Tennis"
// Duel: game: .saberDuel, mode: "Versus"
runID = context.id
```

`RunContext` captures the game/mode, optional profile ID/name/visibility, optional local avatar ID, and a unique run ID. It contains a snapshot, so changing profiles or selecting Guest afterward cannot change that run's owner. A newly started guest run never acquires an owner retroactively.

For every accepted input frame, before evaluating collisions or recording results:

```swift
players.observeInput(simulated: frame.simulated, runID: runID)
```

Simulation is irreversible for a run. Also keep the game's own `isDemo` flag latched so standalone game tests and result presentation remain honest. A later real frame cannot restore record eligibility.

On results, finish policy **before** saving a local best, and use the returned decision:

```swift
let completion = players.finishRun(state, demo: isDemo, runID: runID)
let mayWriteLocalBest = completion?.eligibleForLocalBest ?? false
// Tennis: finishTennis(state, demo: isDemo, runID: runID)
// Duel: finishLocalRun(runID: runID, simulated: isDemo)
```

Finishing consumes the context. A duplicate callback returns `nil` and queues nothing. `canRecordLocalBest(for:)` is available **while** a run is active; after finish, use the completion instead. Only `.results` states are accepted by the Neon Rush and Tennis adapters. Failed rounds are legitimate results; the API's `completed` field retains its existing survived-to-timeout meaning.

On game leave/cancel, call `players.abandonRun(runID: runID)` and clear the adapter's retained ID. Always pass an explicit retained ID to production observe/finish/abandon callbacks; the optional ID exists for backward compatibility and cannot distinguish late callbacks on its own. A callback for another ID cannot finish, abandon, or taint the active run.

The old `beginRun(demo:)` remains compile-compatible for the original Neon Rush callback. Migrate both games to the explicit game/mode overload; Tennis must not use that legacy entry point.

## UI and storage behavior

- `authorize()` always returns true immediately. Profile configuration/server access never gates start.
- `selectGuest()` / `logout()` clear the selected profile and personal best display for future games. They preserve an already running round's owner; leave/cancel is a separate action.
- Keep badge sign-in optional. A late sign-in/profile response cannot override a subsequent Guest selection.
- Guest results may update local Mac bests, but never enter `pending-runs.json` or the public API.
- Real badge results retain their start-time owner, persist to the existing queue, and retry using the same run ID/payload. Private profiles still save personal scores; this code does not change public opt-in.
- Simulated results update neither real local bests nor profile scores, including runs that become simulated midway.
- Duel results remain local: the existing station API accepts only Neon Rush and Tennis scores. No backend schema/API was expanded.

## Verification

`swift test --filter PlayerSessionTests` covers guest/no-server start and results, no retroactive guest upload, profile switches/logout, immutable identity/visibility, late sign-in, simulation at start/midrun/finish, duplicate results, abandoned/late callbacks, wrong-game and nonterminal callbacks, local duel results, persistence across restart, offline retry, and unchanged public opt-in.

Tests inject an HTTP transport, fake configuration, and temporary queue directory. They never read station credentials, use a real badge, contact a real server, or write the user's score queue. MongoDB itself is not exercised by this packet.
