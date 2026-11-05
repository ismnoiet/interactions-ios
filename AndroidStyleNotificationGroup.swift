//
//  AndroidStyleNotificationGroup.swift
//
//  Created by ismnoiet.
//
//  An Android-style expandable notification group, built with SwiftUI.
//  Inspired by Android's notification shade; not affiliated with or endorsed by Google.
//

import SwiftUI

// A grouped-notification card that expands and collapses with a tap or a vertical drag.
//
// The whole animation is driven by a single value, `progress` (0 = collapsed, 1 = expanded).
// Each element (avatar, title, subtitles, count pills, ...) derives its own position and opacity
// from that value, which keeps tapping, dragging and flicking perfectly in sync.

// MARK: - Screen

struct AndroidStyleNotificationGroup: View {
    /// 0 = collapsed, 1 = expanded.
    @State private var progress: CGFloat = 0
    /// Target state of the card. Drives the header chevron.
    @State private var isExpanded = false
    /// Value of `progress` when the current drag began (nil when not dragging).
    @State private var dragStartProgress: CGFloat? = nil

    /// Finger travel, in points, needed to go from fully collapsed to fully expanded.
    private let dragDistance: CGFloat = 110

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.08, blue: 0.14),
                         Color(red: 0.08, green: 0.12, blue: 0.22)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                NotificationGroupCard(progress: progress, isChevronUp: isExpanded) {
                    animate(toExpanded: !isExpanded)
                }
                .simultaneousGesture(dragGesture)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 24)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Interaction

    /// Animates to the expanded or collapsed state with a fast-out, slow-in curve (no bounce).
    private func animate(toExpanded expanded: Bool) {
        isExpanded = expanded
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.42)) {
            progress = expanded ? 1 : 0
        }
    }

    /// Dragging down expands, dragging up collapses. The card follows the finger 1:1 and,
    /// on release, settles to whichever state the gesture was heading towards.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if dragStartProgress == nil { dragStartProgress = progress }
                let start = dragStartProgress ?? 0
                let newProgress = min(max(start + value.translation.height / dragDistance, 0), 1)

                // Follow the finger immediately, without animation.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    progress = newProgress
                    isExpanded = newProgress > 0.5
                }
            }
            .onEnded { value in
                // Use the predicted end point so a quick flick counts even if it was short.
                let start = dragStartProgress ?? progress
                let predicted = start + value.predictedEndTranslation.height / dragDistance
                dragStartProgress = nil
                animate(toExpanded: predicted > 0.5)
            }
    }
}

// MARK: - Notification group card

/// The card itself. Everything it draws is a function of `progress`.
struct NotificationGroupCard: View, Animatable {
    var progress: CGFloat
    var isChevronUp: Bool
    var onTap: () -> Void

    // Lets SwiftUI interpolate `progress` frame by frame, so all the math below runs every frame.
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    // MARK: Content

    private struct Message {
        let sender: String
        let age: String
        let text: String
        let unreadCount: Int
        let avatarColor: Color
    }

    private let messages = [
        Message(sender: "Maya Chen", age: "1h",
                text: "Are we still on for lunch tomorrow? I can book a table…",
                unreadCount: 4, avatarColor: Palette.teal),
        Message(sender: "Jordan", age: "9h",
                text: "Your order has shipped and should arrive by Friday…",
                unreadCount: 2, avatarColor: Palette.purple)
    ]

    // MARK: Layout (points)

    private let padding: CGFloat = 16
    private let appIconSize: CGFloat = 36

    private let collapsedHeight: CGFloat = 92
    private let expandedHeight: CGFloat = 202

    /// Header vertical centre: collapsed -> expanded.
    private let headerCenterY: (collapsed: CGFloat, expanded: CGFloat) = (22, 33)

    /// Vertical centre of each message row: collapsed -> expanded.
    private let rowCenterY: [(collapsed: CGFloat, expanded: CGFloat)] = [(45, 100), (70, 168)]

    private let avatarSize: (collapsed: CGFloat, expanded: CGFloat) = (14, 36)

    /// Left edge of the small avatar when collapsed (just right of the app icon).
    private var collapsedAvatarLeading: CGFloat { padding + appIconSize + 14 }
    /// Left edge of the title and subtitle text when expanded (just right of the large avatar).
    private var expandedTextLeading: CGFloat { padding + avatarSize.expanded + 14 }
    /// Left edge of the inline (collapsed) text.
    private var collapsedTextLeading: CGFloat { collapsedAvatarLeading + avatarSize.collapsed + 6 }

