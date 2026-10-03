# Winnel

Winnel by Made Ordinary is a native Mac clipboard history and saved-stacks app. The MIT-licensed source is public at [madeordinary/winnel](https://github.com/madeordinary/winnel). Core processing is local. Capture requires opt-in. Recent history defaults to 24 hours or 200 unretained items. Pins and saved stacks are deliberate persistent exceptions.

This is a development implementation of v0.1. The [requirement/evidence matrix](docs/requirement-evidence.md) distinguishes source, passing tests, observed behavior and open gates. Direct paste is implemented conservatively but its supported-app list remains empty until real compatibility tests pass. Manual Copy is the fallback. No signed/notarized public release is claimed.

The local goal remains incomplete. PRD v1.2 accepts clipboard-provider allocation exposure and requires two serialized-payload admission stages, now implemented and tested. Bounded native tests have observed synthetic capture, manual Copy, search, stacks, queues, retention and generated-key recovery. Complete keyboard/VoiceOver, direct-paste outcomes, OS compatibility and unexercised native regression checks remain open. Final-source opaque preview, selection clearing, mixed Markdown/PNG export and normal synthetic-app shutdown are observed. See the [handoff](docs/handoff.md) and [verification summary](docs/verification.md) for exact revisions, results and remaining gates.

Attempt 7 on exact `5905897` completed with exit 0 after 1800.3767955416697 seconds, mean CPU 0.1353669968439444% of one core and peak sampled RSS 116.46875 MiB; capture remained active and no recovery state was present. [Recorded verification](docs/verification.md#performance) preserves source and executable provenance; raw receipts remain local. Hosted probes omit AppDelegate/global shortcuts; reference-device acceptance, true cold launch and shortcut-to-visible timing remain unverified. Historical interrupted runs remain documented. [Measurement scope](docs/verification.md#performance) distinguishes each binary's results from reference-device acceptance.

## Build and run

Requires Apple silicon and the existing Xcode 27.0 toolchain (Swift 6.4, macOS SDK 27.0). Deployment target is macOS 14; compiling for that target does not establish runtime compatibility on macOS 14.

```sh
bash scripts/test.sh
bash scripts/build.sh
open build/Winnel.app
```

The build creates an ad-hoc signed development app, with no external Swift package dependencies. `DEVELOPER_DIR` is set only for each command; the global Xcode selection stays unchanged. For an optimized bundle:

```sh
CONFIGURATION=release bash scripts/build.sh
```

Unit/platform tests use synthetic data, temporary vaults and named pasteboards. Run tests in a local environment allowed to contact macOS pasteboard services. A sandbox that blocks those services cannot establish clipboard behavior.

Additional local verification and packaging:

```sh
bash scripts/test-offline.sh    # deny network for this test process only
bash scripts/diagnostics.sh     # render actual views with synthetic state
bash scripts/performance.sh    # full 30-minute synthetic encrypted fixture
bash scripts/preview-performance.sh # separate large text/image preview measurement
bash scripts/package.sh        # optimized ad-hoc development ZIP and receipts
```

Diagnostics require a built bundle. Offscreen renders establish component appearance, not keyboard, VoiceOver or cross-app interaction. Performance reports preserve failures and state their warm-cache conditions.

## Safe development fixture

```sh
bash scripts/build.sh
bash scripts/run-fixture.sh
```

This launches the dedicated Winnel Fixture and `Winnel --fixture`. The fixture uses `org.madeordinary.winnel.fixture`, a named pasteboard, and a temporary encrypted store with an in-memory test key. Capture and ordinary Paste in the fixture editor use that named board. The secure test field and other inherited AppKit actions have not been exercised; no whole-app clipboard-isolation claim is established. Use the three-copy practice or the fixture's Copy next synthetic sample button. Fixture mode disables update traffic. Do not confuse its observations with third-party app compatibility.

The fixture also offers **Copy synthetic PNG** (a generated 16 × 16 checkerboard, `public.png`) and **Copy synthetic file reference** (`public.file-url`). The file button creates only `Synthetic reference.txt` inside a unique `winnel-file-fixture-<UUID>` folder in the system temporary directory; normal fixture shutdown removes that folder. These buttons write only the named fixture pasteboard and leave the three-text-sample cycle unchanged. The editor remains a plain-text Paste destination; use Winnel's captured preview and explicit export flow to inspect the image/file representations. File references may become missing after fixture shutdown, and no private files are opened.

### Recovery fixture

```sh
bash scripts/build.sh
open -n build/Winnel.app --args --fixture-recovery
```

This mode implies fixture isolation and opens the real recovery surface. It creates a new temporary vault containing one encrypted synthetic pinned text item and saved stack, then withholds its in-memory test key. Capture starts off; update checks, launch-at-login registration and Accessibility permission requests are disabled. It uses a separate named pasteboard and accepts no vault path or key arguments.

**Retry safely** releases only that process's fixture key and reloads the preserved sample; find it under Pinned or Saved Stacks. **Export encrypted recovery copy…** can copy ciphertext while the key is unavailable. **Reset Winnel data…** requires the existing confirmation and removes the fixture content; Retry after reset does not reseed it. Normal quit removes the temporary vault. The test key is never saved, so exported ciphertext cannot be reopened after that process exits.

This exercises simulated key unavailability and the actual recovery controls. It does not establish real Keychain denial/lock behavior, durable backup recovery or a manual verification record by itself.

## Everyday controls

Open the palette with Command-Shift-Space; use Command-Shift-N for the explicit queue's Next action. Change either shortcut in Settings. Ordinary Command-V remains the system paste command. The menu bar opens the palette, saved stacks and Settings.

Enable capture in onboarding or Settings. Pause immediately or until a displayed time, exclude apps by bundle identity, search, pin, save ordered stacks, combine text, or export the previewed material. Copy and Paste intentionally replace the clipboard. The app never restores old clipboard contents after a delay.

Accessibility is optional and requested only from an explicit user action. Clipboard permission may also be controlled by macOS. A denied or ambiguous permission or target uses visible recovery or manual behavior. The app does not grant permissions itself. Terminal, secure, unknown and unvalidated targets use manual Copy. A paste-event dispatch is not proof the destination consumed it.

## Storage and recovery

CryptoKit AES-GCM encrypts app content. Winnel stores its key in its own non-synchronizing Keychain item. Payloads, paths, stack names and indexes have no plaintext disk fallback. No cloud backup or account exists. RAM-only retention keeps unsaved recent payloads in memory; saved items remain deliberate encrypted exceptions. RAM previews/queues are bounded.

Keychain, corruption and write errors pause affected actions and preserve existing saved content. Recovery offers Retry, encrypted recovery export and an explicit reset. Encrypted recovery files still require the original key. The device-bound key means copied ciphertext alone is not a migration or backup solution. Export needed content intentionally while access works.

Clear Recent preserves pins and stacks. Delete Everywhere removes all selected references. Delete All Data clears app content and queues. None of these erases exports, original files, backups or the system clipboard. Clear System Clipboard is a separate action and rechecks the approved change counter. No forensic erasure claim is made.

## Privacy and release status

There is no analytics, automatic crash upload, sync, AI, remote preview or background backend. Optional update checks are separately off by default. See [network and privacy](docs/network-and-privacy.md) for endpoint, data and signature behavior.

[Compatibility](docs/compatibility.md), [dependency inventory](docs/dependencies.md), [beta plan](docs/beta-plan.md) and [release preparation](docs/release.md) describe the remaining gates. The real two-week beta, other hardware/OS observations, public signing/notarization, naming clearance and binary-release publication require human actions or unavailable environments.

Original app code is MIT. Serel is development tooling only; upstream notices are in `THIRD_PARTY_NOTICES/`. Start with [CONTRIBUTING.md](CONTRIBUTING.md), `PRD.md` and the public [architecture](docs/architecture.md). Agent checkpoints, owner-specific instructions and raw observations are local Git-ignored files; see [documentation privacy](CONTRIBUTING.md#documentation-and-local-memory).
