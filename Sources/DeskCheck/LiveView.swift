import DeskCheckCore
import AppKit
import SwiftUI

/// Live adjustment inside the menu bar popover. Its height never changes: the title and Stop sit in a header, the
/// bands have a reserved area, and the status text has a reserved line pair, so Stop stays where the pointer is.
struct LiveView: View {
    @ObservedObject var live: LiveController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Live adjustment").font(.headline)
                Text(live.setupName).font(.caption).foregroundStyle(.secondary)
                Spacer()
                // Esc stops Live and returns to the main view; Esc there, or a click away, closes the popover.
                Button("Stop") { live.stop() }.keyboardShortcut(.cancelAction).glassButton(prominent: true)
            }
            Text(InstructionText.live).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ZStack(alignment: .top) {
                if live.advice.isEmpty {
                    Text(live.isRunning ? "Waiting for a steady reading…" : LiveController.offText)
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    GlassGroup(spacing: LiveLayout.rowSpacing) {
                        VStack(spacing: LiveLayout.rowSpacing) {
                            ForEach(live.advice, id: \.adjustment) { BandRow(item: $0) }
                        }
                    }
                }
            }
            .frame(height: LiveLayout.bandAreaHeight(rows: live.rowCount), alignment: .top)
            Text(live.statusText).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: 32, alignment: .topLeading)
        }
    }
}

/// The one instruction line each window carries.
enum InstructionText {
    static let popover = "Check desk measures once. Live shows the bands while you move the desk."
    static let live = "Move the desk or screen until every band is green. Stop turns the camera off."
    static let settings = "Measure with a tape, type centimetres, then Save. Hover a field to see where the tape runs."
}

struct BandRow: View {
    let item: LiveAdvice

    private var colour: Color { item.level == .green ? .green : item.level == .yellow ? .yellow : .red }
    private var symbol: String {
        switch item.direction {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .closer: return "arrow.left.to.line"
        case .further: return "arrow.right.to.line"
        case .none: return "checkmark"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(colour).frame(width: 14, height: 14)
            Text(item.adjustment.label).frame(width: 110, alignment: .leading)
            Spacer()
            Image(systemName: symbol).font(.title2)
            Text(item.direction == .none ? "OK" : "\(item.moveCm) cm")
                .font(.system(.title2, design: .rounded).monospacedDigit()).frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: LiveLayout.rowHeight)
        .glassTile(tint: colour)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.adjustment.label): \(item.level == .green ? "green" : item.level == .yellow ? "yellow" : "red"). \(item.text)")
    }
}