    // MARK: Animation tuning

    /// Avatars and titles move along `progress^jumpPower`: slow at first, then they snap into place.
    private let jumpPower: CGFloat = 2.4

    /// The gap between the two rows opens along `progress^rowGapPower`. Higher values keep
    /// the two avatars closer together for longer before they spread out.
    private let rowGapPower: CGFloat = 5.6

    /// The expanded subtitle starts to appear once the inline subtitle has faded down to this
    /// opacity (0.8 = still 80% visible). It then fades in until the animation ends.
    private let subtitleStartsAtInlineOpacity: CGFloat = 0.8

    // MARK: Body

    var body: some View {
        let p = clamp(progress)
        let headerY = lerp(headerCenterY.collapsed, headerCenterY.expanded, p)

        // Row 1 moves with the card. Row 2 stays close behind it and only opens up to its
        // full spacing near the end of the animation.
        let row1Y = lerp(rowCenterY[0].collapsed, rowCenterY[0].expanded, p)
        let fullGap = rowCenterY[1].expanded - rowCenterY[0].expanded
        let startGap = rowCenterY[1].collapsed - rowCenterY[0].collapsed
        let gap = lerp(startGap, fullGap, pow(p, rowGapPower))

        ZStack(alignment: .topLeading) {
            Palette.card

            appIcon
            header(centerY: headerY)

            ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                row(message,
                    centerY: index == 0 ? row1Y : row1Y + gap,
                    linearCenterY: lerp(rowCenterY[index].collapsed, rowCenterY[index].expanded, p),
                    progress: p)
            }
        }
        .frame(height: lerp(collapsedHeight, expandedHeight, p))
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    // MARK: Header

    private var appIcon: some View {
        Image(systemName: "message.fill")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Color(red: 0.2, green: 0.4, blue: 0.95))
            .frame(width: appIconSize, height: appIconSize)
            .background(Circle().fill(.white))
            .offset(x: padding, y: 17)
    }

    private func header(centerY: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Text("Messages • 1h")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.secondaryText)
                .placed(leading: padding + appIconSize + 12, centerY: centerY)

            // The chevron flips as soon as the state changes, not gradually with the animation.
            HStack(spacing: 3) {
                Text("2").font(.system(size: 11.5, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(isChevronUp ? 180 : 0))
                    .animation(.easeOut(duration: 0.12), value: isChevronUp)
            }
            .foregroundStyle(Palette.primaryText)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Palette.chip))
            .placed(trailing: padding, centerY: centerY)
        }
    }

    // MARK: Message row

    @ViewBuilder
    private func row(_ message: Message, centerY: CGFloat, linearCenterY: CGFloat, progress p: CGFloat) -> some View {
        // `snap` drives the avatar and the sender name; everything else follows `p` directly.
        let snap = pow(p, jumpPower)

        let avatarDiameter = lerp(avatarSize.collapsed, avatarSize.expanded, snap)
        let avatarCenterX = lerp(collapsedAvatarLeading + avatarSize.collapsed / 2, padding + avatarSize.expanded / 2, snap)
        let senderLeading = lerp(collapsedTextLeading, expandedTextLeading, snap)

        // The title line sits level with the avatar when collapsed and 9pt above it when expanded.
        // Everything on that line (sender, inline message, "• 1h", count pill) shares this one
        // y position, so the pieces never drift apart vertically while they cross-fade.
        let titleY = centerY + lerp(0, -9, snap)

        // The expanded subtitle starts low (just under the avatar) and settles 9pt below the row
        // centre. It follows the row's steady, linear path instead of the lagging row gap, so it
        // glides slowly while it fades in instead of shifting quickly.
        let subtitleY = linearCenterY + 9 + 55 * (1 - p)

        // Opacities
        let inlineOpacity = Self.inlineSubtitleOpacity(p)
        let pillOpacity = smoothstep(0.20, 0.85, p)

        let subtitleStart = Self.progress(whereInlineOpacityIs: subtitleStartsAtInlineOpacity)
        let subtitleProgress = clamp((p - subtitleStart) / (1 - subtitleStart))
        let subtitleOpacity = pow(subtitleProgress, 1.5)

        // The expanded subtitle is masked at the bottom edge of the avatar and is uncovered as
        // the avatar grows.
        let subtitleRevealBottom = max(centerY + avatarDiameter / 2, 0)

        ZStack(alignment: .topLeading) {
            avatar(color: message.avatarColor, diameter: avatarDiameter, centerX: avatarCenterX, centerY: centerY)

            // Collapsed: sender and message on a single line. Only the message is drawn here;
            // the sender is an invisible spacer because the real sender text moves separately.
            (Text(message.sender).font(.system(size: 13, weight: .bold)).foregroundColor(.clear)
             + Text("  " + message.text).font(.system(size: 12.5)).foregroundColor(Palette.secondaryText))
                .lineLimit(1)
                .opacity(inlineOpacity)
                .placed(leading: collapsedTextLeading, centerY: titleY)

            // Expanded: "• 1h" next to the sender name (again with an invisible name as a spacer).
            (Text(message.sender).font(.system(size: 13, weight: .bold)).foregroundColor(.clear)
             + Text("  • " + message.age).font(.system(size: 11.5)).foregroundColor(Palette.secondaryText))
                .lineLimit(1)
                .opacity(subtitleOpacity)
                .placed(leading: expandedTextLeading, centerY: titleY)

            // Expanded: the full message on its own line.
            Text(message.text)
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(1)
                .opacity(subtitleOpacity)
                .placed(leading: expandedTextLeading, centerY: subtitleY)
                .mask(alignment: .topLeading) {
                    Rectangle().frame(width: 4000, height: subtitleRevealBottom)
                }

            unreadPill(count: message.unreadCount)
                .opacity(pillOpacity)
                .placed(trailing: padding, centerY: titleY)

            // A single sender label that glides from its inline position to the title position.
            Text(message.sender)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.primaryText)
                .placed(leading: senderLeading, centerY: titleY)
        }
    }

    private func avatar(color: Color, diameter: CGFloat, centerX: CGFloat, centerY: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: diameter * 0.5))
                    .foregroundStyle(.black.opacity(0.85))
            )
            .offset(x: centerX - diameter / 2, y: centerY - diameter / 2)
    }

    private func unreadPill(count: Int) -> some View {
        HStack(spacing: 3) {
            Text("\(count)").font(.system(size: 11.5, weight: .semibold))
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(Color(red: 0.2, green: 0.15, blue: 0.35))
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(Capsule().fill(Palette.pill))
    }

    // MARK: Inline subtitle fade

    /// Opacity of the collapsed, single-line message. It fades steadily from the start of the
    /// animation and is fully gone at the end.
    private static func inlineSubtitleOpacity(_ p: CGFloat) -> CGFloat {
        clamp(1.02 - 0.62 * p - 0.4 * smoothstep(0.75, 1.0, p))
    }

    /// The animation progress at which the inline message has faded down to `opacity`.
    private static func progress(whereInlineOpacityIs opacity: CGFloat) -> CGFloat {
        var low: CGFloat = 0, high: CGFloat = 1
        for _ in 0..<30 {                       // bisection: the opacity only ever decreases
            let mid = (low + high) / 2
            if inlineSubtitleOpacity(mid) > opacity { low = mid } else { high = mid }
        }
        return (low + high) / 2
    }
}

