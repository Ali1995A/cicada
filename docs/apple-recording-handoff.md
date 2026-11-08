# Apple recording handoff (development branch)

## Scope

First deliver a file-based workflow: Apple Watch or iPhone captures the meeting; the Mac imports the audio and does speech recognition and notes. No live streaming, automatic remote control, or proprietary Voice Memos database access. No meeting recordings or credentials belong in Git.

- Apple Watch: use Voice Memos, sync using Apple's supported account/device setup, then export the recording on a supported device. Import the resulting audio file on the Mac. This branch does not contain a watchOS app or promise direct Watch-to-Mac streaming.
- iPhone: Voice Memos export works as the initial route. The existing experimental Cicada iOS app should also offer sharing its completed local recording through the system share sheet (including AirDrop when available).
- Mac: preserve an app-owned copy of imported audio so clearing Downloads does not break replay or retry. On a copy failure, do not create a misleading successful import.
- AI: reuse the existing Mac custom OpenAI-compatible API settings. Text, ASR and TTS are distinct model capabilities. iPhone recording does not need the Mac's API key. Reject credentials or query/fragment data in configurable base URLs.

## Limits and acceptance

The current executor is Linux with no Xcode or Apple devices. Native CI and later device checks are required. No real recording, cloud AI request, paid service, install or release is part of development verification.

Acceptance: exported iPhone M4A opens on Mac; imported audio survives removal of the original; a failed copy produces an error and no record; custom API base rejects embedded secrets; existing imports/tests still work. Later check Apple Watch recording quality, long recordings, interrupted sync, iPhone lock-screen recording, AirDrop and privacy prompts on real devices.

## Current branch status (2026-11-08)

The development branch now includes a source-code prototype: Mac imports copy their source into the session folder off the UI thread, a failed copy does not create a record, iOS exposes completed audio through the system share sheet, and custom API bases reject embedded credentials/query/fragment data. Apple Watch still uses the supported Voice Memos file workflow; no watchOS app or live transfer is implemented.

Native test/build status: NOT RUN successfully. `scripts/test.sh` stops at `xcode-select: command not found` in this Linux executor. No Apple device or model API has been used. GitHub Actions did not create a workflow run for the initial draft-PR commit when checked; its exact cause is not confirmed. Added Swift tests are source only, not a claimed passing suite. This is a draft prototype, not an installable verified release.

## Existing Mac custom API configuration

In Settings → AI service, choose the custom / OpenAI-compatible service:

1. Set the service's documented API base URL, usually ending in `/v1/`, and its text model ID. A native Gemini or Anthropic endpoint is not automatically compatible.
2. Keep Apple silicon on-device speech recognition initially. To use external ASR, explicitly enable it and choose an ASR model and the documented `/audio/transcriptions` compatible base. Chat models alone do not prove ASR support.
3. TTS is optional and uses a `/audio/speech` compatible model. It is not needed to create meeting minutes.
4. To avoid fallback Google translation, use the existing “语音和文字只发给你的服务” option, subject to the chosen backend's actual capabilities.
5. Configure keys locally only. Never paste a key in a URL, commit it, or put it into an exported meeting file. Existing custom endpoints share one provider key; avoid assigning different providers to text/ASR/TTS until credentials are isolated. Changing service domains should be followed by explicitly replacing the key before any request.

Models must be chosen from the actual provider's supported catalog; this branch does not promise a particular model, price or account availability. Real cloud requests can transmit audio/text and incur provider charges; no such tests have been performed.

## Device acceptance checklist for the new Mac

- Record a short consenting two-person meeting with iPhone Voice Memos; export the audio using Apple's supported sharing route; use Cicada's File → Import recording or video on the Mac.
- Repeat with Apple Watch Voice Memos after its recording is available for supported export. Do not assume automatic direct Watch-to-Mac transfer.
- Check duration, Chinese names/numbers, both speakers, original audio playback and timestamps. Speaker identity and diarization accuracy require review.
- Test a long recording and an interrupted transfer. Keep the source until import and playback are verified.
- After the retention change is implemented, remove only a disposable duplicate of the source and prove the imported recording still plays and can be retranscribed.
- Verify generated notes contain only meeting deliverable content; manually review decisions, owners, deadlines and uncertain words against the recording.

## Static verification of this prototype

Nine changed Swift files parsed with tree-sitter-swift without syntax errors. `git diff --check` and `scripts/check-agents.py` pass. These checks do not resolve Swift types, actor isolation, Apple framework availability, macros, or runtime behavior; native builds and tests remain required. Importing copies the entire source file (including video if selected), so allow sufficient free disk space. Existing imported records remain backward-compatible and retain their old source paths; they are not silently migrated.

The new API URL validation also runs before saving the three endpoint fields to ordinary settings. It does not migrate or erase previously saved values. Native localization extraction (`scripts/strings.py`) and iOS typechecking were attempted but blocked by missing Swift/xcrun; the five added text keys were checked in all four language tables. Static review caught and corrected sharing a partially rewrapped recording: an own-recording `.aac` sidecar now prevents sharing until finalization finishes.
