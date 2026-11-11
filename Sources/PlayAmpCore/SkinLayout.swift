import Foundation

/// A declarative player design. When a skin has a `layout`, PlayAmp draws the player window
/// entirely from it: any size, any shapes, images and fonts, with parts that move with playback.
///
///     "layout": { "size": [275, 179], "elements": [
///       { "type": "rect", "frame": [0, 0, 275, 179], "fill": "panelMid", "corner": 8 },
///       { "type": "dragArea", "frame": [0, 0, 275, 16] },
///       { "type": "text", "frame": [140, 22, 128, 26], "text": "{time}", "font": "display", "fontSize": 20 },
///       { "type": "button", "frame": [10, 160, 22, 13], "action": "playPause", "label": "▶" } ] }
///
/// Frames are `[x, y, width, height]` in points from the top-left of the parent. Elements draw
/// in order, so later ones sit on top.
public struct SkinLayout: Codable, Equatable, Sendable {
    public var size: [Double]
    public var elements: [LayoutElement]
    public init(size: [Double], elements: [LayoutElement]) { self.size = size; self.elements = elements }
    public var width: Double { size.first ?? 275 }
    public var height: Double { size.count > 1 ? size[1] : 116 }
}

/// A color, gradient or theme token. JSON: `"display"`, `"#FF8800"`, `{ "linear": ["#000", "panelTop"], "angle": 90 }`,
/// or `{ "radial": ["#FFFFFF40", "#00000000"] }`.
public enum Paint: Codable, Equatable, Sendable {
    case color(String)
    case linear([String], angle: Double)
    case radial([String])
    public init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self) { self = .color(value); return }
        let c = try decoder.container(keyedBy: Keys.self)
        if let stops = try c.decodeIfPresent([String].self, forKey: .linear) { self = .linear(stops, angle: try c.decodeIfPresent(Double.self, forKey: .angle) ?? 90); return }
        if let stops = try c.decodeIfPresent([String].self, forKey: .radial) { self = .radial(stops); return }
        throw DecodingError.dataCorruptedError(forKey: .linear, in: c, debugDescription: "A paint is a color string, or an object with \"linear\" or \"radial\" color stops")
    }
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .color(let value): var c = encoder.singleValueContainer(); try c.encode(value)
        case .linear(let stops, let angle): var c = encoder.container(keyedBy: Keys.self); try c.encode(stops, forKey: .linear); try c.encode(angle, forKey: .angle)
        case .radial(let stops): var c = encoder.container(keyedBy: Keys.self); try c.encode(stops, forKey: .radial)
        }
    }
    enum Keys: String, CodingKey { case linear, radial, angle }
    public var stops: [String] {
        switch self { case .color(let value): [value]; case .linear(let stops, _), .radial(let stops): stops }
    }
}

/// A number, or a number driven by playback: `{ "bind": "progress", "from": 10, "to": 30, "idle": 0 }`
/// maps the binding's 0…1 value onto from…to; `idle` (optional) is used while stopped.
public enum Value: Codable, Equatable, Sendable {
    case number(Double)
    case bound(bind: String, from: Double, to: Double, idle: Double?)
    public init(from decoder: Decoder) throws {
        if let number = try? decoder.singleValueContainer().decode(Double.self) { self = .number(number); return }
        let c = try decoder.container(keyedBy: Keys.self)
        self = .bound(bind: try c.decode(String.self, forKey: .bind), from: try c.decodeIfPresent(Double.self, forKey: .from) ?? 0,
                      to: try c.decodeIfPresent(Double.self, forKey: .to) ?? 1, idle: try c.decodeIfPresent(Double.self, forKey: .idle))
    }
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .number(let n): var c = encoder.singleValueContainer(); try c.encode(n)
        case .bound(let bind, let from, let to, let idle):
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(bind, forKey: .bind); try c.encode(from, forKey: .from); try c.encode(to, forKey: .to); try c.encodeIfPresent(idle, forKey: .idle)
        }
    }
    enum Keys: String, CodingKey { case bind, from, to, idle }
    /// Resolves against binding values (each 0…1). `stopped` selects `idle` when present.
    public func resolve(_ values: [String: Double], stopped: Bool) -> Double {
        switch self {
        case .number(let n): return n
        case .bound(let bind, let from, let to, let idle):
            if stopped, let idle { return idle }
            return from + (to - from) * min(1, max(0, values[bind] ?? 0))
        }
    }
}

