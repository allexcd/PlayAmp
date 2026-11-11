import Foundation

/// A skin is a JSON description of how PlayAmp looks:
///
///     { "name": "Walnut", "face": "turntable", "basedOn": "turntable",
///       "colors": { "display": "#FFB238" },
///       "images": { "panel": { "file": "wood.png", "mode": "tile" }, "recordLabel": "label.png" },
///       "fonts":  { "display": "Menlo", "label": "MyHand.ttf" },
///       "shape":  { "windowCorner": 8, "buttonCorner": 4 } }
///
/// It can be a single `.json` file, or a folder containing `skin.json` plus the images and font
/// files it names. Anything left out falls back to the `basedOn` skin, then to Classic.
public struct Skin: Codable, Equatable, Identifiable, Sendable {
    /// Built-in player designs written in Swift. A skin with a `layout` draws its own player instead.
    public enum Face: String, Codable, Sendable, CaseIterable { case classic, cassette }

    /// An image file, stretched to fill its slot or tiled at its natural size.
    public struct ImageSpec: Codable, Equatable, Sendable {
        public enum Mode: String, Codable, Sendable { case stretch, tile }
        public var file: String
        public var mode: Mode
        public init(file: String, mode: Mode = .stretch) { self.file = file; self.mode = mode }
        /// Accepts either `"wood.png"` or `{ "file": "wood.png", "mode": "tile" }`.
        public init(from decoder: Decoder) throws {
            if let file = try? decoder.singleValueContainer().decode(String.self) { self.init(file: file); return }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(file: try container.decode(String.self, forKey: .file), mode: try container.decodeIfPresent(Mode.self, forKey: .mode) ?? .stretch)
        }
    }

    /// Geometry options. Every field is optional so skins only set what they change.
    public struct Shape: Codable, Equatable, Sendable {
        public var windowCorner: Double?
        public var buttonCorner: Double?
        /// Cassette face: "wide" (one long window) or "twin" (two round windows).
        public var cassetteWindow: String?
        /// Cassette face: "teeth", "spokes" or "solid" reel hubs.
        public var reels: String?
        /// Cassette face: "stripes" or "plain" label.
        public var label: String?
        public init(windowCorner: Double? = nil, buttonCorner: Double? = nil, cassetteWindow: String? = nil, reels: String? = nil, label: String? = nil) {
            self.windowCorner = windowCorner; self.buttonCorner = buttonCorner; self.cassetteWindow = cassetteWindow; self.reels = reels; self.label = label
        }
        /// Keeps corner radii in a sane range.
        public func sanitized() -> Shape {
            func corner(_ value: Double?, _ limit: Double) -> Double? { value.flatMap { $0.isFinite ? min(limit, max(0, $0)) : nil } }
            var copy = self; copy.windowCorner = corner(windowCorner, 60); copy.buttonCorner = corner(buttonCorner, 30)
            return copy
        }
        /// Fields this shape leaves unset are taken from `parent`.
        public func filled(from parent: Shape) -> Shape {
            Shape(windowCorner: windowCorner ?? parent.windowCorner, buttonCorner: buttonCorner ?? parent.buttonCorner,
                  cassetteWindow: cassetteWindow ?? parent.cassetteWindow, reels: reels ?? parent.reels, label: label ?? parent.label)
        }
    }

    /// "classic", "cassette", "turntable", "file:<name>.json" or "folder:<name>" for user skins.
    public var id = ""
    public var name: String
    public var face: Face?
    public var basedOn: String?
    public var colors: [String: String]
    public var images: [String: ImageSpec]?
    public var fonts: [String: String]?
    public var shape: Shape?
    /// A complete player design; overrides `face`. See SkinLayout.
    public var layout: SkinLayout?
    /// Where relative image and font file names are looked up (set when loading).
    public var folder: URL?
    enum CodingKeys: String, CodingKey { case name, face, basedOn, colors, images, fonts, shape, layout }

    public init(id: String, name: String, face: Face? = nil, basedOn: String? = nil, colors: [String: String],
                images: [String: ImageSpec]? = nil, fonts: [String: String]? = nil, shape: Shape? = nil, layout: SkinLayout? = nil) {
        self.id = id; self.name = name; self.face = face; self.basedOn = basedOn; self.colors = colors
        self.images = images; self.fonts = fonts; self.shape = shape; self.layout = layout
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        face = try c.decodeIfPresent(Face.self, forKey: .face)
        basedOn = try c.decodeIfPresent(String.self, forKey: .basedOn)
        colors = try c.decodeIfPresent([String: String].self, forKey: .colors) ?? [:]
        images = try c.decodeIfPresent([String: ImageSpec].self, forKey: .images)
        fonts = try c.decodeIfPresent([String: String].self, forKey: .fonts)
        shape = try c.decodeIfPresent(Shape.self, forKey: .shape)
        layout = try c.decodeIfPresent(SkinLayout.self, forKey: .layout)
    }

