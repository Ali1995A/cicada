# Live meeting inputs implementation plan

Goal: satisfy live recognition using iPhone or AirPods as capture hardware with Mac processing. Post-meeting imports are only a fallback, not fulfillment of the live requirement.

Architecture: reuse Mac RoomMic → ListenEngine → Recognition / CloudHearing → live captions and Notes. iPhone Continuity microphone and AirPods connected to Mac are Core Audio inputs. No custom transport is required for this nearby-device path. Watch realtime capture remains an independent unfinished subsystem.

- Add preferred-input regression cases to RoomTests.
- Persist roomMicUID (empty = automatic), use it for initial capture and disconnect fallback.
- Add a General settings picker for physical inputs. Disable changing it while the microphone is open; user turns microphone off before switching, without silently ending the meeting.
- Preserve the existing automatic preference for table microphones. Explicit AirPods choice is allowed. Reject virtual input preferences; missing selection falls back visibly.
- Document native vs segmented cloud ASR, background/lock/sleep limitations and device tests.

Validation: scripts/test.sh, scripts/build.sh, scripts/strings.py, iPhone/AirPods disconnect and audio-route tests on Mac. Current executor unavailable, so no native execution is possible. Tests are authored first but were not executed. Source changes are draft prototypes pending Apple compilation and device acceptance; no claim of passing TDD or installable output.
