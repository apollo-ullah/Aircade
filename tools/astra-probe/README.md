# Astra Phase 0: screenshot/action probe

This isolated tool checks whether **your OpenAI API account** can run `gpt-6-astra` with the `computer` tool, and measures completed-request and screenshot-to-input latency. It does not modify or drive the running Mac game.

The browser shows a recorded SceneKit Tennis court plus a random yellow target and a mouse-controlled racket. Astra receives only screenshots and instructions. Its actual computer-tool actions are executed through Playwright. The resulting screenshot is sent back for confirmation. Three independent trials run with at most nine requests total, 1,536 output tokens per request and a 45-second request timeout. There are no automatic API retries or model substitutions.

## Setup and commands

Run from the repository root:

```sh
npm ci --prefix tools/astra-probe
npm test --prefix tools/astra-probe
npm run check --prefix tools/astra-probe
npm run preview --prefix tools/astra-probe
```

The harness uses installed Google Chrome on macOS with an isolated temporary browser profile. Alternatively, set `AIRCADE_CHROME_PATH` to your Chrome binary or install Playwright Chromium from this directory with `npx playwright install chromium`.

Add `OPENAI_API_KEY` to the ignored repository-root `.env` file, or export it in the shell. A Baseten key or Codex login does not replace an OpenAI API key. The runner reads only that variable and never executes the `.env` file.

```sh
npm run probe --prefix tools/astra-probe
# Optional: show the isolated browser while the same API probe runs.
npm run probe --prefix tools/astra-probe -- --headed
```

The self-test uses known coordinates, makes **no API calls**, and is explicitly labelled scripted. It verifies the harness only. The live mode provides no DOM or target coordinates to the model. Coordinates in the target fixture are read by the harness to set up and verify trials, not sent in API requests.

## Evidence

Every run writes `.local/astra-probe/<timestamp>-<mode>/report.json`, `report.md`, and before/after screenshots. Reports include API response IDs, actual usage returned by the API, action traces, failed requests, and completion timing. They contain no API key and do not retain model reasoning. Evidence is ignored by git.

Token charges are an **estimate** using standard short-context rates documented on September 19, 2026, excluding any additional tool charges. Failed requests can have unknown usage. A $1 estimated-token stop between requests plus the hard request/output caps bounds the experiment; it is not a guaranteed billing limit.

The included `court.png` is an unmodified recorded native game capture from `build/opponent-tennis-smoke/tennis-play-scene.png`. The target overlay is a Phase 0 fixture, not a simulated successful Tennis return. Live tennis, physics, AirPod input and racket interception are Phase 1/2 work.

## Interpretation

- **Self-test passed:** browser, target input and screenshots work locally. Astra has not been tested.
- **Live passed:** three screenshot/action/screenshot cycles completed and the target was actually clicked. This establishes API/tool access and static input capability only.
- **Blocked:** missing credentials; add the key and rerun.
- **Failed:** inspect the report for provider access, unsupported actions, deadline or confirmation failure. Never relabel a scripted check as a live result.

Compare screenshot-to-action latency with the native game's seconds-long ball flight. A static probe cannot establish reaction accuracy or reliable live rallies. Tiny-sample median/p95 values are descriptive only.

References: [OpenAI computer use](https://developers.openai.com/api/docs/guides/tools-computer-use), [Astra model and pricing](https://developers.openai.com/api/docs/models/gpt-6-astra).
