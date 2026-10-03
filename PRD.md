# Winnel Product Requirements Document

| Field | Value |
|---|---|
| Version | 1.2 — C-09 provider-allocation boundary approved 2026-10-02; other product requirements unchanged |
| Readiness | Ready for Phase 0 feasibility and implementation planning; technical release gates are unverified |
| Owner | Made Ordinary |
| Public name | Winnel by Made Ordinary — approved 2026-10-01. Final naming checks remain outstanding; see [naming review](docs/naming-review.md). |
| Platform | Apple silicon Mac; deployment target macOS 14.0 |
| Technology | Native Swift, SwiftUI and AppKit |
| Release | Free, open-source v0.1; direct signed/notarized download |
| Supersedes | 2026-09-26 Stack discussion draft (historical; this document is canonical) |

## 1. Product and audience

The app helps a Mac user recover earlier copies and collect related text, links, images and file references into reusable groups. A keyboard shortcut opens a compact palette; the user selects a copy, pastes it, or combines several text items into one output.

> Copy freely. Bring back exactly what you need.

Primary users repeatedly move information between browsers, documents, messages, editors and AI tools. A common job is collecting several excerpts and links, then using them together in a document or new AI conversation. The product must also work well for someone who simply wants the thing they copied five minutes ago.

Recent copies are collected automatically only after capture is enabled. Saved groups are deliberate. We do not describe automatic clipboard observation as manual capture or imply that exclusions can detect every secret.

Success depends on a fast, understandable UI and useful collection/paste workflows. Existing clipboard managers and macOS clipboard history already cover much of this category; saved groups and open source are product choices, not claims of a unique invention.

## 2. Decisions fixed for v0.1

| Area | Requirement |
|---|---|
| Core loop | Copy normally → open palette → find/select → copy or paste |
| Durable organization | Pins plus named, ordered groups called stacks |
| Recent history | 24 hours or 200 unretained items, whichever limit is reached first |
| Storage budget | 20 MiB serialized payload per capture; 2 GiB managed data total; visible usage and limits |
| Capture | Explicit opt-in; pause, app exclusions, concealed/transient marker handling |
| Paste | Copy-to-clipboard always available; optional direct paste after Accessibility permission and compatibility validation |
| Sequential use | Explicit queue with a separate configurable Next shortcut; ordinary Command-V is never intercepted |
| Formatting | Deterministic text combination with preview |
| AI | No inference, model download, semantic search or rewriting in v0.1 |
| Network | Core functions work offline; optional update traffic only after user choice |
| UI language | English first; strings structured for later localization |
| License | MIT for original app code; dependency licenses and notices audited before reuse |
| Delivery | Single native Mac app; no backend, account, subscription, sync, helper daemon or mobile app |

Minimum OS is a release target, not proof of compatibility. Phase 0 must demonstrate behavior on macOS 14 and supported newer releases. An OS-target change requires an explicit PRD revision rather than an undocumented implementation change.

## 3. Launch scope and exclusions

v0.1 includes text and safe rich-text representations, URLs, bounded images, file references, color previews for recognized text literals, search, pins, saved stacks, combination, sequential use, exports, exclusions, pause, retention, launch at login and optional updates.

Outside v0.1: OCR, browser extensions, automatic source-page discovery, text expansion/templates, cloud or iCloud sync, shared libraries, generative AI, audio/video storage, automatic form filling, automatic submission and a notch surface. No calendar, microphone or screen recording access is required. Intel builds and an App Store edition are later decisions.

Direct paste remains part of the release requirements for a documented supported-app set. A per-app manual fallback is normal. Failure to demonstrate a viable supported-app set blocks that release claim and requires a scope revision; it is not permission to silently remove the feature.

## 4. Native interface and everyday flows

The app has onboarding, a menu-bar menu, a compact palette, a saved-stacks window and Settings. Every action works with keyboard and VoiceOver. Pointer hover is optional. The palette remembers its size and supports light/dark appearance, Reduce Motion and Increase Contrast.

### Onboarding

Explain capture and the 24-hour/200-item retention rule, then let the user enable capture. Show the keyboard shortcut and a three-copy practice example. Offer direct paste as an optional convenience, explaining Accessibility immediately before the macOS request. Launch at login and update checks are separate explicit choices, initially off. If the OS asks for clipboard access, explain the request and respect denial.

### Retrieve one item

Copy normally, open the palette, type to search, inspect a preview and select an item. Return uses the configured default action, visibly labeled Copy or Paste. Copy leaves the selected item on the system clipboard and dismisses the palette. Direct paste revalidates the original target before sending a paste event. Unsupported targets use Copy and tell the user to press Command-V.