public struct LayoutElement: Codable, Equatable, Sendable {
    public var type: String
    public var frame: [Double]?
    // Common
    public var fill: Paint?
    public var stroke: Paint?
    public var strokeWidth: Double?
    public var corner: Double?
    public var opacity: Value?
    /// Show only when a binding is on: "playing", "!playing", "shuffle", "stopped", …
    public var visible: String?
    public var help: String?
    // image
    public var file: String?
    public var mode: String?
    // text
    public var text: String?
    public var font: String?
    public var fontSize: Double?
    public var weight: String?
    public var color: Paint?
    public var align: String?
    public var scroll: Bool?
    // button
    public var action: String?
    public var label: String?
    public var image: String?
    public var pressedImage: String?
    public var style: String?
    // slider
    public var bind: String?
    public var vertical: Bool?
    public var track: Paint?
    public var knob: Paint?
    public var knobSize: [Double]?
    public var knobImage: String?
    // spectrum
    public var gap: Double?
    public var peaks: Bool?
    public var peakColor: Paint?
    // ellipse
    public var radius: Value?
    // group
    public var children: [LayoutElement]?
    public var rotation: Value?
    public var spin: Value?
    public var pivot: [Double]?
    public var clip: Bool?

    public init(type: String, frame: [Double]? = nil) { self.type = type; self.frame = frame }

    public static let types: [(name: String, use: String)] = [
        ("rect", "rectangle: fill, stroke, strokeWidth, corner"),
        ("ellipse", "ellipse filling the frame, or a circle of `radius` centred in it: fill, stroke, strokeWidth, radius"),
        ("image", "picture file: file, mode (stretch | tile | fit)"),
        ("text", "text with {placeholders}: text, font, fontSize, weight, color, align, scroll"),
        ("spectrum", "20-band analyzer: fill (bars), gap, peaks, peakColor"),
        ("button", "clickable: action, label, style (retro | plain | none), image, pressedImage, font, fontSize, color"),
        ("slider", "drag control: bind (volume | balance | position), vertical, track, fill, knob, knobSize, knobImage"),
        ("group", "container for children: rotation, spin (rpm while playing), pivot, clip"),
        ("dragArea", "where the window can be dragged (every layout needs one)"),
        ("cassette", "the built-in animated cassette, scaled to the frame")
    ]
    public static let actions: [(name: String, use: String)] = [
        ("playPause", "play or pause"), ("play", "play"), ("pause", "pause"), ("stop", "stop"),
        ("next", "next track"), ("previous", "previous track"), ("add", "add files or folders"),
        ("shuffle", "toggle shuffle"), ("repeat", "cycle repeat off / all / one"),
        ("equalizer", "show or hide the equalizer"), ("playlist", "show or hide the playlist"),
        ("skins", "show or hide the skins panel"), ("find", "search the playlist"),
        ("toggleTime", "switch elapsed / remaining time"), ("hide", "hide the app (close button)"), ("minimize", "minimize the player")
    ]
    /// Values available to `bind`, `visible`, and bound numbers. All run 0…1.
    public static let bindings: [(name: String, use: String)] = [
        ("progress", "position in the track"), ("playing", "1 while playing"), ("paused", "1 while paused"),
        ("stopped", "1 when nothing is loaded"), ("volume", "volume"), ("balance", "balance (0 left, 0.5 centre, 1 right)"),
        ("level", "overall loudness, smoothed (good for VU needles)"), ("shuffle", "1 when shuffle is on"),
        ("repeat", "0 off, 0.5 all, 1 one"), ("remaining", "1 when the clock shows remaining time")
    ]
    public static let placeholders: [(name: String, use: String)] = [
        ("time", "elapsed or remaining time, as the user chose (mm:ss)"), ("elapsed", "elapsed time"), ("remaining", "time left"),
        ("duration", "track length"), ("title", "full track title"), ("artist", "artist (when the title is \"Artist — Song\")"),
        ("song", "song name without the artist"), ("format", "file type, e.g. MP3"), ("status", "PLAY, PAUSE or STOP"),
        ("track", "track number in the playlist"), ("count", "number of tracks"), ("shuffle", "SHUF or SHUF ●"),
        ("repeat", "R:OFF, R:ALL or R:ONE"), ("volume", "volume percent"), ("skin", "skin name")
    ]
    public static let sliderBindings: Set<String> = ["volume", "balance", "position"]
}

