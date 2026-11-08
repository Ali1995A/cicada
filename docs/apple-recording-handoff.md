# Live Apple meeting inputs (development branch)

## Corrected scope

The user requires live recognition: speech should become text during the meeting, with Mac doing the processing. Earlier file-import work alone did not satisfy this. It remains a fallback and audio-retention improvement.

Cicada already has a Mac live microphone pipeline (RoomMic → ListenEngine → Recognition / CloudHearing → captions and Notes). The experimental iOS app also has a local live recognition pipeline; that is different from streaming its audio to Mac.

## Live device paths

| Capture device | Processing and current branch status |
| --- | --- |
| iPhone near Mac | Use Apple's Continuity microphone as a Mac audio input. This branch adds an explicit meeting input picker; actual device integration has not been tested. |
| AirPods paired with Mac | Select AirPods explicitly as the meeting input. Automatic mode still prefers a room/table microphone, to avoid unexpectedly switching to a headset. |
| iPhone running Cicada | Existing iOS app recognizes on the phone. A direct iOS-app-to-Mac audio streaming protocol has NOT been implemented. |
| Apple Watch | An isolated [live PCM transport probe](../experiments/watch-live/README.md) has been added. It is not built/tested on watchOS and is NOT connected to recognition. Voice Memos synchronization is NOT realtime recognition. |
| iPhone/Watch completed recording | Export/share and Mac import remain the offline fallback. |

### iPhone → Mac using Continuity microphone

