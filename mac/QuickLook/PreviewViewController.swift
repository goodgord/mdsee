import AppKit
import QuickLookUI

final class PreviewViewController: NSViewController, QLPreviewingController {
    override func loadView() {
        view = NSView()
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        let payload: MarkdownPayload
        do {
            payload = try MarkdownPayload.load(from: url)
        } catch {
            handler(error)
            return
        }
        let viewer = ViewerView(payload: payload, initialMode: .markdown)
        viewer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(viewer)
        NSLayoutConstraint.activate([
            viewer.topAnchor.constraint(equalTo: view.topAnchor),
            viewer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            viewer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            viewer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        handler(nil)
    }
}
