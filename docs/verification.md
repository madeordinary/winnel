# Verification scope and provenance

Recorded 2026-10-02. This is a sanitized **maintainer-recorded summary**, not an independent audit or full PRD acceptance. Raw synthetic receipts are retained privately. Source references were remapped during documentation-history cleanup; application trees were verified unchanged, and the recorded tests predate that cleanup. Results apply only to the named source, host and exercised paths; source/tests alone cannot establish OS integration.

## Automated tests

Application source `590589742b217d0f0a0d39cae558aaccae201a7a` passed 123 XCTest tests with zero failures, exit 0, under test-process network denial using `bash scripts/test-offline.sh`. Named assertions and acceptance limits remain in the [requirement matrix](requirement-evidence.md). Earlier `9dde333` passed 111 tests (26 Core, 13 Storage, 26 Platform, 46 App); `e84664a` passed 107. These earlier results exclude subsequent fixes. Network denial verifies exercised test paths, not comprehensive traffic observation.

## Build and package

Source `5905897` package command and extraction checks exited 0. Extracted executable and license bytes matched; ad-hoc signature validation passed. Executable SHA-256: `44e1a484d4a92fdafd94d28209a9d6cbf9cc591e40b06fa7775f9008682a334d`. ZIP SHA-256: `930f10acf1854c2f3ae16d1e0fdf4f851cf65d5e44d084d4396db0aa4378c970`. These are development artifacts with no Developer ID signature or notarization.

Observed host: arm64 macOS 27.0.1 (26A434), Xcode 27.0, Swift 6.4, SDK 27. The scripts select the native SwiftPM backend with explicit SDK path: it emitted SDK 27/minimum 14 metadata where the default SwiftBuild backend emitted SDK 14/minimum 14. The native backend is deprecated and must be reassessed on toolchain upgrade. Declared deployment target does not establish macOS 14 runtime acceptance.

## Native observations

All observations use synthetic named pasteboards, temporary vaults and generated data. They are partial native observations rather than certification of complete recipes.

| Source | Bounded observations and limitations |
|---|---|
| `9dde333` | Captured synthetic text/search/preview, manual Copy then ordinary fixture Command-V, Settings pause/resume/exclusions, literal color/pin, shared stacks with rename/order/member URLs, Markdown Copy and 196-byte Markdown export; Copy Next completion/Back/cancel. Paste Next fell back, editor unchanged and queue did not advance. Membership removal preserved sibling stack; global deletion named affected stack; export remained unchanged. Stale preview, Library focus/layout/member mismatch and an empty expired queue strip were found. Later fixes require separate observations. |
| `7067ee4` | Reordered URL preview, unobstructed Library/member invalidation, queue-strip removal after a 335.420-second receipt interval (30-second maintenance, not exact expiry), Clear Recent saved-item protection, stack deletion preserving a pin, stale clipboard-clear confirmation preserving a newer fixture copy. Stale selection/loading/title defects led to later fixes. |
| `0d93cc9` | Synthetic recovery: 213-byte encrypted payload plus 1205-byte manifest exported; Retry restored pin/stack/payload without changing ciphertext; cancel preserved files; explicit reset removed payload and returned capture-off onboarding. Deliberately withheld in-memory key, not real OS Keychain denial. |
| `0d2922e` | Library header/count/first row/actions visible; member selection/pinning; Clear Recent cleared preview while preserving saved items; Available file-reference metadata. Transparent image fixture, hidden selection and unresolved export/focus mismatch produced no export. Winnel required forced termination; producer quit normally. Later final-source success does not erase this historical failure. |
| `5905897` | Capture began off; opaque 16×16 PNG preview; empty-Pinned scope and changed query cleared selection/preview/actions; generated file reference Available. Destination cancellation left no files. Reviewed mixed Markdown/image export produced 289-byte Markdown and one 187-byte PNG: 128 opaque orange and 128 opaque blue pixels; only file-reference metadata exported. Confirmation's post-action AX read failed, so inspected output files establish the outcome. Native JSON format picker remained unverified due to persistent focus disagreement. Both synthetic apps exited normally; identified temporary vault/reference removed, export retained. |

Historical offscreen renders comprise 13 component appearance checks. An active-preview synthetic measurement rendered a large image. These do not establish window interaction, keyboard, VoiceOver or complete appearance/scaling behavior. Semantic text replacement does not prove physical keyboard delivery.

## Capture fixtures