    /// Every color a skin can set, with what it paints.
    public static let tokens: [(name: String, use: String)] = [
        ("display", "LCD text, spectrum base, playlist titles"),
        ("displayBackground", "LCD, playlist and slider backgrounds"),
        ("displayDim", "secondary LCD text (track numbers, formats)"),
        ("displayHighlight", "the playing track's title, peak markers"),
        ("playingRow", "background of the playing playlist row"),
        ("panelTop", "window gradient, top-left"),
        ("panelMid", "window gradient, middle"),
        ("panelBottom", "window gradient, bottom-right"),
        ("border", "window outline and title-bar lines"),
        ("text", "window titles and labels"),
        ("panelAccent", "highlighted labels on the window body (EQ values, track count)"),
        ("buttonTop", "button gradient, top"),
        ("buttonBottom", "button gradient, bottom"),
        ("buttonPressed", "pressed button"),
        ("buttonText", "button labels"),
        ("sliderFillStart", "slider fill, left"),
        ("sliderFillEnd", "slider fill, right"),
        ("knob", "slider and fader knobs"),
        ("spectrumHigh", "spectrum bar tops"),
        ("spectrumMid", "spectrum bar middles"),
        ("cassetteShell", "cassette body (cassette face)"),
        ("cassetteLabel", "cassette label (cassette face)"),
        ("cassetteStripe1", "label stripe (cassette face)"),
        ("cassetteStripe2", "label stripe (cassette face)"),
        ("cassetteInk", "handwriting on the label (cassette and turntable faces)"),
        ("tape", "tape ribbon and reel packs (cassette face)"),
        ("reel", "reel hubs (cassette face), spindle (turntable face)"),
        ("deck", "background of the cassette well / turntable plinth"),
        ("vinyl", "the record (turntable face)"),
        ("recordLabel", "the record's center label (turntable face)"),
        ("tonearm", "tonearm and platter rim (turntable face)")
    ]
    /// Image slots a skin can fill. Window slots fall back to "panel".
    public static let imageSlots: [(name: String, use: String)] = [
        ("panel", "background of every window"),
        ("player", "player window background (overrides panel)"),
        ("playlist", "playlist window background (overrides panel)"),
        ("equalizer", "equalizer window background (overrides panel)"),
        ("skins", "skins window background (overrides panel)"),
        ("display", "LCD areas, playlist and lists"),
        ("button", "buttons"),
        ("buttonPressed", "buttons while pressed"),
        ("deck", "cassette well / turntable plinth"),
        ("cassetteLabel", "artwork printed on the cassette label"),
        ("recordLabel", "artwork on the record's center label (spins with it)")
    ]
    /// Font roles. Values are an installed font's name, or a .ttf/.otf file in the skin's folder.
    public static let fontRoles: [(name: String, use: String)] = [
        ("display", "time, LCD text and the playlist"),
        ("ui", "window titles, buttons and labels"),
        ("label", "handwriting on the cassette / record label")
    ]

    public static let classic = Skin(id: "classic", name: "Classic", face: .classic, colors: [
        "display": "#80F247", "displayBackground": "#000000", "displayDim": "#808080", "displayHighlight": "#FFFFFF",
        "playingRow": "#173D0D", "panelTop": "#4A4D59E6", "panelMid": "#212121", "panelBottom": "#4A4D59",
        "border": "#A6A6A6", "text": "#DBDBDB", "panelAccent": "#80F247", "buttonTop": "#999999", "buttonBottom": "#4A4D59",
        "buttonPressed": "#000000", "buttonText": "#FFFFFF", "sliderFillStart": "#408C33", "sliderFillEnd": "#FFFF00",
        "knob": "#D9D9D9", "spectrumHigh": "#FF0000", "spectrumMid": "#FFFF00",
        "cassetteShell": "#2A2A2E", "cassetteLabel": "#EDE6D3", "cassetteStripe1": "#E07A1F", "cassetteStripe2": "#C0392B",
        "cassetteInk": "#1F2A6B", "tape": "#3B2416", "reel": "#F2F2F2", "deck": "#111111",
        "vinyl": "#121212", "recordLabel": "#C2412D", "tonearm": "#D6D6D2"
    ])