### Collect and combine

Select recent entries and choose Create Stack, then name and reorder it. Select compatible text entries to preview one of: newline-separated text, bullets, numbered list, Markdown link list, or JSON string array. Copy, paste or export the exact preview. Original entries remain unchanged. Combine is disabled for unsupported mixed selections with a clear explanation.

### Sequential use

Select and order entries, start a queue, and use its dedicated Next action for one entry at a time. The indicator shows the current item, position, Copy Next/Paste Next mode, Back and Cancel. In manual mode each Next copies one item and the user pastes it. In direct mode each Next validates the currently intended target and sends a single paste request. The queue never sends Tab or Return. Blocked target or failed dispatch does not advance. Escape, five minutes without queue interaction, lock, sleep or user switch cancels it. Queue creation retains the selected entries only for that session; it does not turn them into permanent pins.

## 5. Functional requirements

| ID | Requirement and acceptance behavior |
|---|---|
| C-01 Capture lifecycle | Capture starts only after opt-in and stops on pause, quit, lock, sleep or user switch. Resume begins with the current pasteboard change counter and does not import items copied during the pause. State and failure are visible. |
| C-02 Ingestion | Read only supported types after checking exclusions and concealed/transient markers. Detect a pasteboard change during a read and discard the incomplete capture. Own writes carry an app marker and are not recaptured. Polling is bounded and backs off when inactive. |
| C-03 Type fidelity | Plain/rich text and URL representations are preserved from an explicit allowlist. Images use bounded decoding and previews. File references remain references. Unknown/private types, lazy file promises and oversized payloads are skipped without blocking normal copying. Color swatches are derived from recognized literal text, not a separate capture permission. |
| C-04 Provenance | Store copy time and source-app attribution when reasonably established; label inferred attribution and use Unknown when uncertain. Ordinary copied text often has no page URL: never invent one, scrape a browser tab, or infer a citation from nearby clips. A user can explicitly associate a copied URL with a stack item. |
| C-05 Exclusions | Match applications using stable identity. Check foreground/source evidence conservatively; uncertain attribution during an excluded-app transition is skipped. Exclusions and source inference are best-effort boundaries; Pause is the clear option when the user needs all capture stopped. No blanket promise to skip every password. |
| C-06 Deduplication | Consecutive identical user copies may share payload storage but record the latest actual copy time. Search, viewing or app-generated paste does not renew expiration. Rich representations and file identities are part of equality. |
| C-07 Search | Search captured text, stack names and known metadata locally. No image OCR or semantic inference. Highlight matching text and show content type and timestamp. Indexes/previews obey the same encryption and deletion rules as payloads. |
| C-08 Saved stacks | Create, rename, reorder, pin, remove membership and delete. An item may belong to several stacks without duplicating its payload. Removing a membership affects only that stack. Global deletion states all affected locations. |
| C-09 Limits | Expire eligible recent entries by age, count and storage budget, oldest first. Pins/saved items are never silently evicted. If saved data fills the budget, capture pauses with a management action. Enforce the 20 MiB serialized input-payload limit before content decoding, indexing and persistence. Clipboard-provider retrieval may allocate data before its size is known; perform retrieval off the UI thread, serialize it, discard oversized results and document that OS/provider boundary. Derived text/file metadata must also fit the final 20 MiB serialized retained-payload limit before indexing and persistence. Establish independent decoded-image limits and preview-cache budgets. See the approved [C-09 decision](docs/decisions/002-capture-allocation-feasibility.md). |
| C-10 Direct paste | Optional, compatible-app-only behavior as specified below. Permission loss immediately falls back to explicit Copy. No automatic retries into a different target and no form submission. |
| C-11 Queue | A separate shortcut and visible queue state; normal Command-V remains unchanged. Supported dispatch may advance, but UI must not claim the destination consumed the item merely because an event was sent. Back/retry lets the user recover. |
| C-12 Export | User-initiated Markdown, versioned JSON and optional image assets; preview destination and included content. File entries export metadata/links only in v0.1, never read/copy arbitrary referenced file contents. Missing or relative references are labeled. No export is automatically uploaded or opened. |
| C-13 Settings | Shortcut test, direct-paste toggle, retention, exclusions, pause, limits/usage, launch/update choices, clear controls and readable privacy information. Timed pause: 15 minutes, one hour or until tomorrow; the exact resume time is shown. |
| C-14 Failure recovery | Keychain unavailable, corrupt data, disk full, permission revocation or storage failure pauses affected work and preserves existing saved content. Never silently fall back to plaintext or replace a database/key. A visible recovery/export/reset choice is provided. |