Real named-board provider callbacks replaced the board or added a concealed marker during reads; complete snapshots were discarded. Excluded synthetic source requested zero provider callbacks. AppKit warned about synchronous promise fulfillment from a background thread; passing in-process races do not establish all external providers are reliable or cancellable.

The initial timed probe produced 20 copies at each cadence: 50/250/1250 ms yielded 1/4/20 captures and 19/16/0 misses. The final `5905897` aggregate yielded 1/3/20 captures and 19/17/0 misses. Inactive-host scheduling used 1-second polls plus 150-ms settling. Task sleeps are requested cadence, not guaranteed deadlines. Ten writes before polling retained one latest copy and missed nine. These are observations, not capture-rate guarantees. Controller backpressure permits one pending save and deliberately skips later copies while busy.

## Performance

Hosted probes instantiate AppModel and PaletteView, omit AppDelegate/global shortcuts, and measure synthetic local work. Concurrent UI/build/test activity overlapped host resources. No lock/sleep prevention, security change or threshold change was used.

| Attempt / source | Recorded outcome |
|---|---|
| 1, historical | Exit 1 after 478.047 seconds, capture inactive/suspended. |
| 2, historical | Exit 1 after 1417.600 seconds, capture suspended, no recovery error; exact lifecycle notification unknown. |
| 3 / `3306e42` | Exit 0 after 1800.307 seconds; mean CPU 0.1235% of one core, peak sampled RSS 109.94 MiB. |
| 4 / `9dde333` | Exit 1 after 159.674 seconds, capture suspended, no recovery error; exact lifecycle notification unknown. |
| 5 / `9dde333` | Exit 0 after 1800.376681 seconds; mean CPU 0.1422625%, peak sampled RSS 111.734375 MiB, capture active. |
| 6 / `0d93cc9` | Exit 0 after 1800.485816 seconds; mean CPU 0.125492%, peak sampled RSS 58.15625 MiB, capture active. |
| 7 / `5905897` | Exit 0 after 1800.3767955416697 seconds; mean CPU 0.1353669968439444%, peak sampled RSS 116.46875 MiB; capture active throughout and before shutdown, no recovery state. Source hashes matched the pinned revision. Probe executable SHA-256 `c246aeecbdb51128e072f079ea8b0d82a3ce398d6862a845ff21c0567c525150`. |

The final local idle fixture passed its thresholds. It does not establish reference M1 acceptance, true cold launch or actual shortcut-to-visible timing. Historical 1200-item offscreen core-search p95 was 3.094 ms and hosting-layout p95 0.002708 ms; failed attempt 1 measured encrypted search p95 6.155 ms and layout p95 0.004792 ms; baseline attempt 3 measured encrypted search p95 7.145 ms and layout p95 0.003042 ms. These component measurements do not establish real palette-opening latency.

## UI revamp verification

Recorded 2026-10-04 for the [Supaste-informed UI revamp](ui-revamp.md). This is a new source candidate; earlier native and resource observations above do not establish acceptance of it.

- 125 XCTest tests passed with zero failures under test-process network denial, exit 0. The two additional AppModel tests exercise type filtering of authoritative payload search, preservation of matching selection, hidden-selection cleanup, cancellation of a pending hidden Copy and survival of an existing queue.
- The optimized app and synthetic producer built with the existing toolchain and passed ad-hoc signature verification. This remains a local development build without Developer ID signing or notarization.
- Diagnostics generated 29 actual SwiftUI raster renders from a 1200-item synthetic in-memory state. Inspected light/dark views include palette, selected Library, Settings categories, onboarding, recovery, export, queue, combination and selection order. Minimum viewports include palette/queue 620×420, Library 900×500 and export 500×380. A larger-text/high-contrast hosting variant is included. Stack selection contrast, empty-state overflow and fixed export footer were corrected after inspection.
- These renders do not verify actual scroll input, native sheet placement, keyboard or VoiceOver. Combination shows an unavailable preview; selection order shows a single item with disabled arrows. No populated combination or multi-item reorder acceptance follows from those images.
- During integration, the native synthetic producer's accessibility tree was readable. Winnel's UI connection closed before providing its window state, so native export/category/filter/keyboard flows were not verified. The producer exited through Command-Q. The exact disposable Winnel process was stopped and its identified temporary vault cleaned up; no normal-quit acceptance is claimed for this attempt. No personal clipboard or privacy settings were changed.