/// A problem found in a skin file.
public struct SkinIssue: Equatable, CustomStringConvertible, Sendable {
    public enum Severity: String, Sendable { case error, warning }
    public var severity: Severity
    public var message: String
    public var description: String { "\(severity.rawValue): \(message)" }
}

public enum SkinValidator {
    /// Checks a skin file (`.json`) or package folder. Errors stop the skin from working well;
    /// warnings point at likely mistakes.
    public static func validate(at url: URL) -> [SkinIssue] {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { return [.init(severity: .error, message: "\(url.path) does not exist")] }
        let file = isFolder.boolValue ? url.appendingPathComponent("skin.json") : url
        let folder = isFolder.boolValue ? url : url.deletingLastPathComponent()
        if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > SkinLibrary.maxSkinFileBytes {
            return [.init(severity: .error, message: "\(file.lastPathComponent) is \(size / 1000) KB; skins larger than \(SkinLibrary.maxSkinFileBytes / 1000) KB are not loaded")]
        }
        guard let data = try? Data(contentsOf: file) else { return [.init(severity: .error, message: "cannot read \(file.path)")] }
        do {
            var skin = try JSONDecoder().decode(Skin.self, from: data)
            skin.folder = folder
            return validate(skin, others: SkinLibrary.all(in: folder.deletingLastPathComponent()) + SkinLibrary.all(in: folder))
        } catch let error as DecodingError {
            return [.init(severity: .error, message: "JSON does not match the skin format: \(describe(error))")]
        } catch {
            return [.init(severity: .error, message: "invalid JSON: \(error.localizedDescription)")]
        }
    }

    public static func validate(_ skin: Skin, others: [Skin]) -> [SkinIssue] {
        var issues: [SkinIssue] = []
        func error(_ m: String) { issues.append(.init(severity: .error, message: m)) }
        func warn(_ m: String) { issues.append(.init(severity: .warning, message: m)) }
        let tokens = Set(Skin.tokens.map(\.name))

        if let base = skin.basedOn, !(Skin.builtIn + others).contains(where: { $0.id == base || $0.name == base }) {
            warn("basedOn \"\(base)\" is not a known skin; falling back to Classic")
        }
        for (token, value) in skin.colors {
            if !tokens.contains(token) { warn("unknown color token \"\(token)\"") }
            if SkinLibrary.rgba(value) == nil { error("color \"\(token)\" has \(value), expected #RRGGBB or #RRGGBBAA") }
        }
        let slots = Set(Skin.imageSlots.map(\.name))
        for (slot, spec) in skin.images ?? [:] {
            if !slots.contains(slot) { warn("unknown image slot \"\(slot)\"") }
            checkFile(spec.file, in: skin.folder, what: "image \"\(slot)\"", error)
        }
        let roles = Set(Skin.fontRoles.map(\.name))
        for (role, font) in skin.fonts ?? [:] {
            if !roles.contains(role) { warn("unknown font role \"\(role)\"") }
            if SkinLibrary.fontExtensions.contains((font as NSString).pathExtension.lowercased()) { checkFile(font, in: skin.folder, what: "font \"\(role)\"", error) }
        }
        if let shape = skin.shape {
            if let v = shape.cassetteWindow, !["wide", "twin"].contains(v) { error("shape.cassetteWindow must be \"wide\" or \"twin\"") }
            if let v = shape.reels, !["teeth", "spokes", "solid"].contains(v) { error("shape.reels must be \"teeth\", \"spokes\" or \"solid\"") }
            if let v = shape.label, !["stripes", "plain"].contains(v) { error("shape.label must be \"stripes\" or \"plain\"") }
        }
        if let layout = skin.layout { validate(layout, skin: skin, error: error, warn: warn) }
        return issues
    }

