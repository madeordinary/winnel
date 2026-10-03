# Network and privacy

Core capture, storage, search, stacks, combine, export and clipboard actions have no network client. No accounts, analytics, crash-upload SDKs, remote previews or model downloads are used. Rich text is not rendered through HTML. File references do not grant the app permission to read their contents.

Update checks are separately off by default. A manual Check for Updates action is explicit consent for one request; turning automatic checks on permits one check on launch and then no more than daily. Metadata endpoint: `https://api.github.com/repos/madeordinary/winnel/releases/latest`. This endpoint is chosen for eventual release hosting; a release may not exist yet. A 404 is shown as no published release, never as a verified up-to-date result.

Requests use HTTPS with system TLS validation, an ephemeral session, no cookies/cache/authentication and a generic Winnel user agent. Data fields: release endpoint path, standard connection metadata including source IP, Accept/User-Agent headers. No clipboard contents, paths, stack names, searches, account identifier or installation ID is sent. Release metadata is bounded to 256 KiB. Only stable release metadata and HTTPS GitHub links under madeordinary/winnel are accepted. No background download, install, launch or opening of links occurs. User-selected release-page opening is separate.

The update metadata is authenticated by HTTPS, not a cryptographic app-update signature. The app does not contain a self-updater. Before public release, downloaded app bundles must be Developer ID signed/notarized and verified by macOS; release tooling describes signing verification. No public signed build is claimed here.

The operating system clipboard is observable by other local applications. App writes request current-host-only contents, but this does not retract other apps' observations. Capturing never alters someone else's clipboard to suppress Universal Clipboard. Exclusions, source attribution and marker handling are best effort; pause is the clear option to stop collection. Polling can miss rapid copies.

App storage is encrypted at rest, including metadata. This does not protect against every program running as the user, a compromised/unlocked Mac, OS snapshots/backups or user-created exports. Clearing app data does not clear clipboard/exports/original files. A separate clear clipboard action rechecks the approved change counter; macOS exposes no atomic compare-and-clear API. No forensic erasure claim is made.

OS-controlled crash dumps are outside the app's erasure guarantee; Winnel never forwards them. Operational diagnostics contain codes/counts, not captured content. The recorded 123-test synthetic suite passed under a process sandbox denying network access; see [verification summary](verification.md#automated-tests). This establishes the exercised paths, not every OS path or a packet-level audit. Observation of optional update traffic remains a public-release gate.
