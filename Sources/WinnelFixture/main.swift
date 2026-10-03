import AppKit

/// Synthetic app with its own pasteboard. Never reads the user's general pasteboard.
@MainActor final class FixtureTextView: NSTextView {
    let board = NSPasteboard(name: .init("org.madeordinary.winnel.fixture"))
    override func paste(_ sender: Any?) {
        guard let value = board.string(forType: .string) else { return }
        insertText(value, replacementRange: selectedRange())
    }
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        // NSTextView's default Paste validation consults the general clipboard.
        // Keep both validation and delivery inside this synthetic named board.
        if item.action == #selector(NSText.paste(_:)) {
            return isEditable && board.availableType(from: [.string]) != nil
        }
        return super.validateUserInterfaceItem(item)
    }
}
@MainActor final class FixtureDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var editor: FixtureTextView!
    var status: NSTextField!
    var counter = 0
    private var referenceDirectory: URL?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appMenu = NSMenuItem(); menu.addItem(appMenu); appMenu.submenu = NSMenu()
        appMenu.submenu?.addItem(withTitle: "Quit Winnel Fixture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenuItem(); menu.addItem(edit); edit.submenu = NSMenu(title: "Edit")
        edit.submenu?.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 660,height: 520), styleMask: [.titled,.closable,.resizable,.miniaturizable], backing: .buffered, defer: false)
        window.title = "Winnel Synthetic Fixture"
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 24,left: 24,bottom: 24,right: 24)
        let title = NSTextField(labelWithString: "Synthetic capture and paste destination")
        title.font = .systemFont(ofSize: 21,weight: .semibold)
        root.addArrangedSubview(title)
        root.addArrangedSubview(NSTextField(wrappingLabelWithString: "Copy buttons and Paste in the editor below use only the named Winnel fixture pasteboard."))
        let button = NSButton(title: "Copy next synthetic sample",target: self,action: #selector(copySample))
        button.setAccessibilityIdentifier("fixture-copy"); root.addArrangedSubview(button)
        let representations = NSStackView(); representations.orientation = .horizontal; representations.spacing = 12
        let imageButton = NSButton(title: "Copy synthetic PNG", target: self, action: #selector(copyImage))
        imageButton.setAccessibilityIdentifier("fixture-copy-png"); representations.addArrangedSubview(imageButton)
        let fileButton = NSButton(title: "Copy synthetic file reference", target: self, action: #selector(copyFileReference))
        fileButton.setAccessibilityIdentifier("fixture-copy-file"); representations.addArrangedSubview(fileButton)
        root.addArrangedSubview(representations)
        status = NSTextField(labelWithString: "No synthetic copies yet"); root.addArrangedSubview(status)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        editor = FixtureTextView(frame: .init(x: 0,y: 0,width: 600,height: 200)); editor.isRichText = false
        editor.font = .monospacedSystemFont(ofSize: 15,weight: .regular)
        editor.string = "Paste synthetic samples below:\n"
        editor.setAccessibilityIdentifier("fixture-editor"); editor.setAccessibilityLabel("Synthetic paste destination")
        scroll.documentView = editor; root.addArrangedSubview(scroll)
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true
        scroll.widthAnchor.constraint(equalTo: root.widthAnchor,constant: -48).isActive = true
        let secure = NSSecureTextField(); secure.placeholderString = "Secure field — direct paste must be refused"
        secure.setAccessibilityIdentifier("fixture-secure"); secure.setAccessibilityLabel("Secure test field")
        root.addArrangedSubview(secure)
        window.contentView = root; window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func copySample() {
        let samples = ["A calmer place for every copy.","https://example.com/winnel-fixture","#C87F56"]
        let board = editor.board
        board.clearContents(); board.setString(samples[counter % samples.count], forType: .string)
        counter += 1; status.stringValue = "Synthetic copy \(counter)"
    }
    @objc func copyImage() {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 64, bitsPerPixel: 32) else { status.stringValue = "Synthetic PNG generation failed"; return }
        for y in 0..<16 { for x in 0..<16 { bitmap.setColor((x + y) % 2 == 0 ? .systemOrange : .systemBlue, atX: x, y: y) } }
        guard let png = bitmap.representation(using: .png, properties: [:]) else { status.stringValue = "Synthetic PNG generation failed"; return }
        editor.board.clearContents()
        status.stringValue = editor.board.setData(png, forType: .png) ? "Synthetic PNG copied: 16 × 16 pixels" : "Synthetic PNG copy failed"
    }
    @objc func copyFileReference() {
        do {
            if referenceDirectory == nil {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("winnel-file-fixture-" + UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                referenceDirectory = directory
            }
            guard let referenceDirectory else { return }
            let file = referenceDirectory.appendingPathComponent("Synthetic reference.txt")
            try Data("Synthetic Winnel file reference. No personal content.\n".utf8).write(to: file, options: .atomic)
            editor.board.clearContents()
            status.stringValue = editor.board.setString(file.absoluteString, forType: .fileURL) ? "Synthetic file reference copied: Synthetic reference.txt" : "Synthetic file reference copy failed"
        } catch { status.stringValue = "Synthetic file reference generation failed" }
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let referenceDirectory { try? FileManager.default.removeItem(at: referenceDirectory) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
let delegate = FixtureDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
