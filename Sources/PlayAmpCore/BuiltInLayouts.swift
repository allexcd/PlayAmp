import Foundation

/// Built-in layouts, written in the same JSON format user skins use (see SkinLayout).
enum BuiltInLayouts {
    /// A record player: spinning record and label at 33⅓ rpm, tonearm that tracks the song's progress.
    static let turntable = #"""
    {
      "size": [275, 179],
      "elements": [
        { "type": "rect", "frame": [0, 0, 275, 179], "corner": 8,
          "fill": { "linear": ["panelTop", "panelMid", "panelBottom"], "angle": 120 }, "stroke": "border", "strokeWidth": 1 },
        { "type": "image", "frame": [0, 0, 275, 179], "file": "@player", "corner": 8 },
        { "type": "dragArea", "frame": [0, 0, 255, 17] },
        { "type": "text", "frame": [0, 4, 275, 10], "text": "PLAYAMP • {skin}", "font": "ui", "fontSize": 7, "weight": "bold", "color": "text", "align": "center" },
        { "type": "button", "frame": [259, 3, 12, 11], "action": "hide", "label": "×", "help": "Hide PlayAmp" },

        { "type": "rect", "frame": [6, 18, 140, 124], "corner": 5, "fill": "deck", "stroke": "#00000080", "strokeWidth": 1 },
        { "type": "image", "frame": [6, 18, 140, 124], "file": "@deck", "corner": 5 },
        { "type": "ellipse", "frame": [14, 22, 116, 116], "fill": { "radial": ["tonearm", "#5E5E5A"] } },
        { "type": "ellipse", "frame": [17, 25, 110, 110], "fill": "vinyl" },
        { "type": "ellipse", "frame": [22, 30, 100, 100], "stroke": "#FFFFFF14", "strokeWidth": 0.6 },
        { "type": "ellipse", "frame": [28, 36, 88, 88], "stroke": "#FFFFFF10", "strokeWidth": 0.6 },
        { "type": "ellipse", "frame": [34, 42, 76, 76], "stroke": "#FFFFFF14", "strokeWidth": 0.6 },
        { "type": "ellipse", "frame": [40, 48, 64, 64], "stroke": "#FFFFFF0E", "strokeWidth": 0.6 },
        { "type": "group", "frame": [17, 25, 110, 110], "spin": 33.33, "children": [
          { "type": "rect", "frame": [53, 5, 4, 14], "corner": 2, "fill": "#FFFFFF1C" },
          { "type": "ellipse", "frame": [36, 36, 38, 38], "fill": "recordLabel" },
          { "type": "image", "frame": [36, 36, 38, 38], "file": "@recordLabel", "corner": 19 },
          { "type": "text", "frame": [38, 44, 34, 8], "text": "{song}", "font": "label", "fontSize": 5.5, "color": "cassetteInk", "align": "center" },
          { "type": "text", "frame": [38, 59, 34, 6], "text": "33⅓ RPM", "font": "ui", "fontSize": 3.5, "weight": "bold", "color": "cassetteInk", "align": "center" }
        ] },
        { "type": "ellipse", "frame": [17, 25, 110, 110], "fill": { "linear": ["#FFFFFF1A", "#FFFFFF00", "#FFFFFF0C"], "angle": 135 } },
        { "type": "ellipse", "frame": [69, 77, 6, 6], "fill": "reel" },
        { "type": "group", "frame": [112, 22, 32, 118], "pivot": [16, 12],
          "rotation": { "bind": "progress", "from": 18, "to": 34, "idle": 0 }, "children": [
          { "type": "rect", "frame": [14.5, 12, 3, 92], "corner": 1.5, "fill": "tonearm" },
          { "type": "rect", "frame": [10, 100, 12, 15], "corner": 2, "fill": "#2B2B2B", "stroke": "tonearm", "strokeWidth": 0.8 },
          { "type": "ellipse", "frame": [6, 2, 20, 20], "fill": { "radial": ["tonearm", "#77776F"] }, "stroke": "#00000060", "strokeWidth": 0.8 }
        ] },
        { "type": "ellipse", "frame": [133, 129, 7, 7], "fill": "spectrumHigh", "visible": "playing" },
        { "type": "ellipse", "frame": [133, 129, 7, 7], "fill": "#00000070", "visible": "!playing" },

        { "type": "rect", "frame": [151, 20, 118, 28], "corner": 3, "fill": "displayBackground", "stroke": "border", "strokeWidth": 0.5 },
        { "type": "image", "frame": [151, 20, 118, 28], "file": "@display", "corner": 3 },
        { "type": "button", "frame": [151, 20, 118, 28], "action": "toggleTime", "style": "none", "help": "Elapsed or remaining time" },
        { "type": "text", "frame": [151, 22, 118, 24], "text": "{time}", "font": "display", "fontSize": 20, "color": "display", "align": "center" },
        { "type": "rect", "frame": [151, 51, 118, 20], "corner": 3, "fill": "displayBackground" },
        { "type": "spectrum", "frame": [155, 53, 110, 16], "gap": 1, "peaks": true },
        { "type": "rect", "frame": [151, 74, 118, 24], "corner": 3, "fill": "displayBackground" },
        { "type": "text", "frame": [155, 75, 110, 11], "text": "{title}", "font": "display", "fontSize": 9, "color": "display", "scroll": true },
        { "type": "text", "frame": [155, 86, 110, 10], "text": "{status} • {format}", "font": "display", "fontSize": 7, "color": "displayDim" },
        { "type": "text", "frame": [151, 101, 76, 8], "text": "VOL · BAL", "font": "ui", "fontSize": 6, "weight": "bold", "color": "text" },
        { "type": "slider", "frame": [151, 110, 76, 10], "bind": "volume" },
        { "type": "slider", "frame": [231, 110, 38, 10], "bind": "balance" },
        { "type": "button", "frame": [151, 125, 22, 13], "action": "equalizer", "label": "EQ" },
        { "type": "button", "frame": [176, 125, 22, 13], "action": "playlist", "label": "PL" },
        { "type": "button", "frame": [201, 125, 22, 13], "action": "skins", "label": "SK" },

        { "type": "slider", "frame": [6, 147, 263, 10], "bind": "position" },
        { "type": "button", "frame": [6, 161, 22, 14], "action": "previous", "label": "|◀" },
        { "type": "button", "frame": [30, 161, 22, 14], "action": "playPause", "label": "▶" },
        { "type": "button", "frame": [54, 161, 22, 14], "action": "pause", "label": "Ⅱ" },
        { "type": "button", "frame": [78, 161, 22, 14], "action": "stop", "label": "■" },
        { "type": "button", "frame": [102, 161, 22, 14], "action": "next", "label": "▶|" },
        { "type": "button", "frame": [126, 161, 22, 14], "action": "add", "label": "⏏" },
        { "type": "button", "frame": [203, 161, 36, 14], "action": "shuffle", "label": "{shuffle}" },
        { "type": "button", "frame": [241, 161, 28, 14], "action": "repeat", "label": "{repeat}" }
      ]
    }
    """#
}
