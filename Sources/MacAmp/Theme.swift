import SwiftUI
import CoreText
#if canImport(MacAmpCore)
import MacAmpCore
#endif

/// The active skin as ready-to-use SwiftUI values: colors, images, fonts, shapes and layout.
/// Views read it from the environment.
struct Palette {
    let name: String
    let face: Skin.Face
    let layout: SkinLayout?
    let windowCorner: CGFloat
    let buttonCorner: CGFloat
    let cassetteWindow: String
    let reels: String
    let labelStyle: String
    private let colors: [String: Color]
    private let images: [String: SkinImage]
    private let fonts: [String: String]

    init(_ skin: Skin) {
        name = skin.name
        face = skin.face ?? .classic
        layout = skin.layout
        windowCorner = CGFloat(skin.shape?.windowCorner ?? 0)
        buttonCorner = CGFloat(skin.shape?.buttonCorner ?? 0)
        cassetteWindow = skin.shape?.cassetteWindow ?? "wide"
        reels = skin.shape?.reels ?? "teeth"
        labelStyle = skin.shape?.label ?? "stripes"
        colors = skin.colors.compactMapValues(Palette.color(hex:))
        images = (skin.images ?? [:]).compactMapValues { spec in SkinImage.load(spec.file, mode: spec.mode.rawValue) }
        fonts = (skin.fonts ?? [:]).compactMapValues(FontRegistry.name(for:))
    }
    static func color(hex: String) -> Color? {
        SkinLibrary.rgba(hex).map { Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue, opacity: $0.alpha) }
    }
    /// A token name ("display") or a hex color.
    subscript(_ token: String) -> Color { colors[token] ?? Palette.color(hex: token) ?? .pink }

    var display: Color { self["display"] }
    var displayBackground: Color { self["displayBackground"] }
    var displayDim: Color { self["displayDim"] }
    var displayHighlight: Color { self["displayHighlight"] }
    var playingRow: Color { self["playingRow"] }
    var border: Color { self["border"] }
    var text: Color { self["text"] }
    var panelAccent: Color { self["panelAccent"] }
    var panel: LinearGradient { LinearGradient(colors: [self["panelTop"], self["panelMid"], self["panelBottom"]], startPoint: .topLeading, endPoint: .bottomTrailing) }
    func button(pressed: Bool) -> LinearGradient {
        LinearGradient(colors: [pressed ? self["buttonPressed"] : self["buttonTop"], self["buttonBottom"]], startPoint: .top, endPoint: .bottom)
    }
    var buttonText: Color { self["buttonText"] }
    var sliderFill: LinearGradient { LinearGradient(colors: [self["sliderFillStart"], self["sliderFillEnd"]], startPoint: .leading, endPoint: .trailing) }
    var knob: LinearGradient { LinearGradient(colors: [self["knob"], self["buttonBottom"]], startPoint: .top, endPoint: .bottom) }
    var spectrum: LinearGradient { LinearGradient(colors: [self["spectrumHigh"], self["spectrumMid"], display], startPoint: .top, endPoint: .bottom) }

    // MARK: Images
    /// The skin's image for a slot. Window slots fall back to "panel".
    func image(_ slot: String) -> SkinImage? {
        images[slot] ?? (["player", "playlist", "equalizer", "skins"].contains(slot) ? images["panel"] : nil)
    }
    func hasImage(_ slot: String) -> Bool { image(slot) != nil }
    /// The image for `slot` if the skin has one, otherwise `fallback`.
    @ViewBuilder func surface<S: ShapeStyle>(_ slot: String, _ fallback: S) -> some View {
        if let image = image(slot) { image.view } else { Rectangle().fill(fallback) }
    }

    // MARK: Fonts
    /// Font for a role ("display", "ui", "label"), using the skin's choice when it has one.
    func font(_ role: String, _ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if let name = fonts[role] { return .custom(name, size: size).weight(weight) }
        return role == "label" ? .custom("Marker Felt", size: size).weight(weight) : .system(size: size, weight: weight, design: .monospaced)
    }
    /// A layout's `font` field: a role, an installed font name, or a font file path.
    func font(spec: String?, _ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard let spec else { return font("ui", size, weight) }
        if Skin.fontRoles.contains(where: { $0.name == spec }) { return font(spec, size, weight) }
        return .custom(FontRegistry.name(for: spec) ?? spec, size: size).weight(weight)
    }

    static let classic = Palette(Skin.classic)
}

/// An image from a skin, cached by path, drawn stretched, tiled or fitted.
struct SkinImage {
    let image: NSImage
    let mode: String
    nonisolated(unsafe) private static var cache: [String: NSImage] = [:]
    private static let lock = NSLock()
    static func load(_ path: String, mode: String) -> SkinImage? {
        guard !path.isEmpty, !path.hasPrefix("@") else { return nil }
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[path] { return SkinImage(image: cached, mode: mode) }
        guard acceptable(path), let image = NSImage(contentsOfFile: path) else { return nil }
        cache[path] = image
        return SkinImage(image: image, mode: mode)
    }
    static let extensions: Set<String> = ["png", "jpg", "jpeg", "gif", "tif", "tiff", "bmp", "heic", "webp", "pdf"]
    static let maxBytes = 25_000_000, maxPixels = 8192
    /// Skin images come from other people: only ordinary picture files of a sane size are opened,
    /// so a tiny file that unpacks into a gigantic bitmap can't exhaust memory.
    static func acceptable(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard extensions.contains(url.pathExtension.lowercased()),
              let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, bytes <= maxBytes else { return false }
        if url.pathExtension.lowercased() == "pdf" { return true }   // vector: no pixel size to check
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = info[kCGImagePropertyPixelWidth] as? Int, let height = info[kCGImagePropertyPixelHeight] as? Int else { return false }
        return width <= maxPixels && height <= maxPixels
    }
    /// Forget loaded images so edited files are re-read (Reload in the Skins panel).
    static func clearCache() { lock.lock(); cache.removeAll(); lock.unlock() }
    @ViewBuilder var view: some View {
        switch mode {
        case "tile": Image(nsImage: image).resizable(resizingMode: .tile)
        case "fit": Image(nsImage: image).resizable().scaledToFit()
        default: Image(nsImage: image).resizable()
        }
    }
}

/// Registers font files shipped inside skins and returns usable font names.
enum FontRegistry {
    nonisolated(unsafe) private static var names: [String: String] = [:]
    static let maxBytes = 30_000_000
    private static let lock = NSLock()
    /// Installed font names pass through; .ttf/.otf/.ttc paths are registered for this process.
    static func name(for spec: String) -> String? {
        guard spec.hasPrefix("/") else { return spec.isEmpty ? nil : spec }
        lock.lock(); defer { lock.unlock() }
        if let known = names[spec] { return known }
        guard let bytes = try? URL(fileURLWithPath: spec).resourceValues(forKeys: [.fileSizeKey]).fileSize, bytes <= maxBytes else { return nil }
        let url = URL(fileURLWithPath: spec) as CFURL
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor],
              let name = descriptors.first.flatMap({ CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String }) else { return nil }
        CTFontManagerRegisterFontsForURL(url, .process, nil)
        names[spec] = name
        return name
    }
}

private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette.classic }
extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}
