# UI revamp rationale

Review date: 2026-10-04.

Winnel’s revamp improves recognition, navigation and the visibility of existing workflows. Supaste’s public product materials informed the comparison; Winnel retains its own native, offline, free and open-source product scope. The implementation uses SwiftUI controls, system colors, clear text and restrained cards. Winnel keeps its own branding and feature scope.

## Research and evidence boundaries

The research reviewed official website content, promotional interface imagery, release articles and privacy documentation. Supaste was not installed or exercised. Advertised interactions establish design references, not measured usability, performance, accessibility, security or paste compatibility. Winnel’s implementation and its recorded verification remain separate sources of evidence.

The [homepage and FAQ](https://www.supaste.com/) describe rapid retrieval through several surfaces alongside broader collection management. The homepage advertises visual history, categories, app/type filtering, Quick Paste, a shelf, Library, combined clips, OCR, inline shortcuts and reminders. FAQ questions address capture, storage and optional sync. Not every FAQ answer was available in the reviewed text, so the research does not treat those answers as a complete specification.

The detailed official release sources are:

- [v1.1, June 5](https://www.supaste.com/updates/supaste-v1.1-is-now-available.): Library, customizable shortcuts, manual capture, ignored apps, pins, bulk actions and app/type search filters.
- [v1.2, June 10](https://www.supaste.com/updates/supaste-v1.2-is-here-ocr-bulk-copy-quick-notes-and-more): shelf placement and sizing, manually created notes, inline shortcuts, searchable image text, combined copying and image actions.
- [v1.3, June 20](https://www.supaste.com/updates/supaste-v1.3-is-here-new-views-color-picker-screen-text-capture-and-more): collection layouts, board columns, sequential history paste, ordering preferences, favorites shortcuts and retention based on use.
- [v1.5, July 14](https://www.supaste.com/updates/supaste-v1.4-is-here): keyboard navigation, Space preview, Enter paste, configurable click behavior and text conversions. The page retains an older v1.4 URL slug; its title identifies v1.5. Performance statements have no published measurements in the article.
- [v1.6, July 16](https://www.supaste.com/updates/supaste-v1.6): optional filter/collection chrome, clip sizing and video preview changes.
- [v1.7, July 24](https://www.supaste.com/updates/supaste-1.7): iCloud, automatic filtering, Dropbox sharing, Apple Intelligence tools and shortcut removal.

The [roadmap](https://www.supaste.com/roadmap) exposes a feedback invitation in browser-readable content; no delivery commitments were established. The [privacy policy](https://www.supaste.com/privacy), dated May 29, describes local processing, capture controls, imperfect sensitive detection and network use for link previews and licensing.

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
| Compact surfaces benefit from restrained chrome. | Use consistent headers, system surfaces and contextual actions; avoid adding placement preferences. The follow-up below adds Cards/List for the Library. |

## Initial interface changes

The palette gains a clearer header, capture-state label, prominent search field and search-clearing control. Native browse and type pickers narrow the displayed content. Selected rows have a visible border and background. The action bar brings Save stack and Combine forward, displays selection counts, and keeps the default Copy/Paste action distinct. Filtered empty states offer a route back to all types.

Saved Stacks retains a native sidebar and ordered membership list. Stack names and counts have stronger hierarchy. Combine and Export are visible actions; rename and deletion remain contextual. Unsupported image/file selections disable Combine and show an explanation in both palette and stack actions. Item detail separates preview, metadata, membership-specific source links and membership management. Removing one membership and deleting an item everywhere remain different choices.

Settings replaces the single long sequence of cards with five native segmented categories. Retention and deletion controls belong to Storage, capture and exclusions to Capture, and permission-aware paste behavior to Shortcuts. Recovery remains available in every category. Existing explanations and confirmation flows stay present.

Onboarding adds three benefit summaries and numbered capture, practice and optional-convenience sections. Its scrollable body has a persistent Get started footer. Capture, direct paste, launch at login and update checks remain off initially. The capture toggle starts capture for practice immediately, subject to OS consent. Onboarding displays the configured palette shortcut; finishing setup preserves a pause chosen during practice. Permission requests remain explicit actions.

Export options use native radio choices and separate options, selected content and destination guidance. Recovery visually separates retry, preservation and reset. Shared headers, cards and type badges use adaptive system colors and text labels; decorative symbols do not replace accessible names.

## Scope and deferred experiments

This change does not add cloud sync, accounts, analytics, AI, OCR, screen capture, remote link previews, inline text expansion, reminders, video behavior or automatic history sequencing. It does not expand paste compatibility or change storage and capture safety requirements.

The follow-up below adopts a second collection presentation. Rich media cards and a dedicated preview shortcut remain separate experiments requiring suitable keyboard, accessibility and lifecycle verification.

## Closer visual direction and competitor comparison

The initial revamp retained a large branded header, symbol-heavy rows and a warm accent. The revised direction gives content more space and reduces decorative color. It keeps native adaptive light/dark surfaces, uses cool blue for selection and primary actions, and makes ordinary type symbols neutral. The original stack icon follows the same blue accent.

The October 4 follow-up visually inspected Supaste's public demonstration, Paste's homepage product image, PastePal's official adaptive-grid image and Maccy's instruction image. These are promotional examples; no competitor was installed or tested. Layout observations do not establish runtime quality or feature parity.

| Reference | Visible or documented pattern | Winnel application |
| --- | --- | --- |
| [Supaste](https://www.supaste.com/) | The demonstration shows dark, minimal controls, compact category tabs, large content cards and blue selection borders. A separate preview gives the selected clip more space. | Reduce the quick-panel header; use neutral controls, recognizable excerpts, selected outlines and a collapsible Library inspector. |
| [Paste](https://pasteapp.io/) | The homepage image shows a horizontal strip of visual cards, small pinboard navigation and content-specific previews with colorful headers. | Keep reusable stacks easy to find and give content more room. Avoid adding a separate header color for every item type. |
| [PastePal](https://indiegoodies.com/pastepal) | The [adaptive-grid example](https://user-images.githubusercontent.com/2284279/288302879-cd7a4ea7-5988-4d91-8e37-600ca54b52b9.png) shows a compact sidebar, card grid and separate edge bar; its documentation describes raw and Quick Look previews. | Use a visual Library with a compact stack sidebar, while keeping retrieval in the quick panel. |
| [Maccy](https://maccy.app/) | Its [instruction image](https://maccy.app/img/maccy/Instructions.png) shows a compact search field, short results and visible shortcuts. | Preserve the native result list, search focus and direct explicit actions in the quick panel. |

The resulting Library defaults to adaptive ordered cards and provides a native Cards/List control. The inspector starts hidden and opens when a card is selected; the inspector button can hide it again. Cards show bounded metadata excerpts, item type, order, source attribution and pin status. Up/down controls preserve explicit stack ordering. The existing list remains available for native selection navigation, and the inspector retains preview, Copy, pinning, URL association and membership controls. Card selection itself does not copy or paste.

The quick panel starts with search and Library/settings controls, followed by browse/type filters and a visible capture state. It retains native multiple selection and the existing Copy/Paste, combination, export and queue contracts. The palette, Library and shared controls use the same adaptive blue accent; search-match highlighting also follows it.

This is a closer presentation, not full Supaste equivalence. Unselected image cards currently show metadata and a type symbol; image decoding remains in the bounded selected-preview pipeline. There is no thumbnail grid cache, horizontal shelf, remote link preview, new cloud/AI/OCR feature or expanded paste compatibility. A gallery of live image thumbnails would need a bounded loading design and separate lifecycle/performance verification.

## Keyboard and safety follow-up

A later review of the redesigned surfaces found interaction gaps that the appearance work did not address. The follow-up keeps the visual direction and changes behavior:

- **Keyboard-first palette.** Opening the palette starts a fresh session: the query clears, earlier selection-dependent work is revoked, and the newest visible item is selected. Re-focusing an open palette, or opening it while a sheet depends on the selection, keeps the query and selection. After a query change the first result is selected once results publish, unless the user chose a row first. Up and Down Arrow move the selection from the search field, and Return uses the default action. A hidden Edit menu gives text fields the standard editing shortcuts.
- **Honest capture state.** The palette, Settings and menu bar share one wording: Capture on, Capture off, Capture paused, or Paused while locked or asleep. The menu-bar symbol is slashed whenever new copies are not recorded. Controls that cannot apply are disabled. Wake after an observed lock waits for unlock; an explicit Resume after lock or sleep ends a suspension whose wake or unlock notice was missed and keeps capture off, paused or on as the user left it. Copies that are too large, invalid images or unsupported are reported in the status line; concealed and transient copies stay silent.
- **Queue outside the palette.** The menu bar shows the queue position and offers Next, Back and Cancel. A saved stack can start a queue, and the Library shows the queue strip. Escape cancels the queue only from the palette or Library.
- **Safer deletion.** Delete everywhere applies to every selected item and names the affected stacks. Shortening retention, unpinning, removing a stack membership or deleting a stack asks first when the change would remove items; the count comes from running the same library mutation on a copy.
- **Paste honesty.** While no app is verified for direct paste, Return is labeled Copy, paste-only controls are hidden, and Winnel does not offer the Accessibility request.
- **Denser rows and clearer content.** Rows drop the repeated type caption, show a coarse age that refreshes each minute, and use the native list highlight as the only selection style. New image items are named by format and pixel size. The Library header is shorter, selects a stack automatically, and opens the inspector from List view. Exclusions can be chosen from an app picker, storage values use binary units, and the per-copy capture limit is described as all formats combined.

Remaining design gaps: the Library header fits one row only in wide windows and otherwise uses two compact rows; the stack sidebar still combines the native highlight with its own selection outline; copy confirmations are shown in the status line rather than a transient notice; and the Next shortcut is registered globally even when no queue is active.

## Verification

The initial revamp passed 125 network-denied XCTest tests, including two regressions for type-filter search, selection and pending Copy cancellation. The optimized local app builds and uses an ad-hoc development signature. Its diagnostics generate 29 actual SwiftUI component renders with synthetic data, covering light/dark surfaces, Settings categories, palette/queue minimum 620×420, selected Library minimum 900×500 and export minimum 500×380. Inspection found and corrected low-contrast stack selection, an overflowing empty state and export content that needed scrolling while keeping its footer visible.

These are component appearance checks. The native test producer was readable, but accessibility-based automation repeatedly failed to read Winnel's window state, so no new native JSON-export or keyboard result is claimed. VoiceOver, complete scrolling/focus behavior, real consent and cross-app paste remain unverified. The combination and selection-order renders cover their supplied empty/single-item state only. See [verification scope](verification.md#ui-revamp-verification) for provenance and remaining limits.

The subsequent [PRD follow-up](verification.md#prd-follow-up) adds tested onboarding practice/pause behavior, configured shortcut labels, shared Combine eligibility and a mixed JSON export regression. Native acceptance remains a separate gate.
