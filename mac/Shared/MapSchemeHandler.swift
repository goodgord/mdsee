import Foundation
import WebKit

/// Serves the bundled md2hd app and the previewed markdown over mdsee://viewer/…
/// — the same contract as the md2hd CLI server, minus the network.
final class MapSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "mdsee"
    static let origin = URL(string: "mdsee://viewer")!

    private let payload: MarkdownPayload

    init(payload: MarkdownPayload) {
        self.payload = payload
    }

    private static let mimeTypes: [String: String] = [
        "html": "text/html",
        "css": "text/css",
        "js": "text/javascript",
        "mjs": "text/javascript",
        "json": "application/json",
        "svg": "image/svg+xml",
        "png": "image/png",
        "jpg": "image/jpeg",
        "ico": "image/x-icon",
        "txt": "text/plain",
        "xml": "application/xml",
        "woff2": "font/woff2",
        "webmanifest": "application/manifest+json",
    ]

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            fail(task)
            return
        }
        let path = url.path.isEmpty ? "/" : url.path

        if path == "/__files.json" {
            respond(task, url: url, data: payload.filesJSON(), mime: "application/json")
            return
        }

        guard let (data, mime) = bundledResource(for: path) else {
            fail(task)
            return
        }
        respond(task, url: url, data: data, mime: mime)
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    /// Resolves a request path against the bundled dist/ (the md2hd app) and
    /// viewer/ (our classic markdown page) resource folders.
    private func bundledResource(for rawPath: String) -> (Data, String)? {
        guard let resourceRoot = Bundle.main.resourceURL else { return nil }

        var path = rawPath
        if path == "/" { path = "/app/" }

        // "/md/..." belongs to our own viewer resources; everything else to dist.
        let root: URL
        if path == "/md" || path.hasPrefix("/md/") {
            root = resourceRoot.appendingPathComponent("viewer", isDirectory: true)
            path = String(path.dropFirst("/md".count))
            if path.isEmpty || path == "/" { path = "/md.html" }
        } else {
            root = resourceRoot.appendingPathComponent("dist", isDirectory: true)
        }

        var file = root.appendingPathComponent(path).standardizedFileURL
        guard file.path.hasPrefix(root.standardizedFileURL.path) else { return nil }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            file.appendPathComponent("index.html")
        }
        guard let data = try? Data(contentsOf: file) else { return nil }
        let mime = Self.mimeTypes[file.pathExtension.lowercased()] ?? "application/octet-stream"
        return (data, mime)
    }

    private func respond(_ task: WKURLSchemeTask, url: URL, data: Data, mime: String) {
        let response = URLResponse(
            url: url, mimeType: mime, expectedContentLength: data.count,
            textEncodingName: mime.hasPrefix("text/") || mime.contains("json") ? "utf-8" : nil)
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func fail(_ task: WKURLSchemeTask) {
        task.didFailWithError(URLError(.fileDoesNotExist))
    }
}