    static func validate(_ layout: SkinLayout, skin: Skin, error: (String) -> Void, warn: (String) -> Void) {
        guard layout.size.count == 2, SkinLayout.sizeLimits.width.contains(layout.width), SkinLayout.sizeLimits.height.contains(layout.height) else {
            error("layout.size must be [width, height] between [100, 40] and [1600, 1200]"); return
        }
        var total = 0, deepest = 0
        let types = Set(LayoutElement.types.map(\.name)), actions = Set(LayoutElement.actions.map(\.name))
        let bindings = Set(LayoutElement.bindings.map(\.name)), placeholders = Set(LayoutElement.placeholders.map(\.name))
        let tokens = Set(Skin.tokens.map(\.name)), roles = Set(Skin.fontRoles.map(\.name))
        var hasDrag = false, hasPlay = false, hasHide = false
        func paint(_ p: Paint?, _ path: String) {
            for stop in p?.stops ?? [] where !tokens.contains(stop) && SkinLibrary.rgba(stop) == nil {
                error("\(path): \"\(stop)\" is neither a color token nor #RRGGBB(AA)")
            }
        }
        func value(_ v: Value?, _ path: String) {
            if case .bound(let bind, _, _, _) = v, !bindings.contains(bind) { error("\(path): unknown binding \"\(bind)\"") }
        }
        func walk(_ elements: [LayoutElement], parent: [Double], path: String, depth: Int = 1) {
            total += elements.count; deepest = max(deepest, elements.isEmpty ? 0 : depth)
            guard depth <= SkinLayout.maxDepth else { return }
            for (index, e) in elements.enumerated() {
                let here = "\(path)[\(index)] (\(e.type))"
                guard types.contains(e.type) else { error("\(here): unknown element type; use one of \(types.sorted().joined(separator: ", "))"); continue }
                guard let f = e.frame, f.count == 4 else { error("\(here): needs \"frame\": [x, y, width, height]"); continue }
                if f[2] <= 0 || f[3] <= 0 { error("\(here): frame width and height must be positive") }
                if f[0] < -0.5 || f[1] < -0.5 || f[0] + f[2] > parent[0] + 0.5 || f[1] + f[3] > parent[1] + 0.5 { warn("\(here): frame \(f) reaches outside its parent (\(Int(parent[0]))×\(Int(parent[1])))") }
                paint(e.fill, here); paint(e.stroke, here); paint(e.color, here); paint(e.track, here); paint(e.knob, here); paint(e.peakColor, here)
                value(e.opacity, here); value(e.radius, here); value(e.rotation, here); value(e.spin, here)
                if let v = e.visible, !bindings.contains(v.hasPrefix("!") ? String(v.dropFirst()) : v) { error("\(here): visible \"\(v)\" is not a binding") }
                if let font = e.font, !roles.contains(font), SkinLibrary.fontExtensions.contains((font as NSString).pathExtension.lowercased()) {
                    checkFile(font, in: skin.folder, what: "\(here) font", error)
                }
                for (name, file) in [("file", e.file), ("image", e.image), ("pressedImage", e.pressedImage), ("knobImage", e.knobImage)] {
                    if let file { checkFile(file, in: skin.folder, what: "\(here) \(name)", error) }
                }
                if (e.rotation != nil || e.spin != nil || e.pivot != nil) && e.type != "group" { warn("\(here): rotation, spin and pivot only work on groups") }
                switch e.type {
                case "image": if e.file == nil { error("\(here): needs \"file\"") }
                case "text":
                    guard let text = e.text else { error("\(here): needs \"text\""); break }
                    for name in placeholderNames(in: text) where !placeholders.contains(name) { error("\(here): unknown placeholder {\(name)}") }
                case "button":
                    guard let action = e.action, actions.contains(action) else { error("\(here): needs an \"action\": \(actions.sorted().joined(separator: ", "))"); break }
                    if action == "playPause" || action == "play" { hasPlay = true }
                    if action == "hide" { hasHide = true }
                    if let label = e.label { for name in placeholderNames(in: label) where !placeholders.contains(name) { error("\(here): unknown placeholder {\(name)}") } }
                case "slider":
                    if !LayoutElement.sliderBindings.contains(e.bind ?? "") { error("\(here): \"bind\" must be volume, balance or position") }
                case "dragArea": hasDrag = true
                case "group": walk(e.children ?? [], parent: [f[2], f[3]], path: here + ".children", depth: depth + 1)
                default: break
                }
            }
        }
        walk(layout.elements, parent: [layout.width, layout.height], path: "layout.elements")
        if total > SkinLayout.maxElements { error("layout has \(total) elements; the limit is \(SkinLayout.maxElements), the rest are ignored") }
        if deepest > SkinLayout.maxDepth { error("groups are nested \(deepest) deep; the limit is \(SkinLayout.maxDepth), deeper ones are ignored") }
        if !hasDrag { error("layout has no \"dragArea\", so the window could not be moved") }
        if !hasPlay { warn("layout has no play or playPause button") }
        if !hasHide { warn("layout has no button with action \"hide\" (a close button)") }
    }

