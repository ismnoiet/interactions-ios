//
//  AndroidStyleNotificationIconTray.swift
//
//  Created by ismnoiet
//
//  Android-style notification shade with an icon tray pinned at the bottom. As
//  notifications scroll under the tray they collapse into small icons that slide in
//  from the left and join the group. Everything in the tray is a continuous function
//  of scroll position, so it follows your drag exactly: fast drag = fast, slow drag =
//  slow, and it plays backwards when you drag the other way.
//
//  All apps, names and messages are fictional. Icons are SF Symbols. iOS 17+.
//

import SwiftUI

// MARK: - Metrics

private let pxPerPt: CGFloat = 1.63
/// Converts layout pixels to points.
private func p(_ px: CGFloat) -> CGFloat { px / pxPerPt }

private enum Metrics {
    static let width: CGFloat = p(670)
    static let height: CGFloat = p(1404)
    static let inset: CGFloat = p(22)             // card left/right margin
    static let cardGap: CGFloat = p(5)

    static let trayInset: CGFloat = inset          // same side margin as the cards
    static let trayTop: CGFloat = p(1292)          // leaves ≈ 40px (≈ 25pt) below the tray
    static let trayHeight: CGFloat = p(70)
    static let trayIconPad: CGFloat = p(34)       // centre of the first icon, from the tray's left edge
    static let trayPitch: CGFloat = p(33)         // distance between icons
    static let trayGlyph: CGFloat = p(26)
}

private enum Motion {
    /// Notifications further under the tray than this fraction start turning into icons…
    static let hiddenStart: CGFloat = 0.25
    /// …and are fully an icon at this fraction.
    static let hiddenEnd: CGFloat = 0.90

    /// Smoothstep progress of `x` through `from...to`.
    static func ramp(_ x: CGFloat, _ from: CGFloat, _ to: CGFloat) -> CGFloat {
        let f = min(max((x - from) / (to - from), 0), 1)
        return f * f * (3 - 2 * f)
    }

    /// Icon opacity: starts a little after the slide begins, done before it ends.
    static func fade(_ progress: CGFloat) -> CGFloat {
        let f = min(max((progress - 0.15) / 0.65, 0), 1)
        return f * f * (3 - 2 * f)
    }
}

// MARK: - Colours

private extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

private enum Palette {
    static let card = Color(hex: 0x141820)
    static let tray = Color(hex: 0x141820)
    static let chip = Color(hex: 0x262A33)
    static let primary = Color(hex: 0xE6E8EE)
    static let secondary = Color(hex: 0xA9ADB5)
    static let lavender = Color(hex: 0xAFBDE6)
    static let lavenderInk = Color(hex: 0x191D25)
    static let trayIcon = Color(hex: 0xDEDFE8)
    static let backgroundTop = Color(hex: 0x1C212C)
    static let backgroundBottom = Color(hex: 0x182030)
}

// MARK: - Fake notification data

private struct IconStyle {
    var symbol: String
    var background: Color
    var foreground: Color = .white
}

private enum Icons {
    static let voyago    = IconStyle(symbol: "airplane", background: Color(hex: 0x1B7FD6))
    static let chatly    = IconStyle(symbol: "message.fill", background: Color(hex: 0x1FA463))
    static let brewline  = IconStyle(symbol: "cup.and.saucer.fill", background: Color(hex: 0x6E0F35))
    static let agendo    = IconStyle(symbol: "calendar", background: Color(hex: 0xE8583C))
    static let pacely    = IconStyle(symbol: "figure.run", background: Color(hex: 0x1D5238), foreground: Color(hex: 0xF2E8D0))
    static let paywell   = IconStyle(symbol: "creditcard.fill", background: Color(hex: 0x2E6BEF))
    static let streamr   = IconStyle(symbol: "play.rectangle.fill", background: Color(hex: 0x5B2EA6))
    static let shelfie   = IconStyle(symbol: "books.vertical.fill", background: Color(hex: 0x0E4A52))
    static let skycast   = IconStyle(symbol: "cloud.rain.fill", background: Color(hex: 0x2D8CF0))
    static let gatherly  = IconStyle(symbol: "person.3.fill", background: Color(hex: 0xE0356B))
    static let northbank = IconStyle(symbol: "building.columns.fill", background: Color(hex: 0x0B1B2E), foreground: Color(hex: 0x6FD3A0))
    static let telio     = IconStyle(symbol: "antenna.radiowaves.left.and.right", background: Color(hex: 0x3B1E8F))
    static let snapshots = IconStyle(symbol: "camera.macro", background: Color(hex: 0xF29B1D))
}

