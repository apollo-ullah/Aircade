## Your earbuds are the controller. Astra is the opponent.

**We turned an AirPod into a Wii-style motion controller—and used the arcade we built to explore whether an AI could play along.**

Pick up an earbud. Tilt it to navigate the menu. Swing it like a tennis racket. Challenge an AI rival, slice through Neon Rush, or pair an iPhone for a two-player saber duel.

Our starting point was a piece of hardware people already carry. Our question became: **what happens when a human holding an earbud and an AI operating software meet on the same tennis court?**

## Why OpenAI

We wanted to explore intelligence through play: choosing where to return a ball, acting through an interface, and making decisions while a physical game keeps moving.

OpenAI gave us two ways to investigate that idea. The Responses API lets Astra make a constrained, inspectable tactical choice that changes the next shot. Codex helped us build and test the native system, and its computer-use capabilities let us explore a second interface to the game: seeing the window and operating the rival's visible controls.

**The creative loop is that our development assistant also became a participant in the world it helped us build.** The arcade is both something people can play and an environment for exploring how AI acts.

## How we use the OpenAI API

In the integrated judging build, selecting **Astra · OpenAI API** sends game state and five legal return options through our local Node station to **GPT-6 Astra using the OpenAI Responses API**. A strict output schema restricts the answer to a supplied shot ID. That selection determines the return's target, flight duration, delay, and stroke.

The native game handles movement, animation, and racket-ball contact. Requests run asynchronously, so inference does not stop the court. If a refresh fails, a previous genuine model decision can be reused with a visible **Cached** label. Paused or abandoned requests cannot replace the current run's decision.

The **AI shot decisions** panel makes the integration inspectable: judges can see the input summary, latest selection, shot actually applied, request timing, and observation/decision IDs. An API response and an on-court action are tracked separately.

## The computer-use experiment

We also gave Codex the visible game window. In this mode, it can move the far-side player and trigger **Rival Swing** through the interface. The human still controls their racket with an AirPod.

This is an early experiment in the perception-action loop of computer-use agents. We slow incoming play and buffer early swings to accommodate that loop, and these runs are unranked. The tactical API opponent and desktop experiment have different controls and timing, so we report them separately.

## How we used Codex to build it

We used Codex with parallel implementation agents and computer-use verification to build the Astra adapter, shared provider contract, sensor explanation, decision tracking, and regression tests.

One concrete example: our first comparison reported seven instant rate-limit failures. Inspecting the report with Codex revealed that those requests never reached either provider. Fractional timer waits could wake before our own scheduler allowed the next call. Codex helped repair the request-clock checks, distinguish local rejections from provider failures, and add a regression that deliberately wakes timers early.

Computer-use testing also caught a native menu freeze caused by reading station configuration during UI rendering. We moved those reads off the UI thread, added a timeout, and tested that a blocked read leaves the interface responsive.

These contributions changed behavior a judge can observe: the lobby opens, the model prepares without blocking the controller, and the comparison counts actual requests.

## Making the comparison fairer

We gave Astra and Jev the same twenty fixed synthetic game states, five legal shots, candidate order, and tactical objective. Each state ran twice per provider under a shared six-second deadline and request cadence.

In the corrected complete live run, **both returned 40 valid decisions from 40 requests**. Median request time was **1,836.5 ms for Astra and 322 ms for Jev**. The report retains every attempt and available response evidence.

That is a small comparison of decision delivery under our configured API paths. It does not rank tennis skill or establish why latency differed. The game supplies movement and contact for both models, and endpoint serialization differs.

## How an earbud becomes a racket

We built the arcade natively with **Swift, SwiftUI, SceneKit, and Core Motion**. Calibration maps the earbud's orientation relative to a neutral pose into racket orientation. A swing must make geometric contact with the ball to count.

The **How it works** screen exposes live motion readings, grip mapping, and racket output. New recordings preserve those values for display-only replay. A bundled earlier recording also shows real AirPod input, with its reconstructed mapping clearly labelled.

Rotation does not give us absolute hand position. Optional camera tracking supplies a separate screen-plane hand-position signal; tennis moves the character automatically. Because the public headphone API supplies one active AirPods stream at a time, our two-player duel uses an AirPod and an iPhone.

## What we're proud of—and what comes next

We brought together an everyday sensor, native game physics, a physical controller, an API-driven rival, and a computer-use experiment in one playable system. The most satisfying part is that you can ask how it works, then open the sensor and decision views and see the answer.

Next, we want to measure first-hit time with unfamiliar players, collect more real gameplay traces, and expand controlled agent experiments. Our aim is the feeling that made motion games memorable: someone picks up a controller, understands it, and immediately wants another turn.