    static func placeholderNames(in text: String) -> [String] {
        var names: [String] = [], current: String?
        for ch in text {
            if ch == "{" { current = "" } else if ch == "}", let name = current { names.append(name); current = nil } else if current != nil { current!.append(ch) }
        }
        return names
    }

    static func checkFile(_ file: String, in folder: URL?, what: String, _ error: (String) -> Void) {
        if file.hasPrefix("@") {   // "@slot" = the skin's image for that slot, if any
            if !Skin.imageSlots.contains(where: { "@" + $0.name == file }) { error("\(what): \"\(file)\" is not an image slot") }
            return
        }
        let path = SkinLibrary.absolute(file, in: folder)
        if path.isEmpty { error("\(what): \"\(file)\" must be inside the skin's folder") }
        else if !FileManager.default.fileExists(atPath: path) { error("\(what): file \"\(file)\" not found") }
    }

    static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String { context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        switch error {
        case .keyNotFound(let key, let c): return "missing \"\(key.stringValue)\" at \(path(c).isEmpty ? "top level" : path(c))"
        case .typeMismatch(_, let c), .valueNotFound(_, let c), .dataCorrupted(let c): return "\(path(c)): \(c.debugDescription)"
        @unknown default: return error.localizedDescription
        }
    }
}

extension SkinLayout {
    public static let sizeLimits = (width: 100.0...1600.0, height: 40.0...1200.0)
    /// Most elements (including group children) and deepest group nesting a layout may have.
    public static let maxElements = 2000, maxDepth = 8

