import Foundation

/// The markdown handed to the viewer — mirrors the CLI's /__files.json shape:
/// { name, files: [{ path, text }] }.
struct MarkdownPayload {
    struct File {
        let path: String
        let text: String
    }

    let name: String
    let files: [File]

    /// Matches the CLI's accepted extensions.
    private static let markdownExtensions: Set<String> = ["md", "markdown", "txt"]

    static func load(from url: URL) throws -> MarkdownPayload {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw CocoaError(.fileNoSuchFile)
        }
        if isDirectory.boolValue {
            return try loadFolder(url)
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        let name = url.deletingPathExtension().lastPathComponent
        return MarkdownPayload(name: name, files: [File(path: url.lastPathComponent, text: text)])
    }

    /// Walks a folder the way the CLI does: skip dotfiles and node_modules,
    /// keep paths prefixed with the folder's own name.
    private static func loadFolder(_ root: URL) throws -> MarkdownPayload {
        let prefix = root.lastPathComponent
        var files: [File] = []
        walk(root, prefix: prefix, into: &files)
        guard !files.isEmpty else { throw CocoaError(.fileReadNoSuchFile) }
        return MarkdownPayload(name: prefix, files: files)
    }

    private static func walk(_ dir: URL, prefix: String, into out: inout [File]) {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [])) ?? []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = entry.lastPathComponent
            if name.hasPrefix(".") || name == "node_modules" { continue }
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                walk(entry, prefix: "\(prefix)/\(name)", into: &out)
            } else if markdownExtensions.contains(entry.pathExtension.lowercased()),
                      let text = try? String(contentsOf: entry, encoding: .utf8) {
                out.append(File(path: "\(prefix)/\(name)", text: text))
            }
        }
    }

    /// Whether a file carries a frontmatter node block — mirrors the app's
    /// own rule: a `---` fence only opens a node when what follows looks like
    /// YAML.
    static func fileHasNodes(_ text: String) -> Bool {
        // Example snippets inside code fences shouldn't count as authored
        // nodes, so drop fenced content before looking.
        var inFence = false
        let prose = text.components(separatedBy: "\n").filter { line in
            if line.hasPrefix("```") || line.hasPrefix("~~~") { inFence.toggle(); return false }
            return !inFence
        }.joined(separator: "\n")
        let block = try! NSRegularExpression(
            pattern: #"(^|\n)---[ \t]*\n[ \t]*[A-Za-z0-9_-]+[ \t]*:[\s\S]*?\n---"#)
        let range = NSRange(prose.startIndex..., in: prose)
        return block.firstMatch(in: prose, range: range) != nil
    }

    func filesJSON() -> Data {
        Self.serialize(name: name, files: files)
    }

    /// The payload the map face gets. Files already written as md2hd maps
    /// pass through untouched; plain markdown is transformed into one — the
    /// heading outline becomes typed nodes and containment edges, so every
    /// file draws a graph, not just files authored for md2hd.
    func mapFilesJSON() -> Data {
        var out: [File] = []
        var synthesized = false
        for file in files {
            if Self.fileHasNodes(file.text) {
                out.append(file)
            } else {
                out.append(File(path: file.path, text: MarkdownOutline.nodeBlocks(for: file)))
                synthesized = true
            }
        }
        let hasConfig = files.contains { $0.text.contains("type: map") }
        if synthesized && !hasConfig {
            let config = """
            ---
            type: map
            title: \(MarkdownOutline.yamlString(name))
            inverse:
              contains: part of
            ---
            """
            out.insert(File(path: "_outline.md", text: config), at: 0)
        }
        return Self.serialize(name: name, files: out)
    }

    private static func serialize(name: String, files: [File]) -> Data {
        let payload: [String: Any] = [
            "name": name,
            "files": files.map { ["path": $0.path, "text": $0.text] },
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
    }
}

/// Turns a plain markdown file into md2hd node blocks: one node per heading,
/// nested headings linked by `contains`, prose kept as each node's body.
enum MarkdownOutline {
    private struct Node {
        let id: String
        let title: String
        let level: Int  // markdown heading level; 0 is the document root
        var depth: Int = 0  // tree depth, which decides the type
        var isItem = false  // a list bullet rather than a heading
        var children: [String] = []
        var body: [String] = []
    }

    static func nodeBlocks(for file: MarkdownPayload.File) -> String {
        let fileSlug = slug(String(file.path.split(separator: "/").last ?? "doc")
            .replacingOccurrences(of: #"\.\w+$"#, with: "", options: .regularExpression))

        var nodes: [Node] = []
        var order: [String] = []
        var stack: [Int] = []  // indexes into nodes, root..current
        var usedIds: Set<String> = []
        var inFence = false

        func addNode(title: String, level: Int) {
            var id = "\(fileSlug)-\(slug(title))"
            var n = 2
            while usedIds.contains(id) { id = "\(fileSlug)-\(slug(title))-\(n)"; n += 1 }
            usedIds.insert(id)
            while let last = stack.last, nodes[last].level >= level { stack.removeLast() }
            let depth = stack.isEmpty ? 0 : nodes[stack.last!].depth + 1
            if let parent = stack.last { nodes[parent].children.append(id) }
            nodes.append(Node(id: id, title: title, level: level, depth: depth))
            order.append(id)
            stack.append(nodes.count - 1)
        }

        let lines = file.text.components(separatedBy: "\n")
        var headings: [(title: String, level: Int, line: Int)] = []
        for (i, line) in lines.enumerated() {
            if line.hasPrefix("```") || line.hasPrefix("~~~") { inFence.toggle(); continue }
            if inFence { continue }
            if let match = line.range(of: #"^(#{1,6})[ \t]+"#, options: .regularExpression) {
                let level = line[match].filter { $0 == "#" }.count
                let title = String(line[match.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: #"[ \t]+#+[ \t]*$"#, with: "", options: .regularExpression)
                if !title.isEmpty { headings.append((title, level, i)) }
            }
        }

        // A single heading opening the file is the document; otherwise the
        // file itself is the root and top headings hang off it.
        let firstContent = lines.firstIndex { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? 0
        let topLevel = headings.first?.level ?? 1
        let soleTop = headings.filter { $0.level == topLevel }.count == 1
        let headingIsRoot = soleTop && headings.first?.line == firstContent

        if !headingIsRoot {
            addNode(title: prettify(fileSlug), level: 0)
        }
        // A top-level bullet under a section becomes a node of its own; its
        // indented continuation lines stay with it as body.
        func addItem(text: String, under parent: Int) -> Int {
            let bold = text.range(of: #"^\*\*([^*]+)\*\*"#, options: .regularExpression)
                .map { String(text[$0]).replacingOccurrences(of: "**", with: "") }
            var title = bold ?? text
                .replacingOccurrences(of: #"[*_`]"#, with: "", options: .regularExpression)
            if title.count > 64 {
                title = String(title.prefix(60)).trimmingCharacters(in: .whitespaces) + "…"
            }
            var id = "\(fileSlug)-\(slug(title))"
            var n = 2
            while usedIds.contains(id) { id = "\(fileSlug)-\(slug(title))-\(n)"; n += 1 }
            usedIds.insert(id)
            var node = Node(id: id, title: title, level: 99, depth: nodes[parent].depth + 1)
            node.isItem = true
            if bold != nil || title.hasSuffix("…") { node.body.append(text) }
            nodes[parent].children.append(id)
            nodes.append(node)
            order.append(id)
            return nodes.count - 1
        }

        var bodyOwner = nodes.isEmpty ? nil : 0
        var headingOwner = bodyOwner
        var headingIndex = 0
        inFence = false
        for (i, line) in lines.enumerated() {
            if line.hasPrefix("```") || line.hasPrefix("~~~") { inFence.toggle() }
            if !inFence, headingIndex < headings.count, headings[headingIndex].line == i {
                let h = headings[headingIndex]
                addNode(title: h.title, level: h.level)
                bodyOwner = nodes.count - 1
                headingOwner = bodyOwner
                headingIndex += 1
                continue
            }
            if !inFence, let heading = headingOwner,
               let marker = line.range(
                   of: #"^(?:[-*+]|\d{1,3}[.)])[ \t]+"#, options: .regularExpression) {
                let text = String(line[marker.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    bodyOwner = addItem(text: text, under: heading)
                    continue
                }
            }
            if !inFence, bodyOwner != headingOwner,
               !line.isEmpty, !line.hasPrefix(" "), !line.hasPrefix("\t") {
                bodyOwner = headingOwner  // flush prose ends the list item
            }
            if let owner = bodyOwner {
                // md2hd reads `---` fences and [[wikilinks]] even inside code
                // fences; soften both so example snippets can't inject stray
                // nodes or unresolved edges into the outline.
                var safe = line
                if safe.range(of: #"^---[ \t]*$"#, options: .regularExpression) != nil {
                    safe = "----"
                } else if inFence {
                    safe = safe.replacingOccurrences(of: "[[", with: "[ [")
                } else {
                    // Wikilinks quoted as inline code are mentions, not edges.
                    safe = safe.replacingOccurrences(
                        of: #"`([^`]*)\[\["#, with: "`$1[ [", options: .regularExpression)
                }
                nodes[owner].body.append(safe)
            }
        }

        var blocks: [String] = []
        for id in order {
            let node = nodes.first { $0.id == id }!
            let type = node.isItem ? "item" : ["doc", "section", "topic", "detail"][min(node.depth, 3)]
            var yaml = "---\nid: \(node.id)\ntype: \(type)\ntitle: \(yamlString(node.title))\n"
            if node.depth == 0 { yaml += "weight: lead\n" }
            if !node.children.isEmpty {
                yaml += "rel:\n  contains: [\(node.children.joined(separator: ", "))]\n"
            }
            yaml += "---"
            let body = node.body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            blocks.append(body.isEmpty ? yaml : "\(yaml)\n\n\(body)")
        }
        return blocks.joined(separator: "\n\n")
    }

    static func yamlString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func slug(_ s: String) -> String {
        let lowered = s.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return lowered.isEmpty ? "node" : lowered
    }

    private static func prettify(_ slug: String) -> String {
        slug.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
