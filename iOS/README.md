# Aircade Controller for iPhone

The phone's **own** gyro/accelerometer controls either solo game or either player slot in Saber Duel. The AirPods pair remains connected to the Mac as a separate controller. Requires a physical iPhone with iOS 16+; the simulator has no usable motion sensor.

## Install from Xcode

1. Open `iOS/AircadeController.xcodeproj`.
2. Select the **AircadeController** target → **Signing & Capabilities**. Select your Apple ID's development team. If none is listed, add your Apple ID in Xcode → Settings → Accounts. A personal development team can run on your own device; this is not an App Store installation.
3. Connect the iPhone by USB, unlock it, and trust the Mac. Enable Developer Mode on the phone if Xcode requests it.
4. Choose your iPhone as the run destination and press **Run**. If prompted, trust the developer in the phone's Settings.

The project is configured for the Personal Team used on this Mac. Other developers should select their own team. The updated protocol requires rebuilding and installing the current companion app. A previous build was physically tested; a successful signed build alone does not establish installation. First launch may require trusting the developer profile in Settings → General → VPN & Device Management.

## Play

1. Open **Controllers** from the Mac's channel menu. The app hosts a six-digit pairing code even when no game is open.
2. On the phone, allow **Motion & Fitness** and **Local Network**. Keep both devices on the same Wi-Fi. Enter the code in Aircade Controller and select this Mac.
3. Hold the phone **portrait, screen facing you, top edge up**, and tap **I'm holding it upright**. This recenters only the phone.
4. Select **iPhone** under **Play with** on the Mac. Return to the menu and play **Tennis** or **Neon Rush** as a guest. AirPods are not required for solo phone play.
5. Switch between games without pairing again. The phone displays its current role.
6. For **Saber Duel**, start and calibrate the **earbud named on the Mac**, then choose which device is Player 1. The other becomes Player 2. Blue attacks right; orange attacks left. Both must be ready to start.
7. Swing through the opposing colored target to remove health; cross blades to parry. First to remove all five health wins. After 60 seconds, more health wins; equal health is a draw.

Keep the phone app foregrounded. Its haptic cues distinguish a scored hit, blade clash, taking damage, and match result. Recenter on the phone or press R on the Mac to pause and reset aim; resume on the Mac when ready.

The duel uses fixed hilt positions and controller orientation, not camera-tracked translation. No physical Elegoo motors are driven by this feature.

## Connection troubleshooting

- If discovery is empty, leave Aircade open on the Mac and check Local Network permissions on **both** devices. Allow incoming connections for Aircade if the Mac firewall prompts.
- Some event Wi-Fi networks block connections between clients. Try a personal hotspot with the Mac connected to it. Peer-to-peer discovery is enabled, but availability depends on the devices/network and is not a tested fallback yet.
- Changing games and reopening the lobby preserve the connection and code. **Unpair** explicitly removes the current phone and rotates the code. Restarting Aircade starts a new pairing session.
- A short tracking gap freezes the match and discards sweep history; a sustained gap requires Resume. The phone sends its latest pose only when the Mac requests it, so old movement cannot build up in a sensor send queue. Responses over 250 ms old are rejected; network round-trip time is included in freshness checks.
- Pairing and motion traffic use local TCP/Bonjour, with a lobby code and one phone slot. There is no cloud service. This is a local prototype, not an internet multiplayer transport.

## Reproduce build checks

```sh
xcodebuild -project iOS/AircadeController.xcodeproj -scheme AircadeController \
  -destination 'generic/platform=iOS' -derivedDataPath build/iOS \
  CODE_SIGNING_ALLOWED=NO build
```

An unsigned build verifies compilation and linking only. It does **not** verify physical phone motion, haptics, discovery on your Wi-Fi, or AirPod + phone gameplay.

## Player limits

This version has **two simultaneous players**: one AirPod stream plus one iPhone. One AirPods pair cannot supply separate simultaneous left/right streams through Apple's public API. `sensorLocation` reports the selected sensor; it is not a setter. Turn-based games could share the active earbud, or use a verified system handover between earbuds. Bowling/golf and additional phone slots are future modes, not part of this build.