private struct Line {
    var bold: String
    var rest: String = ""
}

private enum Position { case first, middle, last, alone }

private struct Note: Identifiable {
    let id: String
    var icon: IconStyle
    var position: Position = .middle
    var height: CGFloat = 148            // px
    var header: String? = nil            // small "App • time" row above the lines
    var title: String? = nil             // bold title followed by " • time" (single-row style)
    var time: String
    var ticking = false                  // time flips from 47m to 48m while scrolling
    var lines: [Line] = []
    var count: Int? = nil
    var chevronUp = false
    var thumbnail = false
}

private extension Note {
    /// Large radii where a card ends a group, small radii between stacked cards.
    var cornerRadii: RectangleCornerRadii {
        let big = p(36), small = p(5)
        switch position {
        case .first:  return .init(topLeading: big, bottomLeading: small, bottomTrailing: small, topTrailing: big)
        case .middle: return .init(topLeading: small, bottomLeading: small, bottomTrailing: small, topTrailing: small)
        case .last:   return .init(topLeading: small, bottomLeading: big, bottomTrailing: big, topTrailing: small)
        case .alone:  return .init(topLeading: big, bottomLeading: big, bottomTrailing: big, topTrailing: big)
        }
    }
}

private enum Shade {
    /// Alerting notifications, top to bottom.
    static let notes: [Note] = [
        Note(id: "voyago", icon: Icons.voyago, header: "Voyago", time: "47m", ticking: true,
             lines: [Line(bold: "Lisbon itinerary: Old Town Walks"),
                     Line(bold: "Lisbon itinerary: Sunset Tram Ride", rest: " The…")],
             count: 7),
        Note(id: "chatly", icon: Icons.chatly, header: "Chatly", time: "1h",
             lines: [Line(bold: "Maya", rest: " Hey, are we still on for tonight?"),
                     Line(bold: "Leo", rest: " Sent a photo")],
             count: 5),
        Note(id: "brewline", icon: Icons.brewline, height: 107, title: "Your latte, faster! ☕", time: "4h",
             lines: [Line(bold: "", rest: "Order ahead and skip the queue at your nearest c…")]),
        Note(id: "agendo", icon: Icons.agendo, header: "Agendo", time: "4h",
             lines: [Line(bold: "Design review", rest: " starts in 15 min"),
                     Line(bold: "Team lunch", rest: " moved to 1:30 PM")],
             count: 2),
        Note(id: "pacely", icon: Icons.pacely, height: 150, header: "Pacely", time: "11h",
             lines: [Line(bold: "Pacely", rest: " Ready for a 5K under 30 min?"),
                     Line(bold: "Pacely", rest: " Your weekly streak is at risk…")],
             count: 3),
        Note(id: "paywell", icon: Icons.paywell, header: "Paywell", time: "12h",
             lines: [Line(bold: "CAFE NORTE", rest: " $4.50 with VISA ending 4242"),
                     Line(bold: "METRO TAP CITY", rest: " $2.75 with V…")],
             count: 4),
        Note(id: "streamr", icon: Icons.streamr, height: 106, title: "New episode of Night Shift", time: "12h",
             lines: [Line(bold: "", rest: "Season 2 · Episode 4 is ready to watch now…")]),
        Note(id: "shelfie", icon: Icons.shelfie, height: 149, header: "Shelfie", time: "14h",
             lines: [Line(bold: "6 articles waiting", rest: " About 73 min of reading. Qu…"),
                     Line(bold: "Time to read this again", rest: " 40 pieces of advice fr…")],
             count: 4),
        Note(id: "skycast", icon: Icons.skycast, height: 106, title: "Rain expected after 6 PM", time: "14h",
             lines: [Line(bold: "", rest: "Light showers, 19° – bring an umbrella if you’re…")]),
        Note(id: "gatherly", icon: Icons.gatherly, header: "Gatherly", time: "15h",
             lines: [Line(bold: "Sam Rivera", rest: " Hello everyone,  We’re st…"),
                     Line(bold: "📣 Just scheduled: Sunday Football 5v5 <b>…")],
             count: 3),
        Note(id: "northbank", icon: Icons.northbank, height: 105, title: "Payment authorization", time: "18h",
             lines: [Line(bold: "", rest: "An online payment has been initiated with your…")]),
        Note(id: "telio", icon: Icons.telio, height: 151, header: "Telio", time: "18h",
             lines: [Line(bold: "Weekend Plans with Harbor Grill?", rest: " Plan y…"),
                     Line(bold: "Unlock FREE data today.", rest: " Open App Exclusive…")],
             count: 2),
        Note(id: "snapshots", icon: Icons.snapshots, height: 106, title: "Wait, look", time: "4d",
             thumbnail: true)
    ]

