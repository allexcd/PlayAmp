import SwiftUI
#if canImport(PlayAmpCore)
import PlayAmpCore
#endif

/// The Skins window: every skin with a small preview; one click switches to it.
struct SkinsView: View {
    @ObservedObject var model: Model
    var windows: Windows
    @Environment(\.palette) private var palette
    var body: some View {
        Chrome(title: "PlayAmp • SKINS", close: { windows.toggle(.skins) }, slot: "skins", grip: true) {
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(model.skins) { skin in
                            SkinRow(skin: SkinLibrary.resolved(skin.id, in: model.skins), active: skin.id == model.skin.id) {
                                windows.useSkin(skin.id)
                            }.id(skin.id)
                        }
                    }.padding(2)
                }.background(palette.surface("display", palette.displayBackground))
                // Opening the panel shows the active skin; after that the list stays wherever the user scrolls.
                .onAppear { let id = model.skin.id; DispatchQueue.main.async { scroller.scrollTo(id, anchor: .center) } }
            }
            HStack(spacing: 3) {
                Button("FOLDER") { NSWorkspace.shared.open(model.prepareSkinFolder()) }.help("Open the folder for your own .json skins")
                Button("RELOAD") { model.refreshSkins(); windows.applySkin() }.help("Re-read the skins folder")
                Spacer()
                Text("\(model.skins.count) SKINS").font(palette.font("ui", 8)).foregroundStyle(palette.panelAccent)
            }.buttonStyle(RetroButton()).padding(.trailing, 9)   // room for the size grip
        }.frame(width: 275).frame(maxHeight: .infinity)
        .onAppear { model.reloadSkins() }   // pick up files added since last time
    }
}

private struct SkinRow: View {
    let skin: Skin   // resolved, so every color is present
    let active: Bool
    let choose: () -> Void
    @State private var hovering = false
    @Environment(\.palette) private var palette
    var body: some View {
        Button(action: choose) {
            HStack(spacing: 6) {
                SkinThumbnail(palette: Palette(skin))
                VStack(alignment: .leading, spacing: 1) {
                    Text(skin.name).font(palette.font("display", 9, .bold))
                        .foregroundStyle(active ? palette.displayHighlight : palette.display).lineLimit(1)
                    Text("\(skin.layout != nil ? "LAYOUT" : skin.face == .cassette ? "CASSETTE" : "CLASSIC") • \(Skin.builtIn.contains { $0.id == skin.id } ? "BUILT-IN" : "CUSTOM")")
                        .font(palette.font("display", 7)).foregroundStyle(palette.displayDim)
                }
                Spacer(minLength: 0)
                Text(active ? "● ON" : "").font(palette.font("display", 7, .bold)).foregroundStyle(palette.display)
            }.padding(.horizontal, 4).padding(.vertical, 3).frame(maxWidth: .infinity)
            .background(active ? palette.playingRow : hovering ? palette.playingRow.opacity(0.5) : .clear)
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovering = $0 }
        .accessibilityLabel("\(skin.name) skin\(active ? ", selected" : "")")
    }
}

/// A miniature of the player drawn with the skin's own colors.
private struct SkinThumbnail: View {
    let palette: Palette
    var body: some View {
        ZStack {
            Rectangle().fill(palette.panel)
            if let layout = palette.layout {
                // A real miniature of the skin's own player design.
                let scale = min(56 / layout.width, 27 / layout.height)
                LayoutCanvas(layout: layout, state: .still)
                    .environment(\.palette, palette).environment(\.renderingPreview, true)
                    .scaleEffect(scale).frame(width: layout.width * scale, height: layout.height * scale)
                    .allowsHitTesting(false)
            } else if palette.face == .cassette {
                HStack(spacing: 3) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 2).fill(palette["deck"])
                        RoundedRectangle(cornerRadius: 2).fill(palette["cassetteShell"]).frame(width: 30, height: 19)
                        VStack(spacing: 0) {
                            Rectangle().fill(palette["cassetteLabel"]).frame(height: 4)
                            Rectangle().fill(palette["cassetteStripe1"]).frame(height: 2)
                            Rectangle().fill(palette["cassetteStripe2"]).frame(height: 2)
                            Rectangle().fill(palette["cassetteLabel"]).frame(height: 4)
                        }.frame(width: 26).offset(y: -2)
                        HStack(spacing: 6) {
                            Circle().fill(palette["reel"]).frame(width: 5, height: 5)
                            Circle().fill(palette["reel"]).frame(width: 5, height: 5)
                        }.offset(y: -1)
                    }.frame(width: 34, height: 23)
                    Text("12").font(palette.font("display", 7, .bold)).foregroundStyle(palette.display)
                        .frame(width: 14, height: 10).background(palette.surface("display", palette.displayBackground))
                }
            } else {
                HStack(spacing: 2) {
                    Text("0:42").font(palette.font("display", 8, .bold)).foregroundStyle(palette.display)
                        .frame(width: 26, height: 20).background(palette.surface("display", palette.displayBackground))
                    HStack(alignment: .bottom, spacing: 1) {
                        ForEach([0.5, 0.9, 0.7, 0.4, 0.6], id: \.self) { level in
                            Rectangle().fill(palette.spectrum).frame(width: 2, height: 14 * level)
                        }
                    }.frame(width: 16, height: 18, alignment: .bottom).background(palette.surface("display", palette.displayBackground))
                }
            }
        }.frame(width: 56, height: 27).overlay(Rectangle().strokeBorder(palette.border, lineWidth: 0.5))
    }
}