    /// A 70s silver tape deck: brushed aluminium, amber counter, smoked cassette with a cream label.
    public static let cassette = Skin(id: "cassette", name: "Cassette Deck", face: .cassette, basedOn: "classic", colors: [
        "display": "#FFB238", "displayBackground": "#1A120C", "displayDim": "#8C6A3F", "displayHighlight": "#FFE7B8",
        "playingRow": "#43290F", "panelTop": "#D9D8D2", "panelMid": "#A3A29C", "panelBottom": "#C4C3BD",
        "border": "#5E5D58", "text": "#2B2A27", "panelAccent": "#9A4A12", "buttonTop": "#F2F1EC", "buttonBottom": "#9E9D97",
        "buttonPressed": "#6E6D68", "buttonText": "#1E1E1C", "sliderFillStart": "#B5651D", "sliderFillEnd": "#FFB238",
        "knob": "#F7F6F1", "spectrumHigh": "#FF4A1C", "spectrumMid": "#FFB238",
        "cassetteShell": "#2B2A2ED9", "cassetteLabel": "#F1E9D2", "cassetteStripe1": "#E8892B", "cassetteStripe2": "#C2412D",
        "cassetteInk": "#22306E", "tape": "#3A2213", "reel": "#F4F4F0", "deck": "#121110"
    ])

    /// A walnut record player, drawn entirely by a JSON layout (BuiltInLayouts.turntable).
    public static let turntable = Skin(id: "turntable", name: "Turntable", basedOn: "classic", colors: [
        "display": "#F3E3C3", "displayBackground": "#15100C", "displayDim": "#8F7B62", "displayHighlight": "#FFFFFF",
        "playingRow": "#4A2E1A", "panelTop": "#6B4426", "panelMid": "#3F2614", "panelBottom": "#5A381F",
        "border": "#C9A27A", "text": "#F1E4CF", "panelAccent": "#F0C27B", "buttonTop": "#E9E4DA", "buttonBottom": "#A39C8F",
        "buttonPressed": "#6F695F", "buttonText": "#1F1A14", "sliderFillStart": "#8A5A2B", "sliderFillEnd": "#F0C27B",
        "knob": "#F4F1EA", "spectrumHigh": "#E8573A", "spectrumMid": "#F0C27B",
        "cassetteInk": "#F7EBD3", "reel": "#D9D9D4", "deck": "#2A1A0F",
        "vinyl": "#0F0F10", "recordLabel": "#B8352A", "tonearm": "#D6D6D2"
    ], shape: Shape(windowCorner: 8, buttonCorner: 3),
       layout: try! JSONDecoder().decode(SkinLayout.self, from: Data(BuiltInLayouts.turntable.utf8)))

    public static let builtIn = [classic, cassette, turntable]
}

public enum SkinLibrary {
    static let fontExtensions: Set<String> = ["ttf", "otf", "ttc"]
    // Skins are shared between people, so files from the Skins folder are treated as untrusted.
    /// Largest skin.json that is read.
    public static let maxSkinFileBytes = 1_000_000
    /// Most user skins loaded from one folder.
    public static let maxUserSkins = 200