    /// A copy that is safe to draw, or nil when the size is unusable. Skins come from other people,
    /// so numbers are forced into sane ranges and oversized or malformed parts are dropped; a skin
    /// must never be able to crash the app, hang it, or open a window far bigger than the screen.
    public func sanitized() -> SkinLayout? {
        guard size.count == 2, size.allSatisfy(\.isFinite),
              Self.sizeLimits.width.contains(size[0]), Self.sizeLimits.height.contains(size[1]) else { return nil }
        func number(_ value: Double?, _ range: ClosedRange<Double>) -> Double? {
            value.flatMap { $0.isFinite ? min(range.upperBound, max(range.lowerBound, $0)) : nil }
        }
        func value(_ v: Value?) -> Value? {
            switch v {
            case .number(let n)?: return n.isFinite ? v : nil
            case .bound(let bind, let from, let to, let idle)?:
                guard from.isFinite, to.isFinite else { return nil }
                return .bound(bind: bind, from: from, to: to, idle: idle.flatMap { $0.isFinite ? $0 : nil })
            case nil: return nil
            }
        }
        func paint(_ p: Paint?) -> Paint? {
            switch p {
            case .linear(let stops, let angle)?: return .linear(Array(stops.prefix(16)), angle: angle.isFinite ? angle : 90)
            case .radial(let stops)?: return .radial(Array(stops.prefix(16)))
            default: return p
            }
        }
        func pair(_ values: [Double]?, positive: Bool) -> [Double]? {
            guard let values, values.count == 2, values.allSatisfy({ $0.isFinite && abs($0) <= 4000 && (!positive || $0 > 0) }) else { return nil }
            return values
        }
        var budget = Self.maxElements
        func clean(_ elements: [LayoutElement], depth: Int) -> [LayoutElement] {
            guard depth <= Self.maxDepth else { return [] }
            var result: [LayoutElement] = []
            for var e in elements {
                guard budget > 0 else { break }
                guard let f = e.frame, f.count == 4, f.allSatisfy({ $0.isFinite && abs($0) <= 10_000 }), f[2] > 0, f[3] > 0 else { continue }
                budget -= 1
                e.fill = paint(e.fill); e.stroke = paint(e.stroke); e.color = paint(e.color)
                e.track = paint(e.track); e.knob = paint(e.knob); e.peakColor = paint(e.peakColor)
                e.strokeWidth = number(e.strokeWidth, 0...200); e.corner = number(e.corner, 0...2000)
                e.fontSize = number(e.fontSize, 1...400); e.gap = number(e.gap, 0...200)
                e.opacity = value(e.opacity); e.radius = value(e.radius); e.rotation = value(e.rotation); e.spin = value(e.spin)
                e.knobSize = pair(e.knobSize, positive: true); e.pivot = pair(e.pivot, positive: false)
                e.text = e.text.map { String($0.prefix(500)) }; e.label = e.label.map { String($0.prefix(200)) }
                e.help = e.help.map { String($0.prefix(300)) }
                e.children = e.type == "group" ? clean(e.children ?? [], depth: depth + 1) : nil
                result.append(e)
            }
            return result
        }
        return SkinLayout(size: size, elements: clean(elements, depth: 1))
    }

    /// Turns relative file names inside the layout into absolute paths within `folder`.
    func absolutized(in folder: URL?) -> SkinLayout {
        func path(_ file: String) -> String { file.hasPrefix("@") ? file : SkinLibrary.absolute(file, in: folder) }
        func fix(_ e: LayoutElement) -> LayoutElement {
            var e = e
            e.file = e.file.map(path)
            e.image = e.image.map(path)
            e.pressedImage = e.pressedImage.map(path)
            e.knobImage = e.knobImage.map(path)
            if let font = e.font, SkinLibrary.fontExtensions.contains((font as NSString).pathExtension.lowercased()) { e.font = SkinLibrary.absolute(font, in: folder) }
            e.children = e.children?.map(fix)
            return e
        }
        return SkinLayout(size: size, elements: elements.map(fix))
    }
}
