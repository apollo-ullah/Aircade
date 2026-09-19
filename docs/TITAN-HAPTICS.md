# TITAN Core haptics

Implemented in the macOS app using the kit's stock Vector Haptics serial firmware.
No firmware flash, Arduino install, or hand-tracking replacement is required.

## Connect

1. Attach a DRAKE motor to L, R, or M, matching the board's polarity markings.
2. Remove the mode jumper and connect a data-capable USB-C cable to the Mac.
3. Open **Aircade → Settings…** (Command-comma).
4. Refresh and select the kit's serial port. Choose its motor channel and the
   player wearing it (AirPod/hand-tracked player or phone player).
5. Connect, start with low strength, and press **Test**. Try each effect.
6. Play tennis, Neon Rush, duel, or the training lab. Confirm the intended player
   feels each contact. Phone haptics continue to work independently.

A port opening successfully is not confirmation of motor movement or firmware
compatibility. If Test produces nothing, check channel/wiring, remove jumpers,
close other serial monitors, and reconnect. If the device is unplugged, reconnect
it explicitly in Settings. Settings are session-local; no automatic port opening.
One kit/channel/recipient is supported at a time.

## Event mapping

| Interaction | Effect at full slider strength |
| --- | --- |
| Tennis racket return / Neon Rush cut / duel hit / lab cut | Sharp 20 ms tick, 80% |
| Block / parry / glancing or wrong-direction contact | Soft 45 ms pulse, 65% |
| Damage / missed ball or target | 90 Hz vibration, 140 ms, 60% |
| Victory | 180 Hz vibration, 180 ms, 50% |
| Defeat | 60 Hz vibration, 200 ms, 45% |
| Draw | 100 ms pulse, 40% |
| Controller menu activation | Light 10 ms tick, 30% |

The strength slider scales these values (default 50%). Cues originate from game
judgments, not rendered animation frames. Controller identity/run checks prevent
old game callbacks reaching another player; TITAN also requires fresh,
non-simulated input. Lab and controller-menu interactions use their own gated
callbacks. Test intentionally works without tracking. Opponent tennis returns do
not trigger the player's motor.

## Transport

115200 baud, raw 8N1; channel 1=L, 2=R, 3=M. Example:

```text
CHNL 1; Tick 0.400 20;
```

Each command ends with a newline. Commands use locale-independent decimals and
bounded strength/channel values. Writes are nonblocking, never retried or queued;
a full serial buffer drops the event. Events within 25 ms are coalesced by dropping
the later event. Partial writes and device errors disconnect. All effects have a
finite duration of at most 200 ms; disconnect cannot cancel an effect already
received by the firmware. Diagnostic input is drained periodically.

## Verification

Automated pseudo-terminal tests exercise actual serial setup and transmitted
bytes, recipient filtering, disconnect behavior, effect bounds and invalid ports.
These tests do not verify a physical TITAN board, latency, or perceived feel.
Run:

```sh
swift test --filter 'TitanHapticsTests|SoloFeedbackRecoveryTests|ControllerSessionTests|TennisIntegrationTests|ControllerMenuTests'
```

## Sources and wireless follow-up

- [Titan Hack the North resources](https://titanhaptics.com/hackthenorth)
- [TITAN Core guide bundle](https://titanhaptics.com/docs/TITAN-QuickStart-and%20-Integration-Guide.zip), serial command table on page 9
- [Vector Haptics quickstart](https://titanhaptics.com/docs/Vector%20Haptics%20Quickstart%20Guide.pdf)
- [DIY XR hand-tracking article](https://titanhaptics.com/haptics-in-xr-apples-hand-tracking-and-diy-haptics-peripherals/)

Stock Bluetooth mode is audio-to-haptics on L/R, not a documented BLE command
service. This implementation uses USB for event-specific output. The XR article
links to the saber demo, but supplies no source repository or wireless command
protocol; integrating that project's firmware requires its actual repository.
