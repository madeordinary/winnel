# Contributing to Winnel

Winnel is a native, local-first Mac app under the MIT license. Read [PRD.md](PRD.md), [architecture](docs/architecture.md), [ADRs](docs/decisions) and the [verification summary](docs/verification.md) before changing behavior.

## Build and verification

Use the toolchain and commands in [README.md](README.md). Run `bash scripts/test-offline.sh` for synthetic automated checks and `bash scripts/build.sh` for a local ad-hoc bundle. Native integration needs a Mac session with the required existing permissions. Use `bash scripts/run-fixture.sh` to exercise the dedicated named pasteboard; never use personal clipboard contents as a test fixture.

Keep changes focused and test behavior at the layer that can establish it. Record exact test conditions and known failures. Do not treat an offscreen render, unit test or dispatch call as proof of keyboard, VoiceOver, permissions or cross-app paste compatibility. The production direct-paste allowlist stays empty until observed compatibility trials satisfy the PRD.

## Documentation and local memory

Public documentation includes requirements, architecture decisions, build instructions, known limitations and sanitized verification summaries. Source, tests, licenses and shared Serel workflow definitions stay tracked.

Local-only paths are `memory-bank/`, `.rules`, `GOAL.md`, `docs/evidence/`, seed proposals and the original agent implementation plan. They may contain checkpoints, machine paths, owner instructions, screenshots or raw logs. They are intentionally absent from a fresh public clone. Preserve existing local files, never force-add them, and never treat someone else's saved approval as authorization for your environment.

Initialize a local bank from the code and PRD with Serel's `init-memory` workflow when needed. Keep its seven files at the normal ignored `memory-bank/` path; `memory-bank.local/` is reserved for upstream framework development. No hooks are enabled automatically.

Promote durable findings into `docs/` only after reviewing them for personal content, credentials, local paths and session details. Raw receipts may support a maintainer-recorded summary without being published; state that limit honestly. `.gitignore` does not remove files already present in Git history.

## Pull requests

Explain the user-visible problem, resulting behavior, meaningful verification and remaining limits. Do not change privacy boundaries, weaken failing checks, store clipboard data in source control or publish credentials. Signing and notarization require the release operator's explicitly selected identity and credentials.