    /// Built-in skins, then the Skins folder's `*.json` files and `*/skin.json` packages.
    /// Files that don't parse are skipped.
    public static func all(in folder: URL?) -> [Skin] {
        var skins = Skin.builtIn
        guard let folder, let entries = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return skins }
        for entry in entries.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let isFolder = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            let file = isFolder ? entry.appendingPathComponent("skin.json") : entry
            guard skins.count < Skin.builtIn.count + maxUserSkins else { break }
            guard isFolder || entry.pathExtension.lowercased() == "json",
                  let data = boundedData(at: file), var skin = try? JSONDecoder().decode(Skin.self, from: data) else { continue }
            skin.id = (isFolder ? "folder:" : "file:") + entry.lastPathComponent
            skin.folder = isFolder ? entry : folder
            skin.name = String(skin.name.prefix(80))
            // Drop anything that could crash, hang or blow up the window (see SkinLayout.sanitized).
            skin.layout = skin.layout?.sanitized()
            skin.shape = skin.shape?.sanitized()
            skins.append(skin)
        }
        return skins
    }

    /// Flattens `basedOn` chains so every color has a value, and turns image and font file
    /// names into absolute paths (relative to the skin that named them). Unknown ids fall back to Classic.
    public static func resolved(_ id: String?, in skins: [Skin]) -> Skin {
        var skin = skins.first { $0.id == id } ?? Skin.classic
        var chain = [skin]
        var seen: Set<String> = [skin.id]
        var base = skin.basedOn
        while let next = base, !seen.contains(next), let parent = skins.first(where: { $0.id == next || $0.name == next }) {
            seen.insert(parent.id); chain.append(parent); base = parent.basedOn
        }
        if !seen.contains(Skin.classic.id) { chain.append(Skin.classic) }
        var colors: [String: String] = [:], images: [String: Skin.ImageSpec] = [:], fonts: [String: String] = [:]
        var shape = Skin.Shape(), face: Skin.Face?, layout: SkinLayout?
        for layer in chain {   // nearest first: keep the first value found for each key
            colors.merge(layer.colors) { mine, _ in mine }
            for (slot, spec) in layer.images ?? [:] where images[slot] == nil {
                images[slot] = Skin.ImageSpec(file: absolute(spec.file, in: layer.folder), mode: spec.mode)
            }
            for (role, font) in layer.fonts ?? [:] where fonts[role] == nil {
                fonts[role] = fontExtensions.contains((font as NSString).pathExtension.lowercased()) ? absolute(font, in: layer.folder) : font
            }
            shape = shape.filled(from: layer.shape ?? Skin.Shape())
            face = face ?? layer.face
            if layout == nil, let own = layer.layout { layout = own.absolutized(in: layer.folder) }
        }
        skin.colors = colors; skin.face = face ?? .classic
        skin.images = images.isEmpty ? nil : images; skin.fonts = fonts.isEmpty ? nil : fonts; skin.shape = shape
        // A skin that picks a built-in face replaces an inherited layout.
        skin.layout = (chain[0].layout == nil && chain[0].face != nil) ? nil : layout
        return skin
    }

    /// Reads a skin.json, refusing files that are too large to be a real skin.
    static func boundedData(at url: URL) -> Data? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maxSkinFileBytes else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Names resolve inside `folder` only. Absolute paths, `..` and symlinks that lead out of the
    /// folder are rejected (empty path), so a shared skin can't make the app open other files.
    static func absolute(_ file: String, in folder: URL?) -> String {
        guard let folder, !file.isEmpty, !file.hasPrefix("/"), !file.hasPrefix("~"), !file.contains("\0") else { return "" }
        let base = folder.resolvingSymlinksInPath().path
        let url = URL(fileURLWithPath: base).appendingPathComponent(file).standardizedFileURL.resolvingSymlinksInPath()
        return url.path.hasPrefix(base + "/") ? url.path : ""
    }

    /// Parses "#RRGGBB" or "#RRGGBBAA" into 0...1 components.
    public static func rgba(_ hex: String) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8, let value = UInt64(text, radix: 16) else { return nil }
        let full = text.count == 6 ? value << 8 | 0xFF : value
        return (Double(full >> 24 & 0xFF) / 255, Double(full >> 16 & 0xFF) / 255, Double(full >> 8 & 0xFF) / 255, Double(full & 0xFF) / 255)
    }

    /// A starting point listing every color, written into the Skins folder.
    public static func exampleJSON() -> String {
        let colors = Skin.tokens.map { token in
            "    \"\(token.name)\": \"\(Skin.cassette.colors[token.name] ?? Skin.classic.colors[token.name]!)\""
        }.joined(separator: ",\n")
        return "{\n  \"name\": \"My Tape Deck\",\n  \"face\": \"cassette\",\n  \"basedOn\": \"cassette\",\n  \"colors\": {\n\(colors)\n  }\n}\n"
    }

    public static func readme() -> String {
        """
        PlayAmp skins
        =============
        A skin is either a .json file in this folder, or a folder containing skin.json plus the
        images and fonts it uses. Pick skins from the Skins panel (SK button) or the Skins menu;
        press RELOAD in the panel after editing.

        {
          "name": "Shown in the Skins panel",
          "face": "classic" or "cassette" (built-in designs),
          "layout": { ... } (optional: a complete player design; see the PlayAmp skin guide),
          "basedOn": "classic", "cassette", "turntable", or another skin's name (optional),
          "colors": { "<token>": "#RRGGBB" or "#RRGGBBAA", ... },
          "images": { "<slot>": "file.png"  or  { "file": "file.png", "mode": "tile" }, ... },
          "fonts":  { "<role>": "Installed Font Name"  or  "MyFont.ttf", ... },
          "shape":  { "windowCorner": 8, "buttonCorner": 4,
                      "cassetteWindow": "wide" | "twin", "reels": "teeth" | "spokes" | "solid",
                      "label": "stripes" | "plain" }
        }

        Anything you leave out comes from the basedOn skin, then from Classic.
        Images and fonts are looked up next to skin.json (or in this folder for a loose .json).
        Images stretch to fill their slot unless "mode" is "tile". PNG, JPEG and PDF work.

        Examples here: "Example.json" (every color), "Midnight Tape.json"-style color skins,
        "vu-radio" (a complete layout: VU needles, dial, knobs) and "walnut" (images + fonts).
        Check a skin without the app:   PlayAmp --validate-skin <file or folder>
        Render a preview image:         PlayAmp --render-skin <file or folder> --window all
        Full format reference:          PlayAmp --skin-reference

        Colors:
        \(Skin.tokens.map { "  \($0.name) — \($0.use)" }.joined(separator: "\n"))

        Images:
        \(Skin.imageSlots.map { "  \($0.name) — \($0.use)" }.joined(separator: "\n"))

        Fonts:
        \(Skin.fontRoles.map { "  \($0.name) — \($0.use)" }.joined(separator: "\n"))
        """
    }
}