Apple supports using an iPhone microphone separately from its camera, wired or wirelessly. Devices need the same Apple Account with two-factor authentication, nearby Wi-Fi/Bluetooth, supported hardware/OS, and enabled Continuity Camera; USB requires trust. iPhone XR+ / iOS 16+ and macOS Ventura+ are Apple's continuity floors; Cicada has its own higher platform requirements. Keep the phone locked and stable. Unlocking, calls, disconnecting or moving away can interrupt the audio. See [Apple's current requirements](https://support.apple.com/en-us/102546).

On Mac, before enabling the meeting microphone, choose Settings → General → meeting input. Pick the iPhone entry actually enumerated by macOS, or AirPods. No system-default microphone setting is changed. Close the microphone before changing this picker, then enable it again. Missing preferred inputs fall back to the existing automatic selection and are labeled as unavailable. A disconnected live input uses the existing warning/fallback behavior. The current-input row shows the actual pinned device separately from the saved preference, and a refresh button rereads the device list. Automatic device reconfiguration may pick the preferred input again; hot-plug and reconnect behavior requires device validation.

This path does not expose a network server, pair arbitrary devices, or work across the public internet. It requires no API key on the phone.

### AirPods and background use

AirPods directly connected to Mac can feed the same live recognition chain. They primarily capture the wearer's speech, not every speaker around a large table. Bluetooth bidirectional microphone mode can reduce playback quality; actual behavior depends on hardware/OS. [Apple Bluetooth microphone guidance](https://support.apple.com/en-us/102217).

Mac Cicada is a menu-bar app: hiding/minimizing a window is different from stopping capture. The Mac must remain awake and the app running. Do not promise recording through sleep, lid closure, shutdown or quitting. This branch does not change system sleep settings.

The experimental iOS app declares audio background mode and activates an AVAudioSession; that expresses intended background audio behavior, not proof of uninterrupted locked-phone recording. Interruptions, routes, long sessions and native signing still require device tests. It does not forward audio to Mac. The Continuity path is Apple's separate locked-phone microphone session.

### What realtime means for custom APIs

Mac native recognition supplies draft and final text during speech. The existing custom cloud ASR uses OpenAI-compatible /audio/transcriptions with short audio segments, not a universal WebSocket realtime protocol. CloudSegmenter ends after a 0.6-second pause or cuts stretches at up to 8 seconds, then network/model time is added. Do not advertise zero latency, subsecond results, or compatibility with every provider's realtime API. Text generation and speech recognition require different model capabilities.

## Current verification status

The meeting input picker and preferred-input policy are source-code changes in this draft, not a verified release. Regression cases cover explicit phone selection, explicit Bluetooth selection, unavailable/virtual preferences, and empty input lists. The current executor is unavailable: shell execution returned “No usable execution environment is available.” Native Swift build, tests, localization extraction, signed iOS installation and real audio tests could not run. No user key, recording or paid model request was used.

Device acceptance must cover live Chinese speech before the meeting ends, actual input name, microphone levels, final transcript/notes, phone unlock/call/disconnect, AirPods route changes, minimized Mac UI, locked phone, sleep interruption, and API latency/error recovery. Watch streaming is still open work and must not be presented as complete.

## Existing Mac custom API configuration

In Settings → AI service, choose the custom / OpenAI-compatible service:

1. Set the service's documented API base URL, usually ending in `/v1/`, and its text model ID. A native Gemini or Anthropic endpoint is not automatically compatible.
2. Keep Apple silicon on-device speech recognition initially. To use external ASR, explicitly enable it and choose an ASR model and the documented `/audio/transcriptions` compatible base. Chat models alone do not prove ASR support.
3. TTS is optional and uses a `/audio/speech` compatible model. It is not needed to create meeting minutes.
4. To avoid fallback Google translation, use the existing “语音和文字只发给你的服务” option, subject to the chosen backend's actual capabilities.
5. Configure keys locally only. Never paste a key in a URL, commit it, or put it into an exported meeting file. Existing custom endpoints share one provider key; avoid assigning different providers to text/ASR/TTS until credentials are isolated. Changing service domains should be followed by explicitly replacing the key before any request.

Models must be chosen from the actual provider's supported catalog; this branch does not promise a particular model, price or account availability. Real cloud requests can transmit audio/text and incur provider charges; no such tests have been performed.

## Offline fallback acceptance checklist for the new Mac

- Record a short consenting two-person meeting with iPhone Voice Memos; export the audio using Apple's supported sharing route; use Cicada's File → Import recording or video on the Mac.
- Repeat with Apple Watch Voice Memos after its recording is available for supported export. Do not assume automatic direct Watch-to-Mac transfer.
- Check duration, Chinese names/numbers, both speakers, original audio playback and timestamps. Speaker identity and diarization accuracy require review.
- Test a long recording and an interrupted transfer. Keep the source until import and playback are verified.
- After the retention change is implemented, remove only a disposable duplicate of the source and prove the imported recording still plays and can be retranscribed.
- Verify generated notes contain only meeting deliverable content; manually review decisions, owners, deadlines and uncertain words against the recording.

## Historical static verification of the earlier offline prototype

Nine changed Swift files parsed with tree-sitter-swift without syntax errors. `git diff --check` and `scripts/check-agents.py` pass. These checks do not resolve Swift types, actor isolation, Apple framework availability, macros, or runtime behavior; native builds and tests remain required. Importing copies the entire source file (including video if selected), so allow sufficient free disk space. Existing imported records remain backward-compatible and retain their old source paths; they are not silently migrated.

The new API URL validation also runs before saving the three endpoint fields to ordinary settings. It does not migrate or erase previously saved values. Native localization extraction (`scripts/strings.py`) and iOS typechecking were attempted but blocked by missing Swift/xcrun; the five added text keys were checked in all four language tables. Static review caught and corrected sharing a partially rewrapped recording: an own-recording `.aac` sidecar now prevents sharing until finalization finishes.


## Watch transport experiment update (2026-11-08)

Cloud Python execution was restored for the isolated transport experiment. Ten synthetic protocol/loopback HTTP tests passed. No native Swift build, full Cicada suite or device test has run. The experiment sends audio during recording and only acknowledges/prints transport metadata, with HTTPS, a per-run private pairing token, bounded buffers and visible interruption failure. It does not yet provide Watch transcription, captions, notes, background guarantees or an installable watchOS target. See its README for the remaining integration and device acceptance work.
