import SwiftUI

/// Liquid Glass on macOS 26 and later, with the plain look the app had on macOS 14 and 15.
/// The glass APIs exist only in the macOS 26 SDK, so every use sits behind an availability check.
extension View {
    /// A glass push button; `prominent` is the one main action of a window.
    @ViewBuilder func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }

    /// A small icon button in a header: glass on macOS 26, a plain borderless icon before.
    @ViewBuilder func glassIconButton() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.small)
        } else {
            buttonStyle(.borderless)
        }
    }

    /// A rounded tile of tinted glass for one row of advice or one Live band.
    @ViewBuilder func glassTile(tint: Color, cornerRadius: CGFloat = 10) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26, *) {
            glassEffect(.regular.tint(tint.opacity(0.28)), in: shape)
        } else {
            background(tint.opacity(0.15), in: shape)
        }
    }
}

/// Lets neighbouring glass tiles blend and share one sampling pass on macOS 26; a plain stack before.
struct GlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}