The revamp application-source fingerprint is `f82bb7ae1a2d8a917c8f9f8a37fb10518177be1412ab83a2677dfb33f28a08ae` (SHA-256 of compact sorted-key JSON mapping every regular file in Sources, Tests and scripts plus Package.swift to its SHA-256). Executable SHA-256: `a7994d3f29a80d83bb0e93b1c10bec19e6142a983d0feffe039314756b96657d`. The extracted development ZIP passed signature and binary/license equality checks. The private receipt records the per-file hashes, archive hash, command exits and the native blocker. The public summary intentionally excludes machine-specific paths, process identifiers and raw observations. The full PRD goal remains incomplete.

## PRD follow-up

Recorded 2026-10-04 after the initial UI revamp. Onboarding now displays the configured palette shortcut and starts practice capture from the explicit capture toggle, subject to OS consent. Completing onboarding preserves an indefinite or timed pause chosen during practice. Palette and saved-stack Combine controls disable unsupported image/file selections and display an explanation; backend payload validation remains in place.

- **131 XCTest tests passed, zero failures, exit 0**, with test-process network denied. New named-board regressions cover capture before onboarding completion, exclusion of earlier clipboard contents, separate default-off conveniences, final capture-off winning a pending enable, and preserved pauses until explicit Resume. Shortcut formatting, Combine eligibility and ordered mixed JSON export have new coverage.
- The pause regression first failed against the old completion behavior. The first fix retained the pause but exposed a shared guard that labeled indefinite pause as disabled. Both failures were retained; the final suite passed after the guard was corrected.
- Mixed JSON tests decode exact ordered text/link/image/file records, timestamps, provenance, citations and unavailable/relative references. Both image-included and image-omitted exports match preview bytes on disk; included captured asset bytes and references match exactly. Synthetic image bytes are opaque test data, so this test does not establish image decoding or native export interaction.
- The optimized ad-hoc package built successfully. Extracted signature verification and executable/license equality checks passed. Diagnostics generated **31 actual SwiftUI renders**, adding minimum onboarding and unsupported-Combine views. Inspected minimum palette/Library layouts retain visible explanations and actions; onboarding keeps its footer while the body scrolls. This does not establish physical scrolling, keyboard or VoiceOver behavior.
- A fresh native inspection attempt on the preceding `5373a3d` candidate failed before Winnel window state, while the synthetic producer remained readable. Owned fixture processes and temporary storage were cleaned up. No new native acceptance is claimed for this follow-up.

Application-source fingerprint: `cb5f3bc0a7cf0c6850a6483a8b95a07dfdc1b7d8375215bb163a5f0dd6c25041`, using the same per-file method above. Executable SHA-256: `904b3ee7d6ec500cd36a37c8cac79d1a2d0ffabdb296729ccfa8926ee8445492`. Development ZIP SHA-256: `883264456dc0a85fa81432895e657a76902ac6ab01385aa079a807870ec80cd9`. Private receipts retain command exits, source hashes and earlier failed regression logs. The full PRD goal remains incomplete; the production direct-paste allowlist remains empty.

## Remaining verification

Use synthetic fixtures and record source revision, OS/toolchain/device, exact steps, expected versus actual output and failures. Avoid extrapolating historical observations to later binaries.

- Capture/privacy: real consent, denial/revocation, lock/sleep/user switch, third-party markers/provider behavior, protected files and cross-device clipboard isolation.
- Clipboard/paste: exact app/version/build/control trials, adversarial focus/caret/modifier changes and observed destination consumption; production direct-paste allowlist remains empty.
- Library/retention: durable production reopen, age/count/storage boundaries in native UX, saved-item deletion/recovery and RAM-only lifecycle.
- Combine/export: complete five-format native preview, JSON selection/export, missing/protected/relative file labels and remaining cancellation/collision flows.
- Queue: shortcut configuration/conflicts, mode changes, Escape and real lifecycle cancellation.
- Recovery: actual Keychain denial/lock, corruption, disk-full and revoked permission causes.
- Accessibility/appearance: all keyboard and VoiceOver flows, sizing, light/dark, scaling, contrast and reduced motion.
- Performance/release: cold launch/palette/reference M1/macOS 14/external display, two-week beta, naming checks, signing/notarization and binary release.

See [compatibility](compatibility.md), [requirements](requirement-evidence.md) and [release checklist](release.md) for acceptance bounds.
