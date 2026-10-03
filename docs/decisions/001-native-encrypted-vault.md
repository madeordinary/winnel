# ADR 001: Native components and an authenticated encrypted vault

Date: 2026-10-01. Status: accepted for synthetic implementation; runtime validation pending.

Winnel uses Swift 6, SwiftUI and AppKit with a macOS 14 deployment target. Swift Package Manager builds the app, pure domain library, storage library and platform adapters. Xcode 27.0 (27A266a), Swift 6.4 and SDK 27.0 are the observed build tools. APIs newer than the deployment target require availability checks. A synthetic AppKit fixture uses a named pasteboard and isolated storage; it never reads the general clipboard.

The vault uses Apple's CryptoKit AES-GCM with a random 256-bit key in an app-specific, non-synchronizing Keychain item. It has individually authenticated payload records and an authenticated encrypted manifest for metadata, paths, stack names and references. Search metadata stays in memory after decryption; previews are generated on demand. The app does not write a plaintext database, journal, index, thumbnail or temporary capture.

An actor serializes commits. New immutable encrypted payloads are written before an atomic encrypted manifest replacement. Only then may unreachable records be removed. Recovery never replaces an unknown schema, corrupt manifest or inaccessible key automatically. A key is created only for a new empty vault after an intentional enable/save action. Reopening an existing vault without its key produces a visible recovery state. Automatic Keychain reads do not prompt. Existing credentials outside Winnel's own service are never modified.

RAM-only recent history is excluded from both manifest and payload persistence. Pins and stacks are deliberate persistent exceptions. Queue snapshots remain in memory and expire or cancel independently. The controller must commit a candidate state before replacing its visible committed state, and pause capture on failed persistence. It must not drop saved content in an attempted recovery.

Payload limit is 20 MiB serialized; managed storage limit is 2 GiB, including encrypted overhead. Image dimensions are inspected before decoding and previews bounded. The adapter cannot know how much an arbitrary pasteboard producer allocates internally; unsupported promises are not requested and oversized returned data is discarded. This limitation must stay documented.

Direct paste captures a process, launch identity, focused control, window and selection before the palette activates, and revalidates immediately before posting only Command-V. Terminals, secure controls, unknown controls and focus changes use manual Copy. The empirical compatibility set begins empty. Synthetic fixture support is not a claim about other apps or older macOS versions.

Alternatives considered: SQLite with an encryption dependency would introduce dependency/version and journal-audit work; a single encrypted full-library file would require rewriting large payloads for small metadata changes. Per-record AES-GCM uses established platform cryptography while keeping payload loading bounded. It requires explicit transaction/crash tests and authenticated association between a record and its role/ID.

Self-review risks to verify: crashes between payload and manifest writes; orphan cleanup; disk full and atomic rename failure; key disappearance/denial; symlink substitution; concurrent processes; corrupted/unknown schemas; allocation and cache limits; sleep/lock races; target changes during activation; no dispatch into terminals; future OS consent behavior. Recorded verification and limitations are summarized in `docs/verification.md`. No real clipboard content may be persisted before safety evidence and the user's opt-in.

Transaction quota reserves a second copy of the current encrypted manifest within the 2 GiB cap. New growth cannot consume the headroom needed to stage a later shrinking deletion. This is accounted transaction space, not a changed product budget. Boundary tests use a small injected quota to exercise the same arithmetic without allocating gigabytes.