    // MARK: Layout (px from the top of the scrolling content)

    static let cardGapPx: CGFloat = 5
    static let quickSettingsHeight: CGFloat = 106
    static let quickSettingsGap: CGFloat = 42
    static let anchorBottom: CGFloat = 1268              // content bottom at scroll 0 (clear of the tray zone)
    static let viewportTop: CGFloat = 22                 // content top at max scroll
    static let clipLine: CGFloat = 1276                  // list is clipped here once the tray shows

    /// Top of each note and the total content height.
    static let layout: (tops: [CGFloat], contentHeight: CGFloat) = {
        var y = quickSettingsHeight + quickSettingsGap
        var tops: [CGFloat] = []
        for (i, n) in notes.enumerated() {
            tops.append(y)
            y += n.height + (i < notes.count - 1 ? cardGapPx : 0)
        }
        return (tops, y)
    }()

    /// How far the list can travel, px.
    static var maxScrollPx: CGFloat { layout.contentHeight - (anchorBottom - viewportTop) }

    /// Tray glyphs left → right, one per notification (list order).
    static var traySymbols: [String] { notes.map { $0.icon.symbol } }
}

// MARK: - App icon

private struct AppIcon: View {
    let style: IconStyle
    var size: CGFloat = p(56)

    var body: some View {
        ZStack {
            Circle().fill(style.background)
            Image(systemName: style.symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundColor(style.foreground)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Notification card

private struct NotificationCard: View {
    let note: Note

    private var rowPitch: CGFloat { note.header != nil ? p(41) : p(29) }
    private var rowCount: Int {
        (note.header != nil || note.title != nil ? 1 : 0) + note.lines.count
    }

    var body: some View {
        HStack(spacing: 0) {
            AppIcon(style: note.icon)
                .padding(.leading, p(24))
            VStack(alignment: .leading, spacing: 0) {
                if let header = note.header {
                    (Text(header) + Text(" • \(note.time)"))
                        .font(.system(size: 12.5))
                        .foregroundColor(Palette.secondary)
                        .frame(height: rowPitch, alignment: .center)
                } else if let title = note.title {
                    (Text(title).fontWeight(.semibold).foregroundColor(Palette.primary)
                     + Text(" • \(note.time)").font(.system(size: 12.5)).foregroundColor(Palette.secondary))
                        .font(.system(size: 14.5))
                        .lineLimit(1)
                        .frame(height: rowPitch, alignment: .center)
                }
                ForEach(Array(note.lines.enumerated()), id: \.offset) { _, line in
                    (Text(line.bold).fontWeight(.semibold).foregroundColor(Palette.primary)
                     + Text(line.rest).foregroundColor(Palette.secondary))
                        .font(.system(size: 14))
                        .lineLimit(1)
                        .frame(height: rowPitch, alignment: .center)
                }
            }
            .padding(.leading, p(27))
            Spacer(minLength: 0)
        }
        .frame(width: Metrics.width - Metrics.inset * 2, height: p(note.height), alignment: .leading)
        .overlay(alignment: .topTrailing) { trailing }
    }

    /// Chevron chip (with optional count) and the optional thumbnail.
    @ViewBuilder private var trailing: some View {
        let firstRowCentre = (p(note.height) - rowPitch * CGFloat(rowCount)) / 2 + rowPitch / 2
        HStack(spacing: p(16)) {
            if note.thumbnail {
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: 0x8DB6E8), Color(hex: 0xC9A27A)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: p(70), height: p(70))
            }
            chip
        }
        .frame(height: p(38))
        .padding(.trailing, p(22))
        .padding(.top, note.thumbnail ? (p(note.height) - p(38)) / 2 : firstRowCentre - p(19))
    }

    private var chip: some View {
        HStack(spacing: p(3)) {
            if let count = note.count {
                Text("\(count)").font(.system(size: 11.5, weight: .semibold))
            }
            Image(systemName: note.chevronUp ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(Palette.primary)
        .padding(.horizontal, p(note.count == nil ? 0 : 10))
        .frame(minWidth: p(38), minHeight: p(28))
        .background(Capsule().fill(Palette.chip))
    }
}

// MARK: - Quick settings tiles (top of the list)

private struct BluetoothGlyph: Shape {
    func path(in r: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var path = Path()
        path.move(to: pt(0.2, 0.32))
        path.addLine(to: pt(0.8, 0.72))
        path.addLine(to: pt(0.5, 0.97))
        path.addLine(to: pt(0.5, 0.03))
        path.addLine(to: pt(0.8, 0.28))
        path.addLine(to: pt(0.2, 0.68))
        return path
    }
}

private struct QuickSettingsRow: View {
    var body: some View {
        HStack(spacing: p(14)) {
            tile(title: "Wi-Fi", subtitle: "HomeNet_5G", width: 304) {
                Image(systemName: "wifi").font(.system(size: 26, weight: .semibold))
            }
            tile(title: "Bluetooth", subtitle: nil, width: 302) {
                BluetoothGlyph()
                    .stroke(Palette.lavenderInk, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                    .frame(width: 20, height: 28)
            }
        }
    }

    private func tile<Icon: View>(title: String, subtitle: String?, width: CGFloat,
                                  @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: p(10)) {
            RoundedRectangle(cornerRadius: p(34))
                .fill(Palette.lavender)
                .frame(width: p(84), height: p(84))
                .overlay(icon().foregroundColor(Palette.lavenderInk))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14.5, weight: .semibold)).foregroundColor(Palette.primary)
                if let subtitle {
                    Text(subtitle).font(.system(size: 12.5)).foregroundColor(Palette.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, p(10))
        .frame(width: p(width), height: p(106))
        .background(RoundedRectangle(cornerRadius: p(44)).fill(Palette.card))
    }
}

// MARK: - Bottom icon tray

/// One progress value (0...1) per tray item. An item's icon slides in from the left, pushing
/// the icons already in the tray to the right by one pitch, while it fades in.
private struct IconTray: View {
    let symbols: [String]
    let progress: [CGFloat]

    /// X of each slot: base + pitch × (sum of the progress of every icon to its left).
    private var slotX: [CGFloat] {
        var xs: [CGFloat] = []
        var acc: CGFloat = 0
        let base = Metrics.trayIconPad
        for value in progress {
            xs.append(base + Metrics.trayPitch * acc)
            acc += value
        }
        return xs
    }

    var body: some View {
        let xs = slotX
        let midY = Metrics.trayHeight / 2
        // The tray only exists once the first notification starts going under it, and it fades in
        // after the list has been cut off above it, so the two never touch.
        let trayOpacity = Motion.ramp(progress.last ?? 0, 0.06, 0.3)

        ZStack(alignment: .topLeading) {
            Capsule().fill(Palette.tray)

            ForEach(0..<symbols.count, id: \.self) { i in
                glyph(symbols[i])
                    .opacity(Motion.fade(progress[i]))
                    .position(x: xs[i], y: midY)
            }
        }
        .frame(width: Metrics.width - Metrics.trayInset * 2, height: Metrics.trayHeight)
        .clipShape(Capsule())
        .opacity(trayOpacity)
    }

    private func glyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: Metrics.trayGlyph * 0.62, weight: .semibold))
            .foregroundColor(Palette.trayIcon)
            .frame(width: Metrics.trayGlyph, height: Metrics.trayGlyph)
    }
}

// MARK: - Tray spring simulation

/// Smooths the tray. The scroll position gives each icon a *target* (0...1); each icon then chases
/// its target with a slightly under-damped spring (a little bounce), so a fast flick plays out as a
/// smooth motion instead of icons popping in/out. An ordering rule keeps icons arriving bottom-up
/// and leaving in the reverse order: an icon can only be as far in as 2.5× the icon after it.
private final class TraySimulator {
    private var value: [CGFloat]
    private var velocity: [CGFloat]
    private var lastTime: TimeInterval?

