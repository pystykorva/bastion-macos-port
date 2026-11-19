import SwiftUI
import TessuCore

/// The exposure radar as a flat 2D drawing: concentric rings (centre = the router, rim = the internet),
/// one beacon per scan check, and a sweep while a scan runs. It animates only while scanning; once the
/// scan is done the picture is static and costs nothing to keep on screen.
struct ExposureRadar: View {
    var beacons: [RadarBeacon]
    var scanning: Bool
    @Binding var highlight: String?
    var onSelect: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var hover: String?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !scanning || reduceMotion)) { timeline in
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    Canvas { ctx, sz in
                        let style = RadarStyle(ink: scheme == .dark ? .white : .black, reduceMotion: reduceMotion)
                        RadarDrawing.draw(&ctx, sz, beacons: beacons, scanning: scanning,
                                          emphasised: Set([highlight, hover].compactMap { $0 }),
                                          time: timeline.date.timeIntervalSinceReferenceDate, style: style)
                    }
                    RadarLabels(beacons: beacons, size: size, shown: Set([highlight, hover].compactMap { $0 }))
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p): hover = RadarModel.nearest(to: p, in: size, beacons: beacons)?.id
                    case .ended: hover = nil
                    }
                }
                .onTapGesture(coordinateSpace: .local) { p in
                    if let b = RadarModel.nearest(to: p, in: size, beacons: beacons) { onSelect(b.id) }
                }
            }
        }
        .aspectRatio(1.08, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RadarModel.summary(beacons))
    }
}

struct RadarStyle {
    var ink: Color
    var reduceMotion: Bool
}

/// Labels are real SwiftUI text (crisp at any scale). An open finding and a running check are always
/// labelled; the rest show on hover or when highlighted from the list, so the disc stays quiet.
struct RadarLabels: View {
    var beacons: [RadarBeacon]
    var size: CGSize
    var shown: Set<String>

    var body: some View {
        ZStack {
            ForEach(beacons) { b in
                if b.status == .risk || b.checking || shown.contains(b.id) {
                    let p = RadarModel.point(b, in: size)
                    let goesRight = cos(b.angle) >= -0.05
                    Text(b.short)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.color(b.status).opacity(0.5)))
                        .fixedSize()
                        // Anchored by its near edge, so the pill grows away from the beacon.
                        .position(x: p.x, y: p.y - 18)
                        .alignmentGuide(.leading) { $0[.leading] }
                        .offset(x: goesRight ? CGFloat(b.short.count) * 3.2 + 10 : -(CGFloat(b.short.count) * 3.2 + 10))
                }
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.15), value: shown)
    }
}
