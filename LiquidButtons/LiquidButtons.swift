//
//  LiquidMetalButtons.swift
//  Requires iOS 17 / macOS 14 (SwiftUI Metal shaders) and LiquidMetal.metal in the same target.
//
//  Interactive version:
//   • Tap any of the four nav buttons – the liquid-metal ring springs to it.
//   • Tap the sun / moon toggle – the whole UI crossfades between dark and light.
//   • Everything fits on screen: the 1000×300 design canvas is scaled to the container.
//   • The ring's liquid flow is the only thing that animates on its own.
//

import SwiftUI

// MARK: - Palette (dark ⇄ light crossfade)

private struct Palette {
    let p: Double   // 0 dark … 1 light

    func c(_ dark: UInt32, _ light: UInt32, opacity: Double = 1) -> Color {
        func comps(_ h: UInt32) -> (Double, Double, Double) {
            (Double((h >> 16) & 0xFF) / 255, Double((h >> 8) & 0xFF) / 255, Double(h & 0xFF) / 255)
        }
        let a = comps(dark), b = comps(light)
        return Color(red: a.0 + (b.0 - a.0) * p,
                     green: a.1 + (b.1 - a.1) * p,
                     blue: a.2 + (b.2 - a.2) * p,
                     opacity: opacity)
    }

    func v(_ dark: Double, _ light: Double) -> Double { dark + (light - dark) * p }
}

// MARK: - Icons (stroked paths, centred on origin, units = points)

private enum Icon {
    static func grid() -> Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: -24, y: -24,   width: 19.5, height: 24),   cornerSize: CGSize(width: 4, height: 4))
        p.addRoundedRect(in: CGRect(x: 4,   y: -23.5, width: 19,   height: 12.5), cornerSize: CGSize(width: 3, height: 3))
        p.addRoundedRect(in: CGRect(x: -24, y: 8.5,   width: 19.5, height: 13),   cornerSize: CGSize(width: 3, height: 3))
        p.addRoundedRect(in: CGRect(x: 4,   y: -2,    width: 19,   height: 24.5), cornerSize: CGSize(width: 4, height: 4))
        return p
    }

    static func chart() -> Path {
        var p = Path()
        p.move(to: CGPoint(x: -18.75, y: 10));  p.addLine(to: CGPoint(x: -18.75, y: 24))
        p.move(to: CGPoint(x: 0.25,   y: -23)); p.addLine(to: CGPoint(x: 0.25,   y: 24))
        p.move(to: CGPoint(x: 18.75,  y: -6));  p.addLine(to: CGPoint(x: 18.75,  y: 24))
        return p
    }

    static func layers() -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -28.5))
        p.addLine(to: CGPoint(x: 28, y: -15))
        p.addLine(to: CGPoint(x: 0, y: -1.5))
        p.addLine(to: CGPoint(x: -28, y: -15))
        p.closeSubpath()
        p.move(to: CGPoint(x: -28, y: 1.5)); p.addLine(to: CGPoint(x: 0, y: 15));   p.addLine(to: CGPoint(x: 28, y: 1.5))
        p.move(to: CGPoint(x: -28, y: 15));  p.addLine(to: CGPoint(x: 0, y: 28.5)); p.addLine(to: CGPoint(x: 28, y: 15))
        return p
    }

    static func wallet() -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 20, y: -14.5))
        p.addLine(to: CGPoint(x: 20, y: -21.7))
        p.addQuadCurve(to: CGPoint(x: 16, y: -25.7), control: CGPoint(x: 20, y: -25.7))
        p.addLine(to: CGPoint(x: -21.8, y: -25.7))
        p.addQuadCurve(to: CGPoint(x: -25.8, y: -21.7), control: CGPoint(x: -25.8, y: -25.7))
        p.addLine(to: CGPoint(x: -25.8, y: 21.7))
        p.addQuadCurve(to: CGPoint(x: -21.8, y: 25.7), control: CGPoint(x: -25.8, y: 25.7))
        p.addLine(to: CGPoint(x: 21.8, y: 25.7))
        p.addQuadCurve(to: CGPoint(x: 25.8, y: 21.7), control: CGPoint(x: 25.8, y: 25.7))
        p.addLine(to: CGPoint(x: 25.8, y: -10.5))
        p.addQuadCurve(to: CGPoint(x: 21.8, y: -14.5), control: CGPoint(x: 25.8, y: -14.5))
        p.addLine(to: CGPoint(x: -24, y: -14.5))
        p.addRoundedRect(in: CGRect(x: 9.2, y: -1.5, width: 19, height: 12.5), cornerSize: CGSize(width: 6.2, height: 6.2))
        return p
    }

    static func sun() -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: -17.3, y: -17.3, width: 34.6, height: 34.6))
        for i in 0..<8 {
            let a = Double(i) * .pi / 4
            let (s, c) = (CGFloat(sin(a)), CGFloat(cos(a)))
            p.move(to: CGPoint(x: s * 28.2, y: -c * 28.2))
            p.addLine(to: CGPoint(x: s * 29.8, y: -c * 29.8))
        }
        return p
    }

    static func moon() -> Path {
        let outer = Path(ellipseIn: CGRect(x: -29, y: 6.5 - 29, width: 58, height: 58))
        let inner = Path(ellipseIn: CGRect(x: 12 - 24, y: 6.5 - 12 - 24, width: 48, height: 48))
        var p = outer.subtracting(inner)
        func plus(_ c: CGPoint, _ r: CGFloat) {
            p.move(to: CGPoint(x: c.x - r, y: c.y)); p.addLine(to: CGPoint(x: c.x + r, y: c.y))
            p.move(to: CGPoint(x: c.x, y: c.y - r)); p.addLine(to: CGPoint(x: c.x, y: c.y + r))
        }
        plus(CGPoint(x: 11.5, y: -20.5), 4.5)
        plus(CGPoint(x: 26.5, y: -3.5), 6)
        return p
    }
}

