import AppKit
import WebKit

/// Hosts the two faces of a markdown file — the classic rendered preview and
/// the md2hd map — with a floating segmented toggle to flip between them.
/// Each face keeps its own WKWebView so switching doesn't lose state.
final class ViewerView: NSView {
    enum Mode: Int {
        case markdown = 0
        case map = 1
    }

    private let payload: MarkdownPayload
    private var webViews: [Mode: WKWebView] = [:]
    private let toggleBackdrop = NSVisualEffectView()
    private let toggle = NSSegmentedControl(
        labels: ["Preview", "Map"], trackingMode: .selectOne, target: nil, action: nil)

    private(set) var mode: Mode

    init(payload: MarkdownPayload, initialMode: Mode = .markdown) {
        self.payload = payload
        self.mode = initialMode
        super.init(frame: .zero)

        wantsLayer = true

        toggleBackdrop.material = .hudWindow
        toggleBackdrop.blendingMode = .withinWindow
        toggleBackdrop.state = .active
        toggleBackdrop.wantsLayer = true
        toggleBackdrop.layer?.cornerRadius = 8
        toggleBackdrop.layer?.masksToBounds = true

        toggle.target = self
        toggle.action = #selector(toggleChanged(_:))
        toggle.selectedSegment = mode.rawValue
        toggle.segmentStyle = .capsule

        show(mode)

        toggleBackdrop.translatesAutoresizingMaskIntoConstraints = false
        toggle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toggleBackdrop)
        toggleBackdrop.addSubview(toggle)
        NSLayoutConstraint.activate([
            toggleBackdrop.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            toggleBackdrop.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            toggle.topAnchor.constraint(equalTo: toggleBackdrop.topAnchor, constant: 4),
            toggle.bottomAnchor.constraint(equalTo: toggleBackdrop.bottomAnchor, constant: -4),
            toggle.leadingAnchor.constraint(equalTo: toggleBackdrop.leadingAnchor, constant: 6),
            toggle.trailingAnchor.constraint(equalTo: toggleBackdrop.trailingAnchor, constant: -6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func toggleChanged(_ sender: NSSegmentedControl) {
        guard let next = Mode(rawValue: sender.selectedSegment), next != mode else { return }
        show(next)
    }

    func show(_ next: Mode) {
        mode = next
        toggle.selectedSegment = next.rawValue
        let active = webView(for: next)
        for (m, wv) in webViews {
            wv.isHidden = m != next
        }
        // The toggle stays above the web views.
        sortSubviews({ a, b, _ in
            if a is NSVisualEffectView { return .orderedDescending }
            if b is NSVisualEffectView { return .orderedAscending }
            return .orderedSame
        }, context: nil)
        window?.makeFirstResponder(active)
    }

    /// The payload as a JS object literal, safe to splice into a user script.
    /// The map face gets the outline-transformed files so plain markdown
    /// still draws a graph; the preview face gets the file verbatim.
    private func payloadLiteral(for mode: Mode) -> String {
        let data = mode == .map ? payload.mapFilesJSON() : payload.filesJSON()
        return (String(data: data, encoding: .utf8) ?? "{}")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    private func webView(for mode: Mode) -> WKWebView {
        if let existing = webViews[mode] { return existing }

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(MapSchemeHandler(payload: payload), forURLScheme: MapSchemeHandler.scheme)
        // A viewer previews a file; it doesn't accumulate state between files.
        configuration.websiteDataStore = .nonPersistent()

        // Hand the page its file directly: fetch('/__files.json') resolves from
        // this embedded payload, never from the network stack, so the app
        // always boots into the previewed file.
        let filesShim = """
        (() => {
          const data = \(payloadLiteral(for: mode));
          const orig = window.fetch ? window.fetch.bind(window) : null;
          window.fetch = function (input, init) {
            try {
              const url = typeof input === 'string' ? input : (input && input.url) || '';
              if (url.split('?')[0].endsWith('/__files.json')) {
                return Promise.resolve(new Response(JSON.stringify(data), {
                  status: 200, headers: { 'Content-Type': 'application/json' },
                }));
              }
            } catch (e) {}
            return orig ? orig(input, init) : Promise.reject(new TypeError('no fetch'));
          };
        })();
        """
        configuration.userContentController.addUserScript(
            WKUserScript(source: filesShim, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        // Insurance: some WebKit builds deny window.localStorage to custom
        // schemes. The md2hd app touches it at boot, so shim it if absent.
        let storageShim = """
        (() => {
          try { window.localStorage.getItem('__probe__'); } catch (e) {
            const store = new Map();
            const shim = {
              getItem: (k) => store.has(String(k)) ? store.get(String(k)) : null,
              setItem: (k, v) => store.set(String(k), String(v)),
              removeItem: (k) => store.delete(String(k)),
              clear: () => store.clear(),
              key: (i) => [...store.keys()][i] ?? null,
              get length() { return store.size; },
            };
            Object.defineProperty(window, 'localStorage', { value: shim });
          }
        })();
        """
        configuration.userContentController.addUserScript(
            WKUserScript(source: storageShim, injectionTime: .atDocumentStart, forMainFrameOnly: false))

        if mode == .map {
            // This is a viewer: drop the app chrome for managing maps (the
            // rail with new/import/list/sign-in) and keep the canvas.
            let chromeCSS = """
            (() => {
              const style = document.createElement('style');
              style.textContent = `
                .rail, .rail-toggle { display: none !important; }
                .shell { grid-template-columns: minmax(0, 1fr) !important; }
                .empty-actions { display: none !important; }
              `;
              document.documentElement.appendChild(style);
            })();
            """
            configuration.userContentController.addUserScript(
                WKUserScript(source: chromeCSS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        let webView = WKWebView(frame: bounds, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webViews[mode] = webView
        addSubview(webView, positioned: .below, relativeTo: toggleBackdrop.superview === self ? toggleBackdrop : nil)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        let path = mode == .map ? "/app/" : "/md/"
        webView.load(URLRequest(url: URL(string: "\(MapSchemeHandler.scheme)://viewer\(path)")!))
        return webView
    }
}