// MARK: - Palette

private enum Palette {
    static let card = Color(red: 0.10, green: 0.11, blue: 0.16)
    static let primaryText = Color(red: 0.89, green: 0.89, blue: 0.92)
    static let secondaryText = Color(red: 0.77, green: 0.78, blue: 0.82)
    static let teal = Color(red: 0.25, green: 0.80, blue: 0.82)
    static let purple = Color(red: 0.66, green: 0.30, blue: 0.95)
    static let pill = Color(red: 0.78, green: 0.72, blue: 0.95)
    static let chip = Color.white.opacity(0.10)
}

// MARK: - Math helpers

/// Linear interpolation from `a` to `b`.
private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

/// Clamps a value to 0...1.
private func clamp(_ value: CGFloat) -> CGFloat { min(max(value, 0), 1) }

/// Smooth 0...1 ramp between `edge0` and `edge1`.
private func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
    let t = clamp((x - edge0) / (edge1 - edge0))
    return t * t * (3 - 2 * t)
}

// MARK: - Positioning helpers

private extension View {
    /// Positions a single line of content by its leading edge and vertical centre,
    /// in the coordinate space of the enclosing card.
    func placed(leading: CGFloat, centerY: CGFloat, trailingInset: CGFloat = 16) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, leading)
            .padding(.trailing, trailingInset)
            .frame(height: 20)
            .offset(y: centerY - 10)
    }

    /// Positions content by its trailing edge and vertical centre.
    func placed(trailing: CGFloat, centerY: CGFloat) -> some View {
        frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, trailing)
            .frame(height: 24)
            .offset(y: centerY - 12)
    }
}

#Preview { AndroidStyleNotificationGroup() }
