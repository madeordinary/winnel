# Release preparation

The source repository is public. Publishing a signed application is a separate release step; release operators must explicitly select their signing identity, credentials and destination. No Developer ID signature/notarization is claimed for the local ad-hoc bundle.

## Local package

```sh
bash scripts/test-offline.sh
bash scripts/package.sh
```

The package script records the source revision, working-tree status, actual signature and archive checksum in `build/distribution`. Keep those with the toolchain and command evidence. The separate fixture executable, Serel and test bundles are not included in Winnel.app. The app binary includes explicitly invoked synthetic diagnostics modes; none run during normal startup. The MIT license is included in bundle Resources.

## Human-controlled public release gates

1. Review docs/requirement-evidence.md and close all locally achievable requirements. Run unavailable hardware/OS, VoiceOver, real clipboard-consent and supported-app trials. Complete actual two-week beta and naming/distribution checks.
2. Select stable identifiers and obtain/confirm an appropriate Apple Developer ID identity. Review Keychain accessibility/backup and signing behavior on clean machines. No program enrollment or identity changes have been performed here.
3. Build an optimized app. Review entitlements and sign all embedded code with the selected Developer ID and hardened runtime; the current app has no helper daemon, third-party framework or embedded runtime. Ad-hoc signing in scripts/build.sh is for local development only.
4. Have the owner submit the archive through their chosen Apple notarization profile, inspect the result, staple the ticket and assess with Gatekeeper. Credentials and profiles remain outside repository source. This document intentionally does not select a stored credential automatically.
5. Test the downloaded/stapled candidate on a clean test Mac, including denial/revocation, update metadata, locked-key recovery and quarantine/Gatekeeper behavior.
6. Only after explicit publication authorization: create/use the official repository/release infrastructure, publish source, notices, reproducible commands, compatibility/network documentation and checksum. The update endpoint is documented but may return404 before this action.

Signing/notarization commands depend on the identity and profile chosen by the owner. Prepare the exact commands only after those are selected; never accept legal agreements, upload or modify signing identities as part of routine local build work.
