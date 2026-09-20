// SnapshotUI — renders the hand-entry UI to PNG in both layouts, with a
// sample hand entered and scored. Lets us eyeball the iPhone (compact) and
// Mac (wide) layouts without a simulator or screen-recording permission.
//
// ImageRenderer draws ScrollView content as empty, so this composes the
// public components directly (same order as HandEntryScreen) instead of
// rendering HandEntryScreen itself.
//
// Usage:
//   swift run SnapshotUI <output-dir>
// Writes compact.png and situations.png (390pt wide @2x) and wide.png (1000pt wide @2x).

import AppKit
import SwiftUI
import MahjongCore
import MahjongUI

let outDir = CommandLine.arguments.dropFirst().first ?? "."

@MainActor
func render<V: View>(_ view: V, width: CGFloat, to filename: String) {
    let content = view
        .frame(width: width)
        .background(Color(nsColor: .windowBackgroundColor))
    let renderer = ImageRenderer(content: content)
    renderer.scale = 2
    guard let cg = renderer.cgImage else {
        print("render failed: \(filename)")
        return
    }
    let rep = NSBitmapImageRep(cgImage: cg)
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(filename)
    do {
        try rep.representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.path)")
    } catch {
        print("write failed: \(error)")
    }
}

@MainActor
func sampleModel() -> HandEntryModel {
    let model = HandEntryModel(defaults: UserDefaults(suiteName: "SnapshotUI")!)
    model.target = .exposed
    for n in ["5p", "5p", "5p"] { model.add(try! Tile(n)) }
    model.target = .concealed
    for n in ["1m", "2m", "3m", "1p", "1p", "1p", "1s", "2s", "3s",
              "Ew", "Ew", "Ew", "Nw", "Nw"] {
        model.add(try! Tile(n))
    }
    model.add(try! Tile("1f"))
    model.add(try! Tile("6f"))
    model.roundWind = .east
    model.seatWind = .east
    model.isDealer = true
    model.score()
    return model
}

MainActor.assumeIsolated {
    let model = sampleModel()

    let compact = VStack(alignment: .leading, spacing: 12) {
        TileGridPicker(model: model)
        HandStripView(model: model)
        ScoreErrorBanner(model: model)
        Divider()
        ContextFormView(model: model)
        Divider()
        ScoreResultView(model: model)
    }
    .padding(12)
    render(compact, width: 390, to: "compact.png")

    let wide = HStack(alignment: .top, spacing: 24) {
        VStack(alignment: .leading, spacing: 12) {
            HandStripView(model: model)
            Divider()
            ContextFormView(model: model)
            Divider()
            ScoreResultView(model: model)
        }
        .frame(width: 400)
        TileGridPicker(model: model)
            .frame(width: 520)
    }
    .padding(16)
    render(wide, width: 1000, to: "wide.png")

    // The situations list, expanded, at phone width.
    let situations = ContextFormView(model: model, initiallyExpanded: true).padding(12)
    render(situations, width: 390, to: "situations.png")

    // The table-payments reference sheet, at phone width.
    render(TablePaymentsList(taiBase: model.taiBase).padding(16), width: 390, to: "payments.png")
}
