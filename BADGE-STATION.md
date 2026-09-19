# Local badge station (MongoDB)

## Start

Requires macOS 14+, Node.js 20+, and MongoDB Community (`mongod`). MongoDB is already installed on the development Mac.

```sh
cd ~/dev/repos/Aircade
./scripts/start-station.sh
```

Keep that Terminal open. The script uses an existing MongoDB listener on port 27017, or starts one bound to loopback with data in `.local/mongo`. It installs locked npm dependencies and starts the API on port 8787. The database is `aircade`; it does not modify other databases. Closing the API does not stop MongoDB.

In another Terminal:

```sh
cd ~/dev/repos/Aircade
./scripts/run.sh
```

Open http://127.0.0.1:8787 for the leaderboard. The app's trophy button opens it too.

## Player flow

1. Choose **Scan badge** (or **Scan badge to play**), select a camera, and press **Start camera**. Show the badge QR. Manual/pasted code entry is available for testing or an external USB scanner.
2. A stable QR maps to the same player. First scan creates a generated nickname and private profile; edit the nickname and opt in to appearing publicly if desired.
3. Save the profile, connect/recenter the station's AirPods controller, and play. The app keeps the hand-tracking camera separate from badge scanning: existing hand tracking stops during sign-in and restarts after dismissal.
4. Finished physical rounds save score, difficulty, cuts, best combo, accuracy and completion status. Demo/scripted runs never upload. Ending a round early does not submit it.
5. **Next player** clears the selected profile and reopens sign-in. **Play again** retains the current player. The player ID is captured at round start so later profile changes cannot misattribute a result. Keyboard-start also requires sign-in for physical play.

A camera is only opened after pressing Start camera. Frames are processed locally, never saved or sent to the API. We still need a physical Hack the North badge test to confirm its QR is stable; no assumptions are made about the QR containing names or an organizer login token. The full QR text is an opaque code. It is not opened as a URL. There is no badge software to install.

## Storage and configuration

- MongoDB `players`: opaque ID, server-keyed badge digest, nickname, visibility, creation time.
- MongoDB `runs`: unique run ID, player ID, scores, difficulty, station ID, version and server receipt time.
- Raw QR payloads are SHA-256 hashed on the Mac and HMAC-keyed by the server before storage. They are not logged, persisted or exposed publicly. Keep `.local/station.json` backed up alongside MongoDB: its badge secret is required to recognize returning badges.
- `.local/station.json` is generated once with a private station bearer token, URL and identity. It is ignored by Git and owner-readable. The built app in `build/Aircade.app` locates this beside the repo. If moving the app elsewhere, set `AIRCADE_STATION_CONFIG` to that file's absolute path when launching it.
- Pending run uploads are atomically queued at `~/Library/Application Support/Aircade/pending-runs.json` and retried every 15 seconds, including after restart. Unique run IDs make retries idempotent. New badge recognition requires the local server/MongoDB to be available; a running round can finish and queue its score if they go down.
- Change `MONGODB_URI` / `MONGODB_DB` on the API server to select a different database. Avoid switching databases while uploads are pending.

The station token authorizes profile edits and score submissions. Browser clients have read-only access to the public leaderboard, which exposes only opted-in nicknames, rank and score statistics. Best scores are grouped by player, with separate Chill and Arcade boards; ties use the earliest server receipt time. Static QR recognition is convenient identification, not strong authentication. Anyone holding a copy of a badge code at an authorized station can impersonate its owner. Scores are trusted station submissions, not cryptographic proof of gameplay.

## Sharing the leaderboard

Default binding is **127.0.0.1**: the page is available on this Mac, not the public internet. For a trusted venue LAN, start the API with `HOST=0.0.0.0 npm start` from `server/`, then viewers can visit `http://MAC_LAN_IP:8787`. Keep MongoDB bound to loopback. Do not publish the MongoDB port, station configuration or bearer token. A genuinely internet-public board needs HTTPS hosting or a tunnel pointed at the HTTP API; no public deployment is performed by these scripts.

## Verification

`cd server && npm test` uses a uniquely named temporary MongoDB database and port 8788. It tests returning and simultaneous sign-ins, consent/privacy, separate difficulties, per-player bests, station authorization, invalid/demo rejection, and idempotent/conflicting run IDs. It drops only its own generated test database afterward.

The native Swift build is checked separately. Physical badge recognition, AirPods and camera handoff must be tested with real hardware. Existing XCTest suites require full Xcode, unavailable in the currently selected command-line toolchain.

## Sample leaderboard data

To add three clearly labeled test profiles and seven completed runs to the local `aircade` database:

```sh
cd ~/dev/repos/Aircade/server
npm run seed
```

The command is safe to run repeatedly. In MongoDB Compass, open the `aircade` database and inspect the `players` and `runs` collections. Every sample record has `metadata.fixture: "leaderboard-demo-v1"`; run metadata also describes the test scenario. The fixture deliberately gives one player two Arcade results so the API can demonstrate that it returns the higher personal score rather than the most recent record.

Remove only these sample records, leaving scanned profiles and real runs intact, with:

```sh
npm run unseed
```

`./scripts/check-station-client.sh` (after a release build on Apple Silicon) additionally compiles a standalone Swift client check. It exercises the actual `PlayerSession` against an isolated test database: recognition, sign-in gating, demo exclusion, player identity captured at start, offline queue persistence, restoring/retrying after restart, and per-player bests. This check runs without XCTest or physical hardware. Both server and native client checks passed during implementation.

## Badge name OCR

Camera sign-in looks for one QR code, then runs local Apple Vision text recognition on the small area immediately below it. Keep the QR **and the displayed name** visible. A sufficiently confident 2–24 character name is offered in the profile form; it is not sent to the server until the player confirms with Save. Glare, unreadable text, unusually long names or multiple QR codes require adjusting the badge or typing a nickname. Emails, badge-ID labels and menu text are rejected. The manual code path continues to work without OCR.

Confirmed profiles keep their saved nickname on later scans. Older generated placeholder profiles can still receive a name suggestion; existing customized nicknames are preserved. There is no organizer lookup, email collection, or badge app. Synthetic client checks cover suggestions, explicit confirmation, returning-name preservation and rejected text; physical OCR quality still needs an actual camera/badge trial.
