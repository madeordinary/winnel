# UI revamp rationale

Review date: 2026-10-04.

Winnel’s revamp improves recognition, navigation and the visibility of existing workflows. Supaste’s public product materials informed the comparison; Winnel retains its own native, offline, free and open-source product scope. The implementation uses SwiftUI controls, system colors, clear text and restrained cards. Winnel keeps its own branding and feature scope.

## Research and evidence boundaries

The research reviewed official website content, promotional interface imagery, release articles and privacy documentation. Supaste was not installed or exercised. Advertised interactions establish design references, not measured usability, performance, accessibility, security or paste compatibility. Winnel’s implementation and its recorded verification remain separate sources of evidence.

The [homepage and FAQ](https://www.supaste.com/) describe rapid retrieval through several surfaces alongside broader collection management. The homepage advertises visual history, categories, app/type filtering, Quick Paste, a shelf, Library, combined clips, OCR, inline shortcuts and reminders. FAQ questions address capture, storage and optional sync. Browser text extraction did not expose every accordion answer, so the research does not treat those answers as a complete specification.

The detailed official release sources are:

- [v1.1, June 5](https://www.supaste.com/updates/supaste-v1.1-is-now-available.): Library, customizable shortcuts, manual capture, ignored apps, pins, bulk actions and app/type search filters.
- [v1.2, June 10](https://www.supaste.com/updates/supaste-v1.2-is-here-ocr-bulk-copy-quick-notes-and-more): shelf placement and sizing, manually created notes, inline shortcuts, searchable image text, combined copying and image actions.
- [v1.3, June 20](https://www.supaste.com/updates/supaste-v1.3-is-here-new-views-color-picker-screen-text-capture-and-more): collection layouts, board columns, sequential history paste, ordering preferences, favorites shortcuts and retention based on use.
- [v1.5, July 14](https://www.supaste.com/updates/supaste-v1.4-is-here): keyboard navigation, Space preview, Enter paste, configurable click behavior and text conversions. The page retains an older v1.4 URL slug; its title identifies v1.5. Performance statements have no published measurements in the article.
- [v1.6, July 16](https://www.supaste.com/updates/supaste-v1.6): optional filter/collection chrome, clip sizing and video preview changes.
- [v1.7, July 24](https://www.supaste.com/updates/supaste-1.7): iCloud, automatic filtering, Dropbox sharing, Apple Intelligence tools and shortcut removal.

The [roadmap](https://www.supaste.com/roadmap) exposes a feedback invitation in browser-readable content; no delivery commitments were established. The [privacy policy](https://www.supaste.com/privacy), dated May 29, describes local processing, capture controls, imperfect sensitive detection and network use for link previews and licensing. Its no-sync statement predates the July sync announcement. This is a public documentation discrepancy, not evidence of improper data handling.

## Lessons and Winnel choices

The choices below are design judgments derived from the reviewed materials, not claims that Supaste’s implementation has been validated.

| Observed design lesson | Winnel choice |
| --- | --- |
| Retrieval and organization serve different jobs. | Keep the palette centered on finding and using; make Saved Stacks the deliberate organization surface. |
| Recognizable content reduces dependence on remembering exact text. | Give item rows clearer excerpts, type symbols, source labels, copy age and pin status; keep the selected preview alongside results. |
| Categories and filters answer different questions. | Use Recent, Pinned and All items for browsing, with a separate content-type filter. Search continues to include saved and recent items. |
| Preview should precede a consequential action. | Keep preview visible and label Copy/Paste explicitly; retain existing paste validation and fallback behavior. |
| Reusable collections need visible structure. | Show stack counts and member order; expose Combine and Export directly in the stack header. |
| Combined copying and sequential use are distinct workflows. | Preserve deterministic combinations and the explicit queue with its existing position and controls. Do not start traversing history automatically. |
| Extensive preferences need organization. | Divide Settings into Capture, Storage, Shortcuts, Privacy and General, while retaining native controls. |
| Compact surfaces benefit from restrained chrome. | Use consistent headers, system surfaces and contextual actions; avoid introducing multiple layouts or placement preferences in this change. |

## Concrete interface changes

The palette gains a clearer header, capture-state label, prominent search field and search-clearing control. Native browse and type pickers narrow the displayed content. Selected rows have a visible border and background. The action bar brings Save stack and Combine forward, displays selection counts, and keeps the default Copy/Paste action distinct. Filtered empty states offer a route back to all types.

Saved Stacks retains a native sidebar and ordered membership list. Stack names and counts have stronger hierarchy. Combine and Export are visible actions; rename and deletion remain contextual. Unsupported image/file selections disable Combine and show an explanation in both palette and stack actions. Item detail separates preview, metadata, membership-specific source links and membership management. Removing one membership and deleting an item everywhere remain different choices.

Settings replaces the single long sequence of cards with five native segmented categories. Retention and deletion controls belong to Storage, capture and exclusions to Capture, and permission-aware paste behavior to Shortcuts. Recovery remains available in every category. Existing explanations and confirmation flows stay present.

Onboarding adds three benefit summaries and numbered capture, practice and optional-convenience sections. Its scrollable body has a persistent Get started footer. Capture, direct paste, launch at login and update checks remain off initially. The capture toggle starts capture for practice immediately, subject to OS consent. Onboarding displays the configured palette shortcut; finishing setup preserves a pause chosen during practice. Permission requests remain explicit actions.

Export options use native radio choices and separate options, selected content and destination guidance. Recovery visually separates retry, preservation and reset. Shared headers, cards and type badges use adaptive system colors and text labels; decorative symbols do not replace accessible names.

## Scope and deferred experiments

This change does not add cloud sync, accounts, analytics, AI, OCR, screen capture, remote link previews, inline text expansion, reminders, video behavior or automatic history sequencing. It does not expand paste compatibility or change storage and capture safety requirements.

Future experiments could compare compact and spacious density, evaluate alternate collection presentations, or test a dedicated preview shortcut. Each requires a demonstrated user need, explicit scope and suitable keyboard, accessibility and lifecycle verification. These are research directions, not product commitments.

## Verification

The initial revamp passed 125 network-denied XCTest tests, including two regressions for type-filter search, selection and pending Copy cancellation. The optimized local app builds and uses an ad-hoc development signature. Its diagnostics generate 29 actual SwiftUI component renders with synthetic data, covering light/dark surfaces, Settings categories, palette/queue minimum 620×420, selected Library minimum 900×500 and export minimum 500×380. Inspection found and corrected low-contrast stack selection, an overflowing empty state and export content that needed scrolling while keeping its footer visible.

These are component appearance checks. The native test producer was readable, but the UI connection repeatedly failed when inspecting Winnel, so no new native JSON-export or keyboard result is claimed. VoiceOver, complete scrolling/focus behavior, real consent and cross-app paste remain unverified. The combination and selection-order renders cover their supplied empty/single-item state only. See [verification scope](verification.md#ui-revamp-verification) for provenance and remaining limits.

The subsequent [PRD follow-up](verification.md#prd-follow-up) adds tested onboarding practice/pause behavior, configured shortcut labels, shared Combine eligibility and a mixed JSON export regression. Native acceptance remains a separate gate.