### Paste destination and system clipboard contract

For palette-driven direct paste, capture target application, process identity, window and focused control where exposed before activating the palette. Revalidate that destination after restoring focus. Any competing user focus change, missing target or ambiguous state routes to Copy; do not chase a moved caret. Secure fields are blocked when identified. Phase 0 must establish a conservative compatibility list and zero wrong-target dispatches in its adversarial fixtures.

Queue mode intentionally allows the user to choose a new destination for each invocation, so it validates the target at that invocation. It never uses an old palette destination silently. Known terminal/shell targets and controls where pasting may immediately execute text use manual Copy in v0.1; not sending Return alone is not an execution guarantee.

Selecting Copy or Paste deliberately replaces the system clipboard. v0.1 does not restore an older clipboard after an arbitrary delay, which could overwrite a newer user copy. Writes should use Apple's local-host option where supported; test the behavior per OS. Other local apps can still observe the system clipboard, and the product cannot retract content they already obtained. Capture never modifies the original user's clipboard simply to suppress Universal Clipboard.

### Retention and deletion contract

- Retention choices are 1 hour, 24 hours, 7 days, or clear-on-quit (RAM-only recent history). Count/storage caps still apply. Saved stacks and pins are deliberate persistent exceptions.
- Clear Recent clears the recent view and releases content not retained by pins or stacks. It leaves saved content intact and says so.
- Removing a final saved reference returns an item to recent storage only if its actual copy timestamp remains within the configured retention window; otherwise it is purged.
- Delete Everywhere removes the selected item and all references from app-managed data after stating the affected stacks. Delete All Data clears content, indexes, previews and pending queues; settings may remain. Key handling must account for the active store and later recapture.
- Startup/wake enforces expiration before showing search results. Crashes and reboot cannot revive expired recent entries.
- Clearing app history does not erase the system clipboard, previous exports, backups or original files. A separate explicit Clear System Clipboard action is available; it must not clear a newer clipboard change than the user approved.
- Deletion means removal from active app-managed storage and its journal/cache lifecycle. No forensic erasure guarantee is made for SSDs, OS snapshots or backups. Key deletion is not a promise that existing exported plaintext becomes inaccessible.

## 6. Privacy, network and permissions

All core processing is on the Mac. Captured contents, paths, stack names, indexes and previews are encrypted at rest with an established authenticated-encryption design and a key stored in macOS Keychain. Search may use a bounded in-memory index. SQLite/sidecar files, journals and temporary files must not contain plaintext content. Do not implement novel cryptography.

This protects app-managed storage; it does not protect against every program running as the user, a compromised/unlocked Mac, OS clipboard observers or user-created exports. Imported rich text is rendered without executing HTML/scripts or fetching remote images. Link previews use local information only; no favicon or page-title network fetches.

No analytics or third-party crash upload SDK. App logs exclude captured text, URLs, titles and paths; operational logs use codes and counts. OS-controlled crash dumps are outside the app's erasure guarantee and must not be automatically forwarded by the app.

No-Accessibility mode remains useful but may still require OS clipboard consent. Do not request Input Monitoring, Full Disk Access or Screen Recording by default. Any newly necessary permission is a documented Phase 0 decision. Unavailable protected-file access results in an unavailable reference rather than broader permission demands.

Optional update checks may contact documented release infrastructure; manual checks are also available. Publish domains, data fields and authentication/signature behavior before beta. Direct distribution is a product choice for the selected paste workflow. An unsandboxed build cannot prove a no-network promise merely by omitting a network entitlement; inspect code paths and verify network behavior during testing.

## 7. Swift architecture and data model

- SwiftUI: onboarding, settings, saved-stack library and reusable views.
- AppKit: NSPasteboard integration, menu-bar item, panel lifecycle, shortcuts, focus restoration and compatible paste dispatch.
- A single app process, with capture, storage, search, export and presentation separated into testable components. Expensive work runs off the main thread.
- Entities: ClipboardItem (typed payload, timestamps, provenance), Stack, ordered StackMembership, Pin, ephemeral PasteQueue and Settings. Persisted schema is versioned and migrations are recoverable.
- Select an established local encrypted-storage implementation in Phase 0. Record the exact dependency versions, license and key/backup behavior before persisting real user content.
- Swift 6 language/concurrency direction with a pinned supported Xcode/SDK version in the project. Runtime APIs remain availability-checked against macOS 14. No embedded Python, Node, Electron or required inference runtime.
- Original source uses MIT. Reusing permissive projects requires preserving notices; copyleft dependencies cannot be casually relabeled MIT. Maintain dependency/license inventory and build instructions. Each app gets its own repository and storage keys; no shared permissions or content store with Within.

