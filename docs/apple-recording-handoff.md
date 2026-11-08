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
