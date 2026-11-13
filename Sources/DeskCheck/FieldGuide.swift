import SwiftUI

/// Every Settings field that is read off a tape measure. The label and the caption live here, once,
/// so the form, the drawing and the tooltips always use the same name.
enum GuideField: Hashable, CaseIterable {
    case distance, screenTop, lens, height, seatedEye, elbow, sitDesk, standDesk

    var label: String {
        switch self {
        case .distance: return "Eye to screen, seated"
        case .screenTop: return "Top of screen above desk"
        case .lens: return "Webcam lens above screen top"
        case .height: return "Your height"
        case .seatedEye: return "Seated eyes above desk"
        case .elbow: return "Eyes to elbow"
        case .sitDesk: return "Sit"
        case .standDesk: return "Stand"
        }
    }

    /// What to measure, from where to where. A laptop has no separate screen on a stand, so a few differ.
    func caption(laptop: Bool) -> String {
        switch self {
        case .distance:
            return "From the centre of your eye straight to the screen, sitting as you normally do."
        case .screenTop:
            return laptop
                ? "From the desk surface up to the top edge of the lit display, not the top of the lid."
                : "From the desk surface up to the top edge of the screen."
        case .lens:
            return "From the top edge of the screen up to the centre of the webcam lens. Usually about "
                + (laptop ? "0.5" : "1") + " cm, so a ruler is easier than a tape."
        case .height: return "Floor to the top of your head, standing straight."
        case .seatedEye: return "From the desk surface up to the centre of your eye, sitting as you normally do."
        case .elbow: return "From the centre of your eye straight down to your elbow, with the elbow bent at a right angle."
        case .sitDesk: return "Floor to the top of the desk, read from the tape on the desk leg with the desk at your sitting height."
        case .standDesk: return "Floor to the top of the desk, read from the tape on the desk leg with the desk at your standing height."
        }
    }

    /// The fields drawn on the standing figure; all others are drawn on the seated one.
    var isStanding: Bool { self == .height || self == .elbow || self == .standDesk }
}

/// One measuring line in the drawing: from one end to the other, with where its name is written.
private struct GuideLine {
    let field: GuideField
    let from: CGPoint
    let to: CGPoint
    let label: CGPoint
    let alignment: Alignment

    var hitBox: CGRect {
        CGRect(
            x: min(from.x, to.x) - 8, y: min(from.y, to.y) - 8,
            width: abs(from.x - to.x) + 16, height: abs(from.y - to.y) + 16)
    }
}

/// A side-view drawing above the tape measure fields. The field in focus or under the pointer lights its
/// line and caption; clicking a line asks for that field. Drawn with shapes, so it follows light and dark mode.
struct FieldGuideView: View {
    let active: GuideField?
    let laptop: Bool
    let select: (GuideField) -> Void
    let hover: (GuideField, Bool) -> Void

    private static let size = CGSize(width: 440, height: 190)