## 8. Performance, accessibility and release tests

Initial product budgets are targets to measure, not existing benchmark results. Reference fixture: M1 MacBook Air with 8 GB RAM, 200 recent entries and 1,000 saved entries with a documented text/image mixture. Include an external display, a newer Apple silicon Mac, lowest supported OS and latest stable supported OS. Publish the fixture sizes and warm/cold conditions.

| Gate | Passing result |
|---|---|
| Palette and search | Warm open p95 ≤100 ms; local search p95 ≤100 ms. Cold launch ≤2 seconds. No main-thread blocking decode. |
| Idle overhead | Mean CPU ≤0.5% where 100% means one logical core, over 30 minutes; idle RSS ≤150 MiB including frameworks on the fixture. Active preview budget is separately measured. |
| Capture fidelity | Supported representations survive round trips; concealed/transient/excluded/self-generated fixtures never enter retained history. Rapid-copy misses are measured; no unsupported “captures every copy” claim. |
| Paste reliability | ≥98% successful outcomes in the declared supported-app test matrix and zero wrong-target dispatches. Ambiguous/secure/terminal cases reliably use manual fallback. |
| Data lifecycle | Expiration, shared membership, clear-on-quit crash recovery, disk-full, locked keychain, corrupt payload, moved file and migration tests pass. No plaintext payload/index/journal artifacts in the chosen storage design. |
| Access and export | Keyboard/VoiceOver can complete onboarding, retrieve, manage a stack, combine, queue, export and delete. Reduced Motion/contrast and scaling work. Exports contain only previewed material. |
| Offline and privacy | Core works with network disabled. Optional update traffic contains no content. Denied/revoked permissions and OS clipboard-access changes are visible and recoverable. |
| Release quality | No unresolved data-loss or wrong-target defects; signed/notarized build; public source, dependency notices, build instructions and compatibility/network documentation. |

Product validation uses voluntary dogfood feedback rather than installed analytics: a new user retrieves an earlier copy within three minutes, and repeated users find saved groups useful during at least one real weekly workflow. Record actual research results before making adoption claims.

## 9. Delivery plan and feasibility decisions

1. **Phase 0 — prove platform behavior.** Validate clipboard consent on each supported OS; capture/source/exclusion limits; multi-type/file behavior; focus-safe paste and queue dispatch; encrypted storage/key recovery; shortcuts and VoiceOver. Produce a tested compatibility matrix, dependency decision and performance baseline. Use synthetic data. No feature is declared reliable merely because an API exists.
2. **Core alpha.** Capture, history, search, pins, pause, exclusions and manual Copy. Demonstrate expiration and encrypted persistence before regular private-data dogfooding.
3. **Workflow beta.** Saved stacks, combine/export, direct paste and explicit queue; complete the lifecycle and accessibility tests. Dogfood for two weeks with voluntary reports.
4. **Public v0.1.** Close release gates, complete final naming checks for Winnel, sign/notarize and publish source/builds. Domain/branding choices must not reshape stable data IDs after beta.

Feasibility failures are recorded with evidence and a proposed PRD amendment. They do not silently authorize remote processing, expanded permissions or dropping launch functionality. Future options include OCR, explicit local-model transforms, private sync and an iOS share extension. They require their own scope decision.

## 10. Sources and decision record

Finalized decisions: recent recovery plus deliberate saved stacks; 24-hour/200-item recent limit; optional Accessibility offered during onboarding; saved stacks, deterministic combine, direct paste and explicit sequential use in launch scope; English/Apple silicon first; no generative AI or sync in v0.1. The product name is Winnel. Final naming checks remain a release task, not an unresolved product boundary.

C-09 retains the single-process architecture with an explicit boundary: provider retrieval can allocate an oversized item before its size is available. This accepted technical limitation does not establish OS compatibility or change the direct-paste and accessibility gates. See ADR 002.

Technical references checked 2026-09-29:

- [Apple NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard) and [accessBehavior](https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-9k4t4): clipboard API and user-controlled access.
- [Apple currentHostOnly](https://developer.apple.com/documentation/appkit/nspasteboard/contentsoptions/currenthostonly): confines app-written clipboard contents to the current device; it does not prevent observation by other local apps.
- [Apple App Sandbox restrictions](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox): supports evaluating direct-paste distribution separately from basic clipboard storage.
- [Naming review](docs/naming-review.md): Winnel name approval and reasons for retiring the earlier Stack brand proposal.