private struct StrokeIcon: View {
    let path: Path
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let moved = path.applying(CGAffineTransform(translationX: size.width / 2, y: size.height / 2))
            ctx.stroke(moved, with: .color(color),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 120, height: 120)
    }
}

// MARK: - Liquid metal ring

private struct LiquidMetalRing: View {
    let time: Double
    let light: Double
    var size: CGFloat = 162.5
    var radius: CGFloat = 44
    var width: CGFloat = 10

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .circular)
            .strokeBorder(Color.white, lineWidth: width)
            .frame(width: size, height: size)
            .colorEffect(
                ShaderLibrary.liquidMetalRing(
                    .float2(CGSize(width: size, height: size)),
                    .float(time),
                    .float(light),
                    .float(radius),
                    .float(width)
                )
            )
    }
}

// MARK: - Animatable scene
//
// `light` (0…1) and `selection` (0…3, fractional while the ring travels) are animatable,
// so any `withAnimation` on the state that feeds them is interpolated every frame.

private struct ButtonsScene: View, Animatable {
    var light: Double
    var selection: Double
    var clock: Double          // shader time, not animated

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(light, selection) }
        set { light = newValue.first; selection = newValue.second }
    }

    // Canvas 1000 × 300 (all measured from the recording, px / 2).
    static let canvas = CGSize(width: 1000, height: 300)
    static let cellCenters: [CGFloat] = [141.25, 320, 507.5, 695]
    private let midY: CGFloat = 150
    private let toggleX: CGFloat = 874.5

    private func tileX() -> CGFloat {
        let s = min(max(selection, 0), 3)
        let i = Int(s.rounded(.down)), f = CGFloat(s - Double(i))
        let a = Self.cellCenters[i]
        let b = Self.cellCenters[min(i + 1, 3)]
        return a + (b - a) * f
    }

    private func weight(_ i: Int) -> Double { max(0, 1 - abs(selection - Double(i))) }

    var body: some View {
        let pal = Palette(p: light)
        let tx = tileX()
        let idle = pal.c(0xA8A8A8, 0x999999)
        let active = pal.c(0xFFFFFF, 0x111111)

        ZStack(alignment: .topLeading) {
            // Recessed outer track (holds the toggle on its right end)
            RoundedRectangle(cornerRadius: 77, style: .continuous)
                .fill(pal.c(0x131313, 0xE3E3E3))
                .overlay(
                    RoundedRectangle(cornerRadius: 77, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [pal.c(0x000000, 0x000000, opacity: pal.v(0.75, 0.10)),
                                         .clear,
                                         pal.c(0xFFFFFF, 0xFFFFFF, opacity: pal.v(0.10, 0.90))],
                                startPoint: .top, endPoint: .bottom),
                            lineWidth: 3)
                )
                .frame(width: 940, height: 222)
                .offset(x: 30, y: 39)

            // Raised inner bar
            RoundedRectangle(cornerRadius: 70, style: .continuous)
                .fill(LinearGradient(colors: [pal.c(0x232323, 0xFFFFFF), pal.c(0x141414, 0xF1F1F1)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 70, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [pal.c(0xFFFFFF, 0xFFFFFF, opacity: pal.v(0.22, 0.0)),
                                         .clear,
                                         pal.c(0x000000, 0x000000, opacity: pal.v(0.50, 0.14))],
                                startPoint: .top, endPoint: .bottom),
                            lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(pal.v(0.55, 0.16)), radius: 5, x: 0, y: 3)
                .frame(width: 749.5, height: 208)
                .offset(x: 37, y: 46)

            // Dividers – fade out next to the selected tile
            ForEach(0..<3, id: \.self) { i in
                let x = (Self.cellCenters[i] + Self.cellCenters[i + 1]) / 2
                let hide = max(weight(i), weight(i + 1))
                Rectangle()
                    .fill(pal.c(0x0A0A0A, 0xE2E2E2))
                    .frame(width: 1, height: 130)
                    .opacity(1 - hide)
                    .position(x: x, y: midY + 2)
            }

            // Selected tile: recess → liquid metal ring → groove → face
            RoundedRectangle(cornerRadius: 50, style: .circular)
                .fill(pal.c(0x181818, 0xDEDEDE))
                .overlay(
                    RoundedRectangle(cornerRadius: 50, style: .circular)
                        .strokeBorder(pal.c(0xFFFFFF, 0xFFFFFF, opacity: pal.v(0.16, 0.9)), lineWidth: 1)
                )
                .frame(width: 176.5, height: 176.5)
                .position(x: tx, y: midY)

            LiquidMetalRing(time: clock, light: light)
                .position(x: tx, y: midY)

            RoundedRectangle(cornerRadius: 34, style: .circular)
                .fill(pal.c(0x0E0E0E, 0xD4D4D4))
                .frame(width: 142.5, height: 142.5)
                .position(x: tx, y: midY)

            RoundedRectangle(cornerRadius: 31, style: .circular)
                .fill(LinearGradient(colors: [pal.c(0x1B1B1B, 0xFFFFFF), pal.c(0x242424, 0xF6F6F6)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 31, style: .circular)
                        .strokeBorder(pal.c(0x000000, 0xFFFFFF, opacity: 0.45), lineWidth: 1.5)
                )
                .frame(width: 133.5, height: 133.5)
                .position(x: tx, y: midY)

            // Nav icons: idle copy + active copy crossfaded by distance to the tile
            navIcon(Icon.grid(),   index: 0, idle: idle, active: active, lineWidth: 3.5)
            navIcon(Icon.chart(),  index: 1, idle: idle, active: active, lineWidth: 4)
            navIcon(Icon.layers(), index: 2, idle: idle, active: active, lineWidth: 3.6)
            navIcon(Icon.wallet(), index: 3, idle: idle, active: active, lineWidth: 3.6)

            // Theme toggle: sun ⇄ moon
            StrokeIcon(path: Icon.sun(), color: pal.c(0xFFFFFF, 0xFFFFFF), lineWidth: 6)
                .opacity(1 - light)
                .position(x: toggleX - 3, y: midY + 2)
            StrokeIcon(path: Icon.moon(), color: pal.c(0x000000, 0x000000), lineWidth: 5)
                .opacity(light)
                .position(x: toggleX - 3, y: midY + 2)
        }
        .frame(width: Self.canvas.width, height: Self.canvas.height, alignment: .topLeading)
    }

    private func navIcon(_ path: Path, index: Int, idle: Color, active: Color, lineWidth: CGFloat) -> some View {
        ZStack {
            StrokeIcon(path: path, color: idle, lineWidth: lineWidth)
                .opacity(1 - weight(index))
            StrokeIcon(path: path, color: active, lineWidth: lineWidth)
                .opacity(weight(index))
        }
        .position(x: Self.cellCenters[index], y: midY + 2)
    }
}

