# Apple live meeting inputs (development branch)

## Available paths and scope

- **iPhone near Mac:** select the iPhone's Continuity microphone from Cicada's
  meeting input picker. Requires compatible nearby devices, same Apple account,
  and Apple's Continuity setup. Unlocking/calls/disconnection may interrupt it.
- **AirPods connected to Mac:** explicitly select them for the wearer's voice.
  Automatic mode still prefers room microphones; a headset is not a room-wide
  conference microphone. Bluetooth microphone use can reduce playback quality.
- **Watch:** experimental native capture and HTTPS transport can feed the Mac's
  existing live recognition chain through an explicitly enabled development
  bridge. This requires developer setup and has not passed real-device testing.
- **iPhone Cicada app:** its local recognition is separate from Mac processing.
  Direct app-to-Mac audio streaming is not implemented.
- **Completed audio files:** system sharing and Mac import remain an offline
  fallback, not a substitute for live recognition. Imported sources are copied
  into the meeting's storage, including the whole video if one is selected;
  account for the extra disk space. Keep originals until playback is verified.

## Meeting input selection

With the meeting microphone closed, choose Settings → General → meeting input.
The picker does not change macOS's default input. A missing selection falls back
to the existing automatic policy and is labelled unavailable. The current-input
row shows the active source; Refresh rereads devices. Native device-change and
hot-plug behavior must be validated on actual hardware.

## Watch development bridge

See [Watch development setup](../experiments/watch-live/README.md). The optional
path is Watch PCM → authenticated HTTPS → private 0600 same-user FIFO →
AudioRouter → ListenEngine → native recognition or the configured
CloudStream/TranslationService/LingClient → captions and meeting records.

Build with `WATCH_BRIDGE=1 scripts/build.sh`; regular builds omit the bridge.
Release builds reject that flag. A per-run pairing token authenticates transport;
model credentials never go to Watch. Normal certificate verification remains
enabled. The receiver does not change firewall/router settings or expose itself
publicly. Pairing/setup UI and installable Watch packaging remain unfinished.

The Watch displays transport acceptance, not proof of recognition. Check actual
Mac text. End-of-input drains the current recognizer rather than cancelling it;
disconnects can leave unrecoverable gaps. Mac mute zeros received samples for
recognition but does not stop physical Watch capture or transmission. Sample
duration avoids inserting network latency as repeated recording silence; exact
cross-device timestamps are not verified.

## Model APIs

Use Settings → AI service to choose a documented OpenAI-compatible endpoint and
supported model. Text, ASR and TTS have different capabilities. The existing ASR
path uses segmented `/audio/transcriptions`, not an arbitrary realtime WebSocket
protocol. Speech is batched plus network/inference latency; no fixed low-latency
guarantee is made. On Apple silicon, local recognition is the initial low-risk
choice. Intel requires the existing compatible cloud service.

URLs cannot contain credentials, queries or fragments. Store keys through the
existing local credential mechanism, not in URLs or exports. The existing custom
provider uses one credential across its text/ASR/TTS endpoints: do not configure
unrelated providers there without addressing credential separation. External
recognition sends audio to the configured service and may incur charges.

## Background and privacy

Mac must remain awake with the app running. Hidden/minimized windows do not imply
sleep support. No promise covers lid closure, sleep, quitting or shutdown.
iOS declares audio background mode, but uninterrupted lock-screen sessions remain
device-test work. Watch recording runtime and HTTPS delivery scheduling are
different constraints; wrist-down/background low-latency transmission is not yet
validated. No workout-session or TLS-security bypass is used.

## Verification

The macOS CI baseline native suite passed **285 tests** at commit `029073a`.
Linux cloud protocol/FIFO tests passed 16 synthetic cases. macOS protocol tests
found a test-client race during early oversized-request rejection; it was fixed
and the next macOS run passed that stage. Bridge-enabled compilation, watchOS
typechecking and complete development packaging are tracked by
[Apple validation CI](https://github.com/Ali1995A/cicada/actions).
Do not infer their success from the baseline result.

Real microphones, Watch/iPhone/AirPods hardware, TLS pairing, cloud ASR,
background/lock-screen, recording alignment and long-session battery behavior
remain unverified. No real recording, user key or paid API call was used.

## Official platform references

- https://support.apple.com/en-us/102546
- https://support.apple.com/en-us/102217
- https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos
- https://developer.apple.com/documentation/watchkit/taking-advantage-of-frontmost-app-state
- https://developer.apple.com/documentation/watchos-apps/making-default-and-ephemeral-requests
