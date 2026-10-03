# 002 — Clipboard provider allocation feasibility

Status: **Accepted 2026-10-02**. Scope: PRD C-09; the architecture remains a single process with no helper. This decision does not grant OS permissions or expand product scope.

`SnapshotReader` checks source/exclusions/markers before requesting a representation. It then calls AppKit's `NSPasteboardItem.data(forType:)`, which returns a complete `Data`. The provider API has no byte-length preflight or bounded streaming parameter at this boundary. Checking `Data.count` can reject an oversized result before retaining, decoding or encrypting it, but cannot prevent that provider call from allocating it first. Source: `Sources/WinnelPlatform/PasteboardService.swift`; tests cover the resulting limits and changed/marked providers, not preallocation prevention.

Current safeguards: explicit representation allowlist, serialized capture ceiling 20 MiB, image dimensions/pixels inspected before thumbnail decoding, bounded thumbnails, bounded metadata and content-operation buffers, one serialized capture worker, and no general-clipboard test reads. A stalled external provider can still block its worker; no claim of universal provider cancellation is made. The initial allocation remains an accepted denial-of-service/memory risk under revised C-09; no claim of a process-wide memory ceiling is made.

Alternatives considered:

- Reject all provider-backed data: would also reject ordinary content without a reliable way to distinguish its eventual size, breaking accepted capture scope.
- Separate process with a resource limit: potentially isolates allocations, but adds a helper and changes the PRD's single-process/no-helper constraint; not authorized as a silent fix.
- Keep the single process and explicitly revise the acceptance boundary: retains current product scope but accepts provider-allocation exposure. This is the boundary adopted by PRD v1.2.

Original proposal, retained as decision history: “Enforce the 20 MiB serialized retained-payload limit before decode, indexing and persistence. Clipboard-provider retrieval may allocate data before its size is known; perform it off the UI thread, serialize retrieval, discard oversized results and document that OS/provider boundary. Establish independent decoded-image and preview-cache limits.”

## Accepted boundary and implementation

Keep the single native process and accept the provider-allocation exposure. PRD v1.2 states both concrete admission stages: the complete acquired raw representation payload must fit 20 MiB serialized before content parsers run; the final payload, including derived RTF text and file metadata, must fit 20 MiB serialized before publication, indexing and persistence. Retrieval remains serialized and off the UI thread; image dimensions/pixels and preview buffers retain their independent bounds.

Earlier code parsed before the complete serialized input check and repository indexing before its own size guard. The implementation moves input admission ahead of content parsing and repository admission ahead of plaintext/search/fingerprint work. An admitted RTF/file input may still be rejected when derived output exceeds the final budget. The serialized limits do not claim to measure or cap parser-internal allocations.

Positive consequence: native single-process delivery and safe supported representations remain intact with explicit input and retained-output limits. Negative consequence: an oversized external provider can cause a memory spike or crash before rejection; a blocked provider can still occupy its worker. Process isolation is not authorized or implemented by this decision.

Direct-paste compatibility, interactive accessibility, performance and supported OS/device evidence remain separate acceptance gates. This decision alone does not complete the application goal.
