import AppKit

/// Synthetic app with its own pasteboard. Never reads the user's general pasteboard.
@MainActor final class FixtureTextView: NSTextView {
    let board = NSPasteboard(name: .init("org.madeordinary.winnel.fixture"))
    override func paste(_ sender: Any?) {
        guard let value = board.string(forType: .string) else { return }
        insertText(value, replacementRange: selectedRange())
    }
}
@MainActor final class FixtureDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var editor: FixtureTextView!
    var status: NSTextField!
    var counter = 0
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appMenu = NSMenuItem(); menu.addItem(appMenu); appMenu.submenu = NSMenu()
        appMenu.submenu?.addItem(withTitle: "Quit Winnel Fixture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenuItem(); menu.addItem(edit); edit.submenu = NSMenu(title: "Edit")
        edit.submenu?.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 660,height: 460), styleMask: [.titled,.closable,.resizable,.miniaturizable], backing: .buffered, defer: false)
        window.title = "Winnel Synthetic Fixture"
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 24,left: 24,bottom: 24,right: 24)
        let title = NSTextField(labelWithString: "Synthetic capture and paste destination")
        title.font = .systemFont(ofSize: 21,weight: .semibold)
        root.addArrangedSubview(title)
        root.addArrangedSubview(NSTextField(wrappingLabelWithString: "Uses only the named Winnel fixture pasteboard. The general clipboard is never read or changed."))
        let button = NSButton(title: "Copy next synthetic sample",target: self,action: #selector(copySample))
        button.setAccessibilityIdentifier("fixture-copy"); root.addArrangedSubview(button)
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
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
let delegate = FixtureDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
