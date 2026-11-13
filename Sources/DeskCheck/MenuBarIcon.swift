import AppKit

/// The menu bar icon: a desk with a double arrow above it, drawn as a template image on an
/// 18 x 18 grid (y down) so macOS tints it for light, dark and highlighted menu bars.
enum MenuBarIcon {
    static let deskTopWidth = 1.7
    static let legWidth = 1.5
    static let arrowWidth = 1.1

    static func image(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let scale = rect.width / 18
            NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
            NSColor.black.setStroke()

            func stroke(_ width: Double, _ build: (NSBezierPath) -> Void) {
                let path = NSBezierPath()
                build(path)
                path.lineWidth = width
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }
            // Desk: top, then two legs.
            stroke(deskTopWidth) {
                $0.move(to: NSPoint(x: 2.5, y: 12.5))
                $0.line(to: NSPoint(x: 15.5, y: 12.5))
            }
            stroke(legWidth) {
                $0.move(to: NSPoint(x: 4.2, y: 12.5))
                $0.line(to: NSPoint(x: 4.2, y: 16.5))
                $0.move(to: NSPoint(x: 13.8, y: 12.5))
                $0.line(to: NSPoint(x: 13.8, y: 16.5))
            }
            // Arrow: M9 2 V8.4 M6.6 4.2 L9 1.8 L11.4 4.2 M6.6 6.2 L9 8.6 L11.4 6.2
            stroke(arrowWidth) {
                $0.move(to: NSPoint(x: 9, y: 2))
                $0.line(to: NSPoint(x: 9, y: 8.4))
                $0.move(to: NSPoint(x: 6.6, y: 4.2))
                $0.line(to: NSPoint(x: 9, y: 1.8))
                $0.line(to: NSPoint(x: 11.4, y: 4.2))
                $0.move(to: NSPoint(x: 6.6, y: 6.2))
                $0.line(to: NSPoint(x: 9, y: 8.6))
                $0.line(to: NSPoint(x: 11.4, y: 6.2))
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