// MARK: - Public view

struct LiquidMetalButtonsDemo: View {
    @State private var selected = 0
    @State private var isLight = false
    private let start = Date()

    var body: some View {
        let pal = Palette(p: isLight ? 1 : 0)   // only used for the (non-animated) page fallback

        TimelineView(.animation) { timeline in
            let clock = timeline.date.timeIntervalSince(start)

            GeometryReader { geo in
                let size = ButtonsScene.canvas
                let s = min(geo.size.width / size.width, geo.size.height / size.height)

                ZStack {
                    PageBackground(light: isLight ? 1 : 0)
                        .ignoresSafeArea()

                    ZStack(alignment: .topLeading) {
                        ButtonsScene(light: isLight ? 1 : 0,
                                     selection: Double(selected),
                                     clock: clock)

                        // Hit targets (transparent)
                        ForEach(0..<4, id: \.self) { i in
                            Color.clear
                                .contentShape(Rectangle())
                                .frame(width: 187, height: 208)
                                .position(x: ButtonsScene.cellCenters[i], y: 150)
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
                                        selected = i
                                    }
                                }
                                .accessibilityLabel(["Dashboard", "Analytics", "Layers", "Wallet"][i])
                                .accessibilityAddTraits(.isButton)
                        }

                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: 170, height: 208)
                            .position(x: 874.5, y: 150)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.45)) { isLight.toggle() }
                            }
                            .accessibilityLabel(isLight ? "Switch to dark mode" : "Switch to light mode")
                            .accessibilityAddTraits(.isButton)
                    }
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(s)
                    .frame(width: size.width * s, height: size.height * s)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .preferredColorScheme(isLight ? .light : .dark)
        .background(pal.c(0x121212, 0xE7E7E7))
    }
}

/// Animatable page background so it crossfades together with the scene.
private struct PageBackground: View, Animatable {
    var light: Double
    var animatableData: Double {
        get { light }
        set { light = newValue }
    }

    var body: some View {
        let pal = Palette(p: light)
        LinearGradient(colors: [pal.c(0x1E1E1E, 0xF0F0F0), pal.c(0x121212, 0xE7E7E7)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

#Preview("Liquid metal buttons", traits: .fixedLayout(width: 800, height: 260)) {
    LiquidMetalButtonsDemo()
}
