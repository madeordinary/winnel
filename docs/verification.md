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
