import SwiftUI
import TessuCore

enum RadarDrawing {
    static func draw(_ ctx: inout GraphicsContext, _ size: CGSize, beacons: [RadarBeacon], scanning: Bool,
                     emphasised: Set<String>, time: TimeInterval, style: RadarStyle) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let R = min(size.width, size.height) / 2 * 0.92
        drawDisc(&ctx, c, R, style)
        if scanning { drawSweep(&ctx, c, R, time: time, style: style) }
        drawRouter(&ctx, c, R)
        for b in beacons.sorted(by: { $0.radius < $1.radius }) {
            drawBeacon(&ctx, b, center: c, size: size, emphasised: emphasised.contains(b.id), time: time, style: style)
        }
    }

    /// Rings from sealed (inner) to exposed (outer) and one faint spoke per category slot.
    private static func drawDisc(_ ctx: inout GraphicsContext, _ c: CGPoint, _ R: CGFloat, _ style: RadarStyle) {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2)), with: .radialGradient(
            Gradient(colors: [Theme.accent.opacity(0.16), Theme.accent.opacity(0.03)]), center: c, startRadius: 0, endRadius: R))
        for f in [0.37, 0.52, 0.67, 0.84, 1.0] as [CGFloat] {
            let ring = Path(ellipseIn: CGRect(x: c.x - R * f, y: c.y - R * f, width: R * f * 2, height: R * f * 2))
            ctx.stroke(ring, with: .color(style.ink.opacity(f == 1 ? 0.30 : 0.10)),
                       style: StrokeStyle(lineWidth: f == 1 ? 1.5 : 1, dash: f == 1 ? [] : [2, 4]))
        }
        for i in 0..<RadarModel.order.count {
            let a = (-90 + Double(i) / Double(RadarModel.order.count) * 360 + 8) * .pi / 180
            var spoke = Path(); spoke.move(to: c)
            spoke.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * R, y: c.y + CGFloat(sin(a)) * R))
            ctx.stroke(spoke, with: .color(style.ink.opacity(0.05)), lineWidth: 1)
        }
    }

    private static func drawSweep(_ ctx: inout GraphicsContext, _ c: CGPoint, _ R: CGFloat, time: TimeInterval, style: RadarStyle) {
        let a = style.reduceMotion ? -52 * Double.pi / 180 : (time.truncatingRemainder(dividingBy: 2.6) / 2.6) * 2 * .pi
        var wedge = Path(); wedge.move(to: c)
        wedge.addArc(center: c, radius: R, startAngle: .radians(a - 0.55), endAngle: .radians(a), clockwise: false)
        wedge.closeSubpath()
        ctx.fill(wedge, with: .color(Theme.accent.opacity(0.22)))
        var edge = Path(); edge.move(to: c)
        edge.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * R, y: c.y + CGFloat(sin(a)) * R))
        ctx.stroke(edge, with: .color(Theme.lavender.opacity(0.8)), lineWidth: 1.5)
    }

    private static func drawRouter(_ ctx: inout GraphicsContext, _ c: CGPoint, _ R: CGFloat) {
        let core = CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18)
        ctx.fill(Path(ellipseIn: core.insetBy(dx: -8, dy: -8)), with: .color(Theme.accent.opacity(0.18)))
        ctx.fill(Path(ellipseIn: core), with: .color(Theme.lavender))
        ctx.draw(Text("router").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: c.x, y: c.y + 26))
        ctx.draw(Text("internet").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: c.x, y: c.y - R - 4), anchor: .bottom)
    }

    private static func drawBeacon(_ ctx: inout GraphicsContext, _ b: RadarBeacon, center c: CGPoint, size: CGSize,
                                   emphasised: Bool, time: TimeInterval, style: RadarStyle) {
        let p = RadarModel.point(b, in: size)
        let col = b.checking ? Theme.lavender : Theme.color(b.status)
        var leader = Path(); leader.move(to: c); leader.addLine(to: p)
        ctx.stroke(leader, with: .color(col.opacity(0.22)), lineWidth: 1)
        if b.status == .risk && !b.checking && !style.reduceMotion {
            let t = time.truncatingRemainder(dividingBy: 2.0) / 2.0
            let r = 10 + CGFloat(t) * 16
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                       with: .color(col.opacity(0.5 * (1 - t))), lineWidth: 1.5)
        }
        let r: CGFloat = emphasised ? 9 : 7
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r - 4, y: p.y - r - 4, width: (r + 4) * 2, height: (r + 4) * 2)),
                 with: .color(col.opacity(emphasised ? 0.35 : 0.18)))
        marker(&ctx, at: p, radius: r, status: b.status, checking: b.checking, color: col)
    }

    /// The shape carries the status as well as the colour, so it reads without colour vision:
    /// open = diamond, review = thick ring, sealed = filled dot, unknown = dashed ring.
    private static func marker(_ ctx: inout GraphicsContext, at p: CGPoint, radius r: CGFloat, status: CheckStatus, checking: Bool, color: Color) {
        let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        if checking {
            ctx.stroke(Path(ellipseIn: rect), with: .color(color), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
            return
        }
        switch status {
        case .risk:
            var d = Path()
            d.move(to: CGPoint(x: p.x, y: p.y - r - 1)); d.addLine(to: CGPoint(x: p.x + r + 1, y: p.y))
            d.addLine(to: CGPoint(x: p.x, y: p.y + r + 1)); d.addLine(to: CGPoint(x: p.x - r - 1, y: p.y)); d.closeSubpath()
            ctx.fill(d, with: .color(color))
        case .warn: ctx.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 3)
        case .ok: ctx.fill(Path(ellipseIn: rect.insetBy(dx: 1, dy: 1)), with: .color(color))
        case .unknown: ctx.stroke(Path(ellipseIn: rect.insetBy(dx: 1, dy: 1)), with: .color(color), style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
        }
    }
}
