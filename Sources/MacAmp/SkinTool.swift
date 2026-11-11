import AppKit
import SwiftUI
#if canImport(MacAmpCore)
import MacAmpCore
#endif

/// Command-line helpers for skin authors (people or LLMs). They run instead of the app:
///
///     MacAmp --validate-skin <skin.json | skin folder>
///     MacAmp --render-skin <skin.json | skin folder | built-in name> [--out preview.png]
///            [--state playing|paused|stopped] [--progress 0.4] [--window player|all] [--scale 2]
///     MacAmp --skin-reference
@MainActor enum SkinTool {
    /// Returns an exit code when the arguments ask for a skin command, nil to launch the app normally.
    static func run(_ arguments: [String]) -> Int32? {
        let args = Array(arguments.dropFirst())
        guard let command = args.first, ["--validate-skin", "--render-skin", "--skin-reference"].contains(command) else { return nil }
        switch command {
        case "--skin-reference": print(reference()); return 0
        case "--validate-skin":
            guard args.count > 1 else { fail("usage: MacAmp --validate-skin <skin.json | skin folder>"); return 2 }
            return validate(URL(fileURLWithPath: args[1]))
        default:
            guard args.count > 1 else { fail("usage: MacAmp --render-skin <skin.json | skin folder | built-in name> [--out file.png] [--state playing|paused|stopped] [--progress 0…1] [--window player|all] [--scale 1…4]"); return 2 }
            return render(args[1], options: options(Array(args.dropFirst(2))))
        }
    }

    // MARK: Validate
    static func validate(_ url: URL) -> Int32 {
        let issues = SkinValidator.validate(at: url)
        if issues.isEmpty { print("✓ \(url.lastPathComponent): no problems found"); return 0 }
        for issue in issues { if issue.message.hasPrefix("cannot read") { fail(issue.description) } else { print(issue) } }
        let errors = issues.filter { $0.severity == .error }.count
        print("\(errors) error(s), \(issues.count - errors) warning(s)")
        return errors > 0 ? 1 : 0
    }

