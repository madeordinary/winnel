# Toolchain and dependency inventory

| Component | Version/source | License/use |
|---|---|---|
| Original Winnel Swift code | This repository | MIT, LICENSE |
| Swift compiler | 6.4, swiftlang-6.4.0.34.1 | Apple Xcode toolchain, build only |
| Xcode | 27.0, build 27A266a | Existing Apple installation, not redistributed |
| macOS SDK | 27.0 | Existing Apple SDK, deployment target 14.0 |
| AppKit, SwiftUI, CryptoKit, Security, ImageIO, ServiceManagement, Carbon | Platform frameworks from selected SDK | System libraries; no bundled third-party runtime |
| Serel Memory | v0.6.0, 5f99244d648735db94429bf4e77571325160e5ec | MIT, development only, THIRD_PARTY_NOTICES/Serel-Memory-LICENSE |
| Serel Kit | v0.2.0, a4b7b29b9b80e72294e601da2c264f8a9082a795 | MIT, development only, THIRD_PARTY_NOTICES/Serel-Kit-LICENSE |

Package.swift has no remote dependencies. Serel files and test fixtures are not copied into the user app bundle. The separate fixture app is a development test tool. Intel support is not claimed. No models, analytics or crash upload SDKs are included.

Build scripts explicitly select the existing SDK and SwiftPM's `native` build backend. On this Xcode 27 toolchain, the default `swiftbuild` backend compiled with SDK 27 but emitted Mach-O SDK 14.0; explicitly specifying the SDK did not correct that stamp. The native backend emitted deployment minimum 14.0 / SDK 27.0. Native is deprecated in this toolchain; reassess this local workaround when upgrading, and verify the binary with `xcrun vtool -show-build`. No global toolchain setting was changed. [Recorded toolchain limitation](verification.md#build-and-package).
