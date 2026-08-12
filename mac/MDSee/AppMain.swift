import AppKit
import UniformTypeIdentifiers

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    private var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { open(url) }
    }

    // Called only when launched without a document.
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        promptForFile()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @objc func openDocument(_ sender: Any?) {
        promptForFile()
    }

    private func promptForFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .folder, UTType("net.daringfireball.markdown") ?? .plainText]
        panel.message = "Choose a markdown file or a folder of notes"
        if panel.runModal() == .OK, let url = panel.url {
            open(url)
        } else if windows.isEmpty {
            NSApp.terminate(nil)
        }
    }

    private func open(_ url: URL) {
        let payload: MarkdownPayload
        do {
            payload = try MarkdownPayload.load(from: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Nothing to map"
            alert.informativeText = "No markdown found at \(url.path)."
            alert.runModal()
            return
        }
        let viewer = ViewerView(payload: payload, initialMode: .map)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = payload.name
        window.contentView = viewer
        window.center()
        window.setFrameAutosaveName("MDSee-\(payload.name)")
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About MDSee", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit MDSee", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