    // MARK: Render
    static func render(_ target: String, options: [String: String]) -> Int32 {
        guard let (skin, defaultOut) = load(target) else {
            if FileManager.default.fileExists(atPath: target) { for issue in SkinValidator.validate(at: URL(fileURLWithPath: target)) { fail(issue.description) } }
            else { fail("No skin at \"\(target)\". Pass a .json file, a skin folder, or one of: \(Skin.builtIn.map(\.id).joined(separator: ", "))") }
            return 1
        }
        let issues = SkinValidator.validate(skin, others: Skin.builtIn).filter { $0.severity == .error }
        for issue in issues { fail(issue.description) }
        let palette = Palette(skin)
        let state = options["state"] ?? "playing"
        let progress = min(1, max(0, Double(options["progress"] ?? "") ?? 0.35))
        let scale = min(4, max(1, Double(options["scale"] ?? "") ?? 2))
        let model = sampleModel(state: state, progress: progress, skin: skin)
        let windows = Windows(model: model)
        let (width, height) = Windows.playerSize(palette)
        let player = PlayerView(model: model, live: model.live, windows: windows).frame(width: width, height: height)
        let view: AnyView
        if options["window"] == "all" {
            view = AnyView(VStack(alignment: .leading, spacing: 0) {
                player
                EqualizerView(model: model, windows: windows).frame(width: 275, height: 116)
                PlaylistView(model: model, windows: windows).frame(width: 275, height: 245)
            }.background(Color(white: 0.5)))
        } else {
            view = AnyView(player)
        }
        let renderer = ImageRenderer(content: view.environment(\.palette, palette).environment(\.renderingPreview, true))
        renderer.scale = scale
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            fail("Could not render the skin."); return 1
        }
        let out = URL(fileURLWithPath: options["out"] ?? defaultOut.path)
        do { try png.write(to: out) } catch { fail("Could not write \(out.path): \(error.localizedDescription)"); return 1 }
        print("Rendered \(skin.name) (\(state), progress \(progress)) → \(out.path)")
        return issues.isEmpty ? 0 : 1
    }

    /// Loads a skin from a file, folder or built-in name, resolving `basedOn` against built-ins and siblings.
    static func load(_ target: String) -> (Skin, URL)? {
        if let builtIn = Skin.builtIn.first(where: { $0.id == target.lowercased() || $0.name.lowercased() == target.lowercased() }) {
            return (SkinLibrary.resolved(builtIn.id, in: Skin.builtIn), URL(fileURLWithPath: "\(builtIn.id)-preview.png"))
        }
        let url = URL(fileURLWithPath: target).standardizedFileURL
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { return nil }
        let parent = url.deletingLastPathComponent()
        let skins = SkinLibrary.all(in: parent)
        let id = (isFolder.boolValue ? "folder:" : "file:") + url.lastPathComponent
        guard skins.contains(where: { $0.id == id }) else { return nil }
        let out = isFolder.boolValue ? url.appendingPathComponent("preview.png") : parent.appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-preview.png")
        return (SkinLibrary.resolved(id, in: skins), out)
    }

    /// A model with a sample playlist and playback state, saving nowhere that matters.
    static func sampleModel(state: String, progress: Double, skin: Skin) -> Model {
        let model = Model(stateURL: FileManager.default.temporaryDirectory.appendingPathComponent("macamp-preview-\(UUID().uuidString).json"))
        let titles = ["The Example Band — Night Drive", "Lumen — Glass Rivers", "Orbit Club — Slow Satellites", "Mira Vale — Paper Lanterns",
                      "The Example Band — Coastline", "Static Bloom — Neon Weather", "Juniper — Small Hours", "Low Tide — Harbour Lights"]
        model.session.tracks = titles.enumerated().map { Track(url: URL(fileURLWithPath: "/Music/\($0.offset + 1).mp3"), title: $0.element) }
        model.session.selected = model.session.tracks.first?.id
        model.session.volume = 0.7; model.session.balance = 0; model.session.shuffle = true; model.session.repeatMode = .all
        model.session.bands = [3, 5, 2, 0, -1, -2, 0, 2, 4, 5]
        model.preview(skin: skin, state: state, progress: progress, duration: 214)
        return model
    }

    static func options(_ args: [String]) -> [String: String] {
        var result: [String: String] = [:], key: String?
        for arg in args {
            if arg.hasPrefix("--") { key = String(arg.dropFirst(2)) } else if let current = key { result[current] = arg; key = nil }
        }
        return result
    }

    static func fail(_ message: String) {
        var text = message
        // The installed app is sandboxed: point at the one folder it may read.
        if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil, message.contains("cannot read") || message.contains("Could not write") {
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MacAmp/Skins").path
            text += "\n  The installed app is sandboxed and can only use skins in: \(folder)\n  Move the skin there, or run a source build (swift run MacAmp …)."
        }
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    // MARK: Reference
    /// The skin format, straight from the code, so it can't drift from what the app accepts.
    static func reference() -> String {
        func list(_ items: [(name: String, use: String)]) -> String { items.map { "  \($0.name) — \($0.use)" }.joined(separator: "\n") }
        return """
        MAC-AMP SKIN REFERENCE

        Skin keys: name, face (\(Skin.Face.allCases.map(\.rawValue).joined(separator: " | "))), basedOn, colors, images, fonts, shape, layout
        Built-in skins: \(Skin.builtIn.map { "\($0.id) (\($0.name))" }.joined(separator: ", "))

        COLOR TOKENS (colors: { token: "#RRGGBB" | "#RRGGBBAA" })
        \(list(Skin.tokens))

        IMAGE SLOTS (images: { slot: "file.png" | { "file": "file.png", "mode": "stretch" | "tile" } })
        \(list(Skin.imageSlots))

        FONT ROLES (fonts: { role: "Installed Font Name" | "MyFont.ttf" })
        \(list(Skin.fontRoles))

        SHAPE (shape: { ... }, all optional)
          windowCorner — corner radius of windows (points)
          buttonCorner — corner radius of buttons (points)
          cassetteWindow — "wide" | "twin" (cassette face)
          reels — "teeth" | "spokes" | "solid" (cassette face)
          label — "stripes" | "plain" (cassette face)

        LAYOUT (layout: { "size": [width, height], "elements": [ ... ] }) — draws the whole player
          Frames are [x, y, width, height] in points from the parent's top-left. Later elements draw on top.
          Paint: token | "#RRGGBB(AA)" | { "linear": [stops], "angle": degrees } | { "radial": [stops] }
          Number or binding: 12 | { "bind": "<binding>", "from": a, "to": b, "idle": c }  (idle = value while stopped)
          File "@<slot>" uses the skin's image for that slot, if any.
          Common fields: frame, fill, stroke, strokeWidth, corner, opacity, visible ("binding" or "!binding"), help

        LIMITS (skins are checked when loaded; anything outside these is ignored)
          skin.json up to \(SkinLibrary.maxSkinFileBytes / 1000) KB; layout size \(Int(SkinLayout.sizeLimits.width.lowerBound))–\(Int(SkinLayout.sizeLimits.width.upperBound)) × \(Int(SkinLayout.sizeLimits.height.lowerBound))–\(Int(SkinLayout.sizeLimits.height.upperBound)) points
          up to \(SkinLayout.maxElements) elements, groups nested up to \(SkinLayout.maxDepth) deep; fontSize up to 400; text up to 500 characters
          images: \(SkinImage.extensions.sorted().joined(separator: ", ")); up to \(SkinImage.maxBytes / 1_000_000) MB and \(SkinImage.maxPixels) pixels a side
          files must be inside the skin's folder: no absolute paths, no "..", no symlinks that lead outside

        ELEMENT TYPES
        \(list(LayoutElement.types))

        BUTTON ACTIONS
        \(list(LayoutElement.actions))

        BINDINGS (0…1)
        \(list(LayoutElement.bindings))

        TEXT PLACEHOLDERS ({name} in text and button labels)
        \(list(LayoutElement.placeholders))
        """
    }
}