    var body: some View {
        let standing = active?.isStanding ?? false
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                scene(standing: standing)
                ForEach(lines(standing: standing), id: \.field) { line in
                    dimension(line)
                }
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
            Text(
                active.map { "\($0.label): \($0.caption(laptop: laptop))" }
                    ?? "Click a field or a line in the drawing to see what to measure."
            )
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
        }
    }

    // MARK: Drawing

    private func dimension(_ line: GuideLine) -> some View {
        let lit = line.field == active
        let colour: Color = lit ? .accentColor : Color.primary.opacity(0.35)
        return ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: line.from)
                p.addLine(to: line.to)
                for end in [line.from, line.to] {
                    // A short tick across each end, perpendicular to the line.
                    let vertical = line.from.x == line.to.x
                    p.move(to: CGPoint(x: end.x - (vertical ? 4 : 0), y: end.y - (vertical ? 0 : 4)))
                    p.addLine(to: CGPoint(x: end.x + (vertical ? 4 : 0), y: end.y + (vertical ? 0 : 4)))
                }
            }
            .stroke(colour, style: StrokeStyle(lineWidth: lit ? 2.5 : 1.5, lineCap: .round))
            if lit {
                Text(line.field.label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.accentColor)
                    .frame(width: 200, alignment: line.alignment)
                    .position(
                        x: line.label.x + (line.alignment == .trailing ? -100 : line.alignment == .leading ? 100 : 0),
                        y: line.label.y)
            }
            Color.clear
                .frame(width: line.hitBox.width, height: line.hitBox.height)
                .contentShape(Rectangle())
                .offset(x: line.hitBox.minX, y: line.hitBox.minY)
                .onTapGesture { select(line.field) }
                .onHover { hover(line.field, $0) }
                .help("\(line.field.label): \(line.field.caption(laptop: laptop))")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.field.label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { select(line.field) }
    }

    private func scene(standing: Bool) -> some View {
        let ink = Color.primary.opacity(0.6)
        let style = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
        return ZStack {
            Path { p in  // floor
                p.move(to: CGPoint(x: 10, y: 175))
                p.addLine(to: CGPoint(x: 430, y: 175))
            }.stroke(ink.opacity(0.5), style: style)
            if standing { standingScene(ink, style) } else { seatedScene(ink, style) }
        }
    }

    private func person(
        _ p: inout Path, head: CGPoint, hip: CGPoint, knee: CGPoint, foot: CGPoint, shoulder: CGPoint, elbow: CGPoint, hand: CGPoint
    ) {
        p.addEllipse(in: CGRect(x: head.x - 13, y: head.y - 13, width: 26, height: 26))
        p.move(to: CGPoint(x: head.x, y: head.y + 13))
        p.addLine(to: shoulder)
        p.addLine(to: hip)
        p.addLine(to: knee)
        p.addLine(to: foot)
        p.move(to: shoulder)
        p.addLine(to: elbow)
        p.addLine(to: hand)
    }

    private func seatedScene(_ ink: Color, _ style: StrokeStyle) -> some View {
        Path { p in
            // Chair.
            p.move(to: CGPoint(x: 20, y: 128))
            p.addLine(to: CGPoint(x: 76, y: 128))
            p.move(to: CGPoint(x: 48, y: 128))
            p.addLine(to: CGPoint(x: 48, y: 175))
            // Person: eye at (66, 53).
            person(
                &p, head: CGPoint(x: 58, y: 55), hip: CGPoint(x: 46, y: 126), knee: CGPoint(x: 104, y: 126),
                foot: CGPoint(x: 104, y: 175), shoulder: CGPoint(x: 52, y: 84), elbow: CGPoint(x: 62, y: 104),
                hand: CGPoint(x: 112, y: 108))
            // Desk, with its leg.
            p.move(to: CGPoint(x: 80, y: 110))
            p.addLine(to: CGPoint(x: 410, y: 110))
            p.move(to: CGPoint(x: 400, y: 110))
            p.addLine(to: CGPoint(x: 400, y: 175))
            if laptop {
                p.move(to: CGPoint(x: 200, y: 106))
                p.addLine(to: CGPoint(x: 262, y: 106))  // base
                p.move(to: CGPoint(x: 262, y: 106))
                p.addLine(to: CGPoint(x: 270, y: 46))  // lid, leaning back
                p.addEllipse(in: CGRect(x: 266, y: 46, width: 4, height: 4))  // built-in camera
            } else {
                p.move(to: CGPoint(x: 236, y: 110))
                p.addLine(to: CGPoint(x: 262, y: 110))  // stand foot
                p.move(to: CGPoint(x: 250, y: 110))
                p.addLine(to: CGPoint(x: 250, y: 90))
                p.addRoundedRect(in: CGRect(x: 244, y: 40, width: 6, height: 50), cornerSize: CGSize(width: 2, height: 2))
                p.addRoundedRect(in: CGRect(x: 238, y: 29, width: 12, height: 11), cornerSize: CGSize(width: 2, height: 2))  // webcam
                p.addEllipse(in: CGRect(x: 236, y: 32, width: 4, height: 4))  // its lens
            }
        }
        .stroke(ink, style: style)
    }

    private func standingScene(_ ink: Color, _ style: StrokeStyle) -> some View {
        Path { p in
            // Eye at (157, 36), elbow at (156, 80).
            person(
                &p, head: CGPoint(x: 150, y: 38), hip: CGPoint(x: 150, y: 102), knee: CGPoint(x: 152, y: 140),
                foot: CGPoint(x: 156, y: 175), shoulder: CGPoint(x: 150, y: 54), elbow: CGPoint(x: 156, y: 80),
                hand: CGPoint(x: 206, y: 84))
            p.move(to: CGPoint(x: 150, y: 102))
            p.addLine(to: CGPoint(x: 144, y: 140))
            p.addLine(to: CGPoint(x: 142, y: 175))
            // Standing desk, with its leg.
            p.move(to: CGPoint(x: 190, y: 86))
            p.addLine(to: CGPoint(x: 410, y: 86))
            p.move(to: CGPoint(x: 400, y: 86))
            p.addLine(to: CGPoint(x: 400, y: 175))
        }
        .stroke(ink, style: style)
    }

    private func lines(standing: Bool) -> [GuideLine] {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        if standing {
            return [
                GuideLine(field: .height, from: pt(100, 25), to: pt(100, 175), label: pt(94, 100), alignment: .trailing),
                GuideLine(field: .elbow, from: pt(190, 36), to: pt(190, 80), label: pt(198, 58), alignment: .leading),
                GuideLine(field: .standDesk, from: pt(424, 86), to: pt(424, 175), label: pt(418, 132), alignment: .trailing),
            ]
        }
        let screenX: CGFloat = laptop ? 292 : 270
        let top: CGFloat = laptop ? 54 : 40
        return [
            GuideLine(field: .distance, from: pt(72, 53), to: pt(laptop ? 258 : 240, 53), label: pt(160, 43), alignment: .center),
            GuideLine(field: .seatedEye, from: pt(84, 53), to: pt(84, 110), label: pt(92, 84), alignment: .leading),
            GuideLine(field: .screenTop, from: pt(screenX, top), to: pt(screenX, 110), label: pt(screenX + 8, 80), alignment: .leading),
            GuideLine(
                field: .lens, from: pt(laptop ? 250 : 222, top), to: pt(laptop ? 250 : 222, laptop ? 48 : 34),
                label: pt(laptop ? 244 : 216, laptop ? 36 : 22), alignment: .trailing),
            GuideLine(field: .sitDesk, from: pt(424, 110), to: pt(424, 175), label: pt(418, 150), alignment: .trailing),
        ]
    }
}
