# mdsee

**Quick Look for markdown, two ways.** Press space on a `.md` file in Finder
and flip between a clean rendered preview and a visual map of the document's
structure — headings, bullets, and links drawn as a graph you can explore.

mdsee is a macOS fork of [md2hd](https://github.com/evan-steinhilb/md2hd) by
Evan Steinhilb — *"Markdown, mapped."* md2hd draws knowledge maps from
markdown frontmatter and wikilinks in your browser; mdsee wraps that same
canvas in a native Quick Look extension and viewer app, and teaches it to map
**any** markdown file, not just files authored for md2hd.

| Preview | Map |
| --- | --- |
| ![Rendered markdown preview with typed node cards](media/mdsee-preview.png) | ![The md2hd canvas drawing a document graph](media/mdsee-map.png) |

## What you get

- **Quick Look extension** — spacebar any markdown file in Finder. A
  Preview / Map toggle sits in the top-right corner.
- **Preview face** — rendered markdown (light/dark aware). md2hd frontmatter
  node blocks render as styled cards — type badge, title, relationship chips —
  instead of raw YAML.
- **Map face** — the md2hd canvas, stripped of its app chrome. Just the
  graph, search, the type strip, and the node detail drawer.
- **MDSee.app** — the same viewer as a regular app. Open a markdown file, or
  point it at a whole folder of notes to map them together.

## Every file maps

md2hd draws nodes from frontmatter blocks and edges from `[[wikilinks]]` and
`rel:` entries. mdsee keeps that: files written as md2hd maps pass through
untouched and draw exactly as the CLI would draw them.

Plain markdown gets a map too. mdsee synthesizes one from the document's own
structure before handing it to the canvas:

- the **document** becomes the root node
- **headings** become nodes, typed by depth (`doc` → `section` → `topic` → `detail`)
- **top-level bullets and numbered steps** become `item` nodes under their
  section — a bold lead like `**02-career-profile.md** — the professional
  record…` becomes the node's title, the rest becomes its detail text
- nesting becomes `contains` edges, and any `[[wikilinks]]` in your notes
  become real edges between nodes

The Preview face always shows your file verbatim; only the map sees the
transformation.

## Let your agent write the map

The outline map works on any markdown, but mdsee really shines when the
markdown is *authored for the map* — typed nodes, named relationships,
weights — and the cheapest way to get that is to have your coding agent do
it while it's already writing the file. Architecture docs, briefing notes,
incident writeups, the context files you keep for agents anyway: ask for
them as md2hd maps and every one becomes a graph you can spacebar.

Hand-writing the format is easy to get subtly wrong — md2hd has no error
state, so mistakes draw *something* rather than failing. The bundled
`writing-md2hd-maps` skill (from upstream md2hd) teaches an agent the whole
authoring language plus the traps: silent node loss from `key:value` missing
its space, arrows flipped by `_by` suffixes, titles hijacked by body
headings, relations merged by stem.

Set it up once per project (or globally) with the
[skills CLI](https://github.com/vercel-labs/skills) — it installs for Claude
Code, Codex, Cursor, Gemini CLI, and a dozen other agents:

```sh
npx skills add goodgord/mdsee
```

Then just ask your agent, in its own words:

> Rewrite docs/ARCHITECTURE.md as an md2hd map using the writing-md2hd-maps
> skill. Keep the prose as node bodies.

or, for new material:

> Write up this incident as an md2hd map — services, people, timeline,
> action items.

Claude Code users can also invoke it directly with `/writing-md2hd-maps`, or
install it as a plugin from upstream
(`/plugin marketplace add evan-steinhilb/md2hd`). Agents with the skill
loaded pick it up automatically whenever a task mentions md2hd or map
authoring. When it's done: press space on the file.

## How it works

There is no server and nothing leaves your machine. The md2hd web app is
bundled prebuilt (`dist/`) and served to a `WKWebView` through a custom
`mdsee://` URL scheme handler; the file being previewed is injected directly
into the page as the same `__files.json` payload the md2hd CLI serves. The
whole thing is sandboxed with no network access.

## Installing

**Homebrew** (easiest):

```sh
brew install --cask goodgord/tap/mdsee
```

**Download**: grab the zip from the
[latest release](https://github.com/goodgord/mdsee/releases/latest), unzip,
and drag MDSee.app to Applications. Releases are signed and notarized, so
Gatekeeper is happy. Open the app once to register the Quick Look extension.

**From source** — requires Xcode and
[xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`):

```sh
git clone https://github.com/goodgord/mdsee.git
mdsee/mac/install.sh
```

Whichever route: press space on a `.md` file and you're done.

If another Quick Look extension already owns markdown previews (Markdown
Peek, QLMarkdown, …), pick the handler in **System Settings → General →
Login Items & Extensions → Quick Look**, or from a terminal:

```sh
pluginkit -e use -i com.goodgord.MDSee.QuickLook
```

To uninstall, delete `/Applications/MDSee.app`.

`samples/partnerships.md` is a small hand-written md2hd map to try; any
markdown file exercises the outline map.

## Upstream

The md2hd CLI, web app, and markdown syntax are Evan Steinhilb's work —
docs at [md2hd.app](https://md2hd.app). The CLI still works from this fork
(`node bin/md2hd.mjs notes/`). The mac layer lives entirely in `mac/` so
upstream changes merge cleanly: `git merge upstream/main`, rebuild, done.

## License

MIT, same as upstream. See [LICENSE](LICENSE).
