import AppKit
let application = NSApplication.shared
if let index = CommandLine.arguments.firstIndex(of: "--performance") {
    guard index + 1 < CommandLine.arguments.count, CommandLine.arguments[index + 1].hasPrefix("/") else { exit(2) }
    let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
    var duration: Double = 1_800
    if let durationIndex = CommandLine.arguments.firstIndex(of: "--idle-seconds") {
        guard durationIndex + 1 < CommandLine.arguments.count, let value = Double(CommandLine.arguments[durationIndex + 1]), value.isFinite, value >= 1, value <= 3_600 else { exit(2) }
        duration = value
    }
    application.setActivationPolicy(.accessory)
    Task { @MainActor in
        do { try await FixturePerformance.run(outputDirectory: directory, idleSeconds: duration); exit(0) }
        catch { fputs("Winnel isolated performance fixture failed. See its progress report.\n", stderr); exit(1) }
    }
    application.run()
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--diagnostics") {
    guard index + 1 < CommandLine.arguments.count, CommandLine.arguments[index + 1].hasPrefix("/") else { exit(2) }
    let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
    application.setActivationPolicy(.accessory)
    Task { @MainActor in
        do { try await FixtureDiagnostics.run(outputDirectory: directory); exit(0) }
        catch { fputs("Winnel fixture diagnostics failed.\n", stderr); exit(1) }
    }
    application.run()
    exit(0)
}
let delegate = AppDelegate(fixtureMode: CommandLine.arguments.contains("--fixture"))
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