    private let stiffness: CGFloat = 260
    private let damping: CGFloat = 17          // ζ ≈ 0.53 → one soft overshoot
    private let lead: CGFloat = 2.5            // how far an icon may run ahead of the next one

    init(count: Int) {
        value = Array(repeating: 0, count: count)
        velocity = Array(repeating: 0, count: count)
    }

    func step(targets: [CGFloat], date: Date) -> [CGFloat] {
        let now = date.timeIntervalSinceReferenceDate
        defer { lastTime = now }
        guard let last = lastTime, targets.count == value.count else {
            value = targets                       // first frame / preview: no animation
            velocity = Array(repeating: 0, count: targets.count)
            return value
        }
        let dt = min(max(now - last, 0), 1.0 / 15)
        guard dt > 0 else { return value }

        let steps = max(1, Int((dt * 240).rounded(.up)))
        let h = CGFloat(dt) / CGFloat(steps)
        let n = value.count
        for _ in 0..<steps {
            var t = targets
            // Appearing: icon i can't run ahead of the icon after it (the one that went under first).
            if n > 1 {
                for i in stride(from: n - 2, through: 0, by: -1) {
                    t[i] = min(t[i], lead * max(value[i + 1], 0))
                }
                // Leaving: the icon after i can't leave before i has left.
                for i in 0..<(n - 1) {
                    t[i + 1] = max(t[i + 1], max(value[i], 0) / lead)
                }
            }
            for i in 0..<n {
                let accel = stiffness * (t[i] - value[i]) - damping * velocity[i]
                velocity[i] += accel * h
                value[i] += velocity[i] * h
            }
        }
        return value
    }
}

// MARK: - Shade

private struct NotificationShade: View {
    @State private var tray = TraySimulator(count: Shade.notes.count)

