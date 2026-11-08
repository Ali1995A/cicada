# Watch → Mac live audio transport experiment

**Status: isolated, unshipped experiment. This is NOT speech recognition.**
It sends audio while recording instead of waiting for the meeting to end.
The Mac receiver acknowledges each PCM frame and prints only sequence, sample
count, duration, RMS and receipt time. It does not persist audio, call a model,
feed Cicada's subtitles/records, or produce a meeting report.

## Why this experiment exists
The requested final product is Watch/iPhone live capture with Mac recognition,
including custom API models. Existing Cicada does live recognition from Mac
audio devices; iPhone Continuity/AirPods selection is in draft PR #1. Watch is
not a Continuity microphone. This independent probe tests the missing network
capture transport before integrating it with AudioRouter / ListenEngine.
All eventual AI calls must use the existing LingClient. Do not add model keys
to this Watch app or bypass that architecture with Python API requests.

## Files
- `WatchLiveProbe.swift`: native watchOS capture + bounded upload queue + minimal UI.
- `live_receiver.py`: Python 3.10+ standard-library HTTPS receiver, one active session.
- `live_protocol.py`: frame and sequence validation.
- `test_live_protocol.py`, `test_live_receiver.py`: synthetic protocol/HTTP tests.

## Build and run (manual, not performed on the user's computer)
1. Create a separate SwiftUI watchOS app target (watchOS 10+, Swift 5 language mode)
   in Xcode on a Mac. Replace its generated App file with WatchLiveProbe.swift.
   This source is **not** included in Cicada's current build scripts and has not
   been compiled against the watchOS SDK.
2. Set the microphone usage description and enable the Audio background mode
   for this recording target. Start recording only through the visible button.
   Do not add workout sessions, ATS global exceptions or trust-all TLS delegates.
3. On the Mac provide a TLS certificate and key for a hostname the Watch can
   resolve and reach, with a chain already trusted by the Watch. The certificate
   must match that hostname. An ordinary untrusted self-signed certificate fails.
   Certificate provisioning is not automated by this experiment.
4. Run `python3 live_receiver.py --cert /path/cert.pem --key /path/key.pem`.
   Default bind is loopback only. To test across devices, explicitly select the
   Mac's private LAN address via `--bind <LAN-IP>`. No firewall changes, router
   forwarding or public exposure are performed. Keep the Mac awake.
5. Enter the HTTPS origin (e.g. `https://mac.example:8443`) and 64-character pairing token from
   the private 0600 file whose path the receiver prints on the Watch. Watch keeps the token only in memory. The Mac removes its temporary pairing
   file on a clean shutdown; a new run creates a new token. Do not screenshot
   or share the file. Crash leftovers cannot authenticate to a new receiver. No API key is needed for this transport-only probe.
6. Press Start. Confirm increasing sequence numbers on **both** devices while
   speaking. Press Stop; wait for the final confirmation. Frame metadata and RMS
   establish delivery, **not** recognizer accuracy, complete audio fidelity or
   proven lock-screen/background reliability.

## Wire contract and failure behavior
- HTTPS POST /session, Bearer token, empty body: opens one random session.
- POST /pcm/{session}/{sequence}: mono signed PCM16 little-endian at 16 kHz,
  maximum 128000 bytes (4 seconds), sequence starts at zero. One outstanding
  upload; up to three queued frames. Frame boundaries use sample counts, not
  UI timers. No silent replay/reordering and no unbounded buffering.
- POST /end/{session}: closes the session after the last frame acknowledgement.
- 8-second request / 10-second resource timeout on Watch. Sequence gaps,
  overload, interruptions, audio-route changes, failed TLS/auth/network requests
  stop the recording with a visible error. User must explicitly start again.
  No hidden fallback to offline file transfer. Failed sessions expire after
  30 seconds; restarting too early can return “already recording”.
- The receiver checks auth before reading the bounded body; rejects unknown
  routes and oversized/odd-length frames. Constant-time token comparison,
  no redirects on Watch, standard certificate verification. Receiver accepts
  one client at a time with 5-second socket timeout. It is a LAN experiment,
  **not a hardened public server**.
- The receiver discards PCM after deriving metadata. There is no recovery copy;
  any interrupted/unacknowledged audio may be lost. Do not use for important
  meetings until recording retention, recognition, gap UI and device tests exist.

## Platform facts and open acceptance work
Apple permits URLSession HTTPS on watchOS, without a custom iPhone relay.
Actual routing may go via the paired iPhone, known Wi-Fi or cellular; this does
not make a private Mac LAN endpoint reachable from every route.
Active recording can allow background runtime, but ordinary URLSession requests
and deferred background transfers do not establish a fixed 4-second background
delivery guarantee. Wrist down, app switching, screen lock, calls/alarms,
network changes and Mac sleep all need real-device tests. No workout keepalive.

Sources:
- https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos
- https://developer.apple.com/documentation/watchos-apps/keeping-your-watchos-app-s-content-up-to-date
- https://developer.apple.com/documentation/watchkit/taking-advantage-of-frontmost-app-state
- https://developer.apple.com/documentation/watchos-apps/making-default-and-ephemeral-requests
- https://developer.apple.com/documentation/watchos-apps/making-background-requests

## Verification, 2026-11-08
Executed in cloud Linux/Python 3.12 with synthetic zero PCM, no real microphones,
keys or model calls: 5 protocol tests + 5 loopback HTTP tests passed.
The tests were run using the exact source text loaded as in-memory modules.
The HTTP test harness intentionally uses loopback cleartext; the command-line
receiver has no cleartext option. **TLS/device interoperability was not tested.**
Swift/watchOS compilation, full Cicada suite, native runtime and 1-hour battery/
background tests were **not run**. No claim of end-to-end transcription.

Next: watchOS SDK compilation and audio/TLS device tests, then integrate accepted
PCM into the Mac native recognition pipeline with session-scoped authentication,
sample timestamps, continuity/gap handling, bounded buffering and appropriate
recording-retention controls. This must not be advertised as released Watch support.
