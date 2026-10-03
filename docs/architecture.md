# Architecture

## Architecture
One native process: SwiftUI onboarding, palette, stacks and settings; AppKit menu bar, nonactivating panel, pasteboard and focus lifecycle. SwiftPM targets separate WinnelCore, WinnelStorage, WinnelPlatform and WinnelApp; WinnelFixture is development-only.

## Key decisions
- CryptoKit AES-GCM seals manifest metadata and per-UUID payload files. Winnel owns one non-synchronizing Keychain item; no plaintext fallback. Atomic manifest replacement precedes garbage collection; GC failure is a committed-state warning, not rollback.
- Direct paste is optional and restricted to exact empirically tested app versions/builds. Production allowlist currently empty. Target observation must begin before snapshot, and any focus/selection change permanently invalidates that invocation.
- Capture admission: the complete raw representation payload is checked before content parsers; derived RTF text/file metadata is checked again before publication. Repository size rejection precedes plaintext/search/fingerprint processing. ADR002 records the approved provider-allocation exposure.
- ADR: decisions/001-native-encrypted-vault.md. Privacy/OS observations remain separate evidence gates.

## Patterns in use
Repository FIFO serialization spans actor suspension points. Main-actor controller uses revisions, cancellation epochs and field-wise settings merges to prevent stale actions. Content invalidation clears selected IDs/order with plaintext caches, preventing surviving saved selections from displaying a cleared preview. The recovery fixture seeds only a generated temporary encrypted vault with an in-memory key deliberately withheld; retry releases the same key and ciphertext export requires no key. Each content-operation kind cancels and awaits its predecessor before loading more payloads; image thumbnails are part of that same preview worker. Capture admits one pending save and visibly skips incoming copies while storage is busy. Authorization is rechecked after key access and before disk/RAM publication. Expensive decoding/search/export run outside UI execution. Exercised fixtures use synthetic named pasteboards and temporary vaults. The ordinary fixture editor overrides Paste and its validation to use the named board; actual ordinary fixture Command-V outcomes are observed, while secure-field and other inherited AppKit actions remain unverified. Preview invalidation follows the first ordered selected item, and Library member detail invalidates when global selection diverges. Opening Library/Settings and preparing an export modal dismiss the floating palette; palette invocation returns while a native modal is active. Explicit scope changes keep only visible selected IDs in order. A changed search query starts fresh selection and cancels pending selection-dependent work; identical query assignments and routine refresh preserve selection, and existing queues survive query changes. Authoritative payload search determines results, avoiding metadata-only false negatives for long text.

## Component relationships
Payloads are shared by pins and ordered per-stack memberships, including membership-specific URLs. Queue retains bounded payload snapshots in RAM, is ephemeral and is canceled on lifecycle suspension/deletion. RAM-only recent payloads stay in process; deliberate saved references persist encrypted.

## Data flow
Opt-in and lifecycle/exclusion/marker checks → stable allowlisted read with retained-payload limits (provider allocation is an explicitly accepted boundary under PRD v1.2 / ADR002) → deduplication and retention → authenticated encrypted persistence → local search/preview → explicit copy, validated paste or export. Error states pause capture and protect existing content.