    /// List travel in points. 0 = bottom of the list, `p(Shade.maxScrollPx)` = top.
    let scroll: CGFloat

    private var scrollPx: CGFloat { scroll * pxPerPt }
    private var contentTopPx: CGFloat { Shade.anchorBottom - Shade.layout.contentHeight + scrollPx }

    /// 0...1 for a card: how far it has gone under the tray (eased), from its position on screen.
    private func hiddenProgress(topPx: CGFloat, heightPx: CGFloat) -> CGFloat {
        let hidden = min(max((topPx + heightPx - Shade.clipLine) / heightPx, 0), 1)
        return Motion.ramp(hidden, Motion.hiddenStart, Motion.hiddenEnd)
    }

    private var trayProgress: [CGFloat] {
        var values: [CGFloat] = []
        for (note, top) in zip(Shade.notes, Shade.layout.tops) {
            values.append(hiddenProgress(topPx: contentTopPx + top, heightPx: note.height))
        }
        return values
    }

    var body: some View {
        let progress = trayProgress
        let tick = scrollPx >= 349

        ZStack(alignment: .topLeading) {
            Backdrop()

            list(tick: tick)
                .offset(y: p(contentTopPx))

            // Cuts the list off above the tray with rounded corners (drawn over the list). The cut line
            // is fixed; at rest the last card ends just above it, so nothing is clipped.
            CutCover(amount: 1)

            TimelineView(.animation) { context in
                IconTray(symbols: Shade.traySymbols,
                         progress: tray.step(targets: progress, date: context.date))
            }
            .offset(x: Metrics.trayInset, y: Metrics.trayTop)
        }
        .frame(width: Metrics.width, height: Metrics.height, alignment: .topLeading)
    }

    private func positioned(_ index: Int) -> Note {
        var note = Shade.notes[index]
        note.position = index == 0 ? .first : (index == Shade.notes.count - 1 ? .last : .middle)
        return note
    }

    private func ticked(_ note: Note, _ tick: Bool) -> Note {
        guard note.ticking, tick else { return note }
        var copy = note
        copy.time = "48m"
        return copy
    }

    /// Every card is placed at an absolute position (from the layout table), background included.
    private func list(tick: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            QuickSettingsRow()
                .offset(x: Metrics.inset)

            ForEach(Array(Shade.notes.indices), id: \.self) { i in
                let note = ticked(positioned(i), tick)
                NotificationCard(note: note)
                    .background(UnevenRoundedRectangle(cornerRadii: note.cornerRadii).fill(Palette.card))
                    .offset(x: Metrics.inset, y: p(Shade.layout.tops[i]))
            }
        }
        .frame(width: Metrics.width, alignment: .topLeading)
    }
}

// MARK: - Backdrop & cut-off cover

private struct Backdrop: View {
    /// Extra height below the design frame, filled with the bottom colour.
    var extraBottom: CGFloat = 0

