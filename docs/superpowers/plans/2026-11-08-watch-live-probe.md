# Watch live transport experimental plan

Goal: test Watch audio reaching Mac during recording, never substitute completed-file sync for live input.

Architecture: isolate a native AVAudioEngine sender and standard-library HTTPS metadata receiver under experiments/watch-live; preserve the production LingClient-only AI path. Model integration is a later task, not included in this probe. User requested background development without more setup questions; no user desktop operations.

- [x] Check Apple HTTPS/routing/background constraints.
- [x] Write protocol and synthetic receiver tests before implementation; run missing-module baseline, implement, execute 10 passing checks.
- [x] Add bounded native capture/upload source, explicit session sequencing and interruption errors; independently static-review.
- [x] Correct tap/finish ordering, allocation failures and malformed HTTP header handling.
- [ ] Compile/typecheck native source and test concurrent stop, resampler finalization, microphone permissions, TLS and real Watch networks.
- [ ] Add Mac native recognition integration, session continuity and retention policy.
- [ ] Validate wrist-down/background, calls, network changes, long recordings and battery.

The prototype is not a production feature. Python checks do not validate Swift, audio completeness or end-to-end transcription. No keys, recordings, models, firewall modifications or public deployment used.
