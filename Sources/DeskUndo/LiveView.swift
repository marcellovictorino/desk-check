import DeskUndoCore
import AppKit
import SwiftUI

/// A small window that stays on top while the desk is cranked. Closing it turns the camera off.
struct LiveView: View {
    @ObservedObject var live: LiveController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Live adjustment").font(.headline)
                Spacer()
                Text(live.setupName).font(.caption).foregroundStyle(.secondary)
            }
            if live.advice.isEmpty {
                Text(live.isRunning ? "Waiting for a steady reading…" : "Start live mode, then move the desk or screen.")
                    .foregroundStyle(.secondary)
            }
            ForEach(live.advice, id: \.adjustment) { BandRow(item: $0) }
            Text(live.statusText).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button(live.isRunning ? "Stop" : "Start") { live.isRunning ? live.stop() : live.start() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .frame(width: 300)
        .background(FloatingWindow())
        .onAppear { live.start() }
        .onDisappear { live.stop() }
    }
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
        .padding(8)
        .background(colour.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.adjustment.label): \(item.level == .green ? "green" : item.level == .yellow ? "yellow" : "red"). \(item.text)")
    }
}

/// Keeps the live window above other windows so it stays visible while the desk is cranked.
struct FloatingWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.level = .floating }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}