    var body: some View {
        let total = Metrics.height + extraBottom
        LinearGradient(stops: [.init(color: Palette.backgroundTop, location: 0),
                               .init(color: Palette.backgroundBottom, location: Metrics.height / total),
                               .init(color: Palette.backgroundBottom, location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .frame(width: Metrics.width, height: total)
    }
}

/// Everything on the screen except a rounded "window".
private struct OutsideWindow: Shape {
    var window: CGRect
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        let corners = RectangleCornerRadii(topLeading: 0, bottomLeading: radius,
                                           bottomTrailing: radius, topTrailing: 0)
        path.addPath(UnevenRoundedRectangle(cornerRadii: corners).path(in: window))
        return path
    }
}

/// The backdrop gradient painted over everything outside the list's window. `amount` 0 = window is
/// the whole screen height (nothing hidden); 1 = window ends just above the tray with rounded
/// bottom corners. The list itself is never clipped, so cards always keep their full background
/// and simply slide under this cover.
private struct CutCover: View {
    let amount: CGFloat
    static let extra: CGFloat = 3000      // reaches past the bottom of any device

    var body: some View {
        let bottom = Metrics.height + (p(Shade.clipLine) - Metrics.height) * amount
        let window = CGRect(x: Metrics.inset, y: -Metrics.height,
                            width: Metrics.width - Metrics.inset * 2,
                            height: bottom + Metrics.height)
        Backdrop(extraBottom: Self.extra)
            .mask {
                OutsideWindow(window: window, radius: p(36) * amount)
                    .fill(Color.white, style: FillStyle(eoFill: true))
                    .frame(width: Metrics.width, height: Metrics.height + Self.extra)
            }
            .allowsHitTesting(false)
    }
}

// MARK: - Public demo view

/// Drag up/down to scroll the shade.
/// `initialScroll` (px of list travel from the bottom) is handy for previews.
struct AndroidStyleNotificationIconTray: View {
    var initialScroll: CGFloat = 0

    @State private var scroll: CGFloat = 0
    @State private var dragStart: CGFloat? = nil
    @State private var seeded = false

    private let maxScroll = p(Shade.maxScrollPx)

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / Metrics.width, geo.size.height / Metrics.height)
            NotificationShade(scroll: scroll)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
                .background(deviceBackground(in: geo.size, scale: scale))
                .contentShape(Rectangle())
                .gesture(drag(scale: scale))
        }
        .ignoresSafeArea()
        .onAppear {
            guard !seeded else { return }
            seeded = true
            scroll = min(p(initialScroll), maxScroll)
        }
    }

    /// The same gradient as the shade's backdrop, stretched so it fills the whole device
    /// (including safe areas): flat top colour above the design frame, flat bottom colour below.
    private func deviceBackground(in size: CGSize, scale: CGFloat) -> some View {
        let frameHeight = Metrics.height * scale
        let top = (size.height - frameHeight) / 2
        let a = max(0, min(1, top / size.height))
        let b = max(a, min(1, (top + frameHeight) / size.height))
        return LinearGradient(stops: [.init(color: Palette.backgroundTop, location: 0),
                                      .init(color: Palette.backgroundTop, location: a),
                                      .init(color: Palette.backgroundBottom, location: b),
                                      .init(color: Palette.backgroundBottom, location: 1)],
                              startPoint: .top, endPoint: .bottom)
    }

    private func drag(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let base = dragStart ?? scroll
                dragStart = base
                // Dragging down moves the list down (scroll increases).
                scroll = rubberBand(base + value.translation.height / scale)
            }
            .onEnded { value in
                dragStart = nil
                // Coast with the flick's velocity toward a point clamped to the content, using an
                // under-damped spring so the list bounces at either end.
                let velocity = value.velocity.height / scale
                let projected = scroll + velocity * 0.22
                let target = min(max(projected, 0), maxScroll)
                let distance = target - scroll
                let relative = abs(distance) > 1 ? max(-30, min(30, velocity / distance)) : 0
                withAnimation(.interpolatingSpring(stiffness: 85, damping: 11, initialVelocity: relative)) {
                    scroll = target
                }
            }
    }

    /// Soft resistance past either end of the list.
    private func rubberBand(_ x: CGFloat) -> CGFloat {
        if x < 0 { return -pow(-x, 0.75) }
        if x > maxScroll { return maxScroll + pow(x - maxScroll, 0.75) }
        return x
    }
}

// MARK: - Previews

#Preview("Drag me") {
    AndroidStyleNotificationIconTray()
}

#Preview("Tray appears") {
    AndroidStyleNotificationIconTray(initialScroll: 70)
}

#Preview("A few icons collected") {
    AndroidStyleNotificationIconTray(initialScroll: 400)
}
