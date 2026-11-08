# Apple recording handoff Implementation Plan

> For agentic workers: execute in a development branch; keep verification limits explicit.

Goal: make completed iPhone/Watch recordings reliable inputs to the Mac meeting workflow.
Architecture: use existing native recording/import and API clients, system file sharing, and app-owned local audio copies. Do not add a server or live stream protocol.
Tech Stack: Swift, SwiftUI, Foundation, existing Swift Testing.
Spec: docs/apple-recording-handoff.md

## Global constraints

No third-party dependencies, no personal recordings or keys in Git, no desktop front-end automation, no main-branch merge or release. Preserve current bundle identifiers and record compatibility.

## Review focus

Copy failure and cleanup; temporary source removal; duplicate filenames; live recording must not be exported unfinished; custom URL credentials/query data.

## Tasks

- [ ] Add failing tests for imported audio retention, copy failure and URL validation; run native tests.
- [x] Implement managed local copies and an import failure callback, preserving successful files in a mixed batch.
- [x] Add iPhone system share access to a completed local audio file.
- [x] Reject embedded URL credentials, query and fragment on custom AI bases.
- [ ] Update localized user guidance, run native tests, iOS typecheck, and review final diff.
- [ ] Push isolated development branch and draft PR; disclose any unrun tests and device acceptance checks.

Prototype exception: implementation continued at coordinator direction despite unavailable native tooling; no native red/green claim is made. Native builds/tests and device acceptance remain open.
