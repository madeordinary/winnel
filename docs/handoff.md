# Winnel — contributor handoff

Maintainer-recorded verification for application source `590589742b217d0f0a0d39cae558aaccae201a7a`: **123 offline tests passed**, local ad-hoc package checks passed, and bounded synthetic native observations and a 30-minute local resource fixture completed. These reports are not independent full acceptance. See [verification scope and provenance](verification.md). Full native/OS and release acceptance remains incomplete.

The 2026-10-04 [UI revamp](ui-revamp.md) adds content-type filtering and updates the main native surfaces. Its 125-test offline suite and optimized build passed; 29 synthetic component renders cover light/dark and selected minimum sizes. Native interaction remains unverified on this candidate because accessibility-based automation could not read Winnel's window state. Start with JSON export and keyboard/category/filter navigation when native access is available. See the [new verification record](verification.md#ui-revamp-verification); retain the earlier observations under their original revisions.

The [PRD follow-up](verification.md#prd-follow-up) fixes live onboarding practice, shortcut display, pause preservation and unavailable Combine actions. Its 131-test offline suite, optimized ad-hoc package/extraction and 31 component renders passed. Start native acceptance with onboarding opt-in → practice → Pause → Get started → still paused, then JSON export and keyboard/category/filter navigation.

The [neutral palette and card Library follow-up](verification.md#neutral-palette-and-card-library-follow-up) replaces the warm accent with adaptive blue, reduces quick-panel chrome, and adds ordered Cards/List views with an optional inspector. Final source passes 131 offline tests, local package/extraction checks and 36 component renders. Native selection reveal, inspector reflow and keyboard/VoiceOver remain unverified.

## Run and reproduce

From the repository root:

```sh
bash scripts/test-offline.sh
bash scripts/package.sh
bash scripts/run-fixture.sh
```

Packaging writes development artifacts under `build/distribution`. Use the synthetic fixture for development; production capture requires explicit opt-in and applicable OS consent. Existing Xcode is selected per command; see [dependencies](dependencies.md).

## Implementation

Native SwiftUI/AppKit menu bar, palette, onboarding, saved-stacks Library and Settings. Core/controller/storage tests cover opt-in capture, retention, deduplication, pins/shared ordered stacks, local search, five combination formats, exact preview/export, manual Copy/queue behavior, encrypted storage and recovery. Direct paste defaults closed until exact app/version/control observations establish compatibility.

One process; Core, Storage, Platform and App SwiftPM targets. CryptoKit AES-GCM encrypts UUID-bound payloads and manifest metadata. One app-owned non-synchronizing Keychain item holds the key; fixtures use in-memory keys. FIFO repository transactions span suspension points. Atomic manifest replacement is the commit point; later garbage-collection failure is a committed-state warning. Storage never falls back to plaintext. See [architecture](decisions/001-native-encrypted-vault.md).

Content tasks cancel obsolete work and revalidate epochs. Capture checks authorization after key access and before publication. Paste paths recheck the approved clipboard counter and target. A sent event does not prove destination consumption. Queues retain bounded ephemeral payloads; saved references are deliberate. Ciphertext without the original device-bound key is not a portable backup.

## Remaining work

- Finish [native recipes](verification.md#remaining-verification): JSON export, complete keyboard/VoiceOver, actual OS consent/revocation, supported direct paste and adversarial focus, production durable reopen and remaining recovery causes.
- Establish true cold launch and shortcut-to-visible timing on the reference device. The final-source local 30-minute fixture passed; its hosted model omits AppDelegate/global shortcuts. Historical failed measurements remain in the [performance summary](verification.md#performance).
- Test macOS 14, reference M1 Air 8 GB, external display and other declared environments.
- Complete two-week voluntary beta, naming checks, Developer ID signing/notarization and binary release. Public source availability does not close these gates. See [release checklist](release.md), [beta plan](beta-plan.md), [compatibility](compatibility.md) and [requirements](requirement-evidence.md).

The [C-09 allocation decision](decisions/002-capture-allocation-feasibility.md) accepts provider allocation before size is known. Raw and final serialized admission limits do not prevent an oversized provider memory spike or a stalled provider worker; there is no helper/process isolation.

Public contributor docs contain bounded summaries. Raw synthetic receipts and project continuity/worklogs are retained privately by maintainers. Contributors can reproduce automated checks and record new native observations with exact source revision and environment.
