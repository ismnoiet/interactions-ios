//
//  ClaudeStyleNavigation.swift
//  Created by ismnoiet
//
//  Interactive predictive-back / forward navigation (SwiftUI, iOS 17+).
//
//  • On the chat screen: drag from the LEFT edge to go back to the list.
//  • On the list screen: drag from the RIGHT edge to go forward to the chat.
//  • The back arrow and tapping the first list row work too.
//
//  One value, `q`, drives everything:
//      q = 0  -> chat fully shown
//      q = 1  -> chat gone, list fully shown (100% brightness)
//  While dragging, `q` follows your finger across the whole screen.
//  On release it commits past ~35% of the width, or on a fast flick.
//

import SwiftUI

struct ClaudeStyleNavigation: View {
    @State private var q: CGFloat = 0
    @State private var chatShown = true
    @State private var dragEdge: HorizontalEdge?
    @State private var tracking = false
    @GestureState private var gestureActive = false
    @State private var bubbleInset: CGFloat = 22   // bubble distance from the touched edge
    @State private var lastDx: CGFloat = 0
    @State private var p: CGFloat = 0            // finger travel / screen width
    @State private var touchY: CGFloat = 0.6     // fraction of height

    private let edgeZone: CGFloat = 32
    private let dragReach: CGFloat = 0.3         // q where the "peeled" pose is reached
    private let commitAnim = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.32)
    private let cancelAnim = Animation.spring(response: 0.3, dampingFraction: 0.8)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            let lift = min(q / dragReach, 1)            // 0...1 while peeling
            let beyond = max(0, q - dragReach)          // travel past the peeled pose
            let reveal = min(1, beyond / 0.5)           // list: brightens, grows, settles
            let fade = min(1, beyond / 0.25)            // chat: fades out
            let exit = min(1, beyond / 0.7)             // chat: keeps shrinking
            let backDim = 0.6 * (1 - reveal)            // 0 when settled

            ZStack {
                // BACK SCREEN (list)
                ListScreen(onOpen: { go(toChat: true) })
                    .scaleEffect(0.95 + 0.05 * reveal)
                    .offset(x: -0.09 * w * (1 - reveal))
                    .overlay {
                        if backDim > 0.001 {
                            Color.black.opacity(backDim).allowsHitTesting(false)
                        }
                    }

                // FRONT SCREEN (chat)
                ChatScreen(onBack: { go(toChat: false) })
                    .clipShape(RoundedRectangle(cornerRadius: 36 * lift, style: .continuous))
                    .scaleEffect(1 - 0.05 * lift - 0.15 * exit)
                    .offset(x: q * w)
                    .overlay(
                        Color.black.opacity(0.5 * lift).allowsHitTesting(false)
                    )
                    .shadow(color: .black.opacity(0.5 * lift * (1 - fade)), radius: 18, x: -6)
                    .opacity(1 - fade)

                // Chevron bubble (follows the finger)
                BackBubble(forward: dragEdge == .trailing)
                    .scaleEffect(dragEdge != nil ? 1 : 0.3)
                    .opacity(dragEdge != nil ? 1 : 0)
                    .position(
                        x: dragEdge == .trailing ? w - bubbleInset : bubbleInset,
                        y: h * touchY
                    )
                    .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.9), value: bubbleInset)
            }
            .frame(width: w, height: h)
            .background(Color.black)
            .contentShape(Rectangle())
            .simultaneousGesture(
                // minimumDistance > 0 so a plain tap on the back arrow (which sits
                // inside the edge zone) never starts an edge drag / bubble.
                DragGesture(minimumDistance: 8)
                    .updating($gestureActive) { _, state, _ in state = true }
                    .onChanged { v in
                        if !tracking {
                            tracking = true
                            var edge: HorizontalEdge?
                            if chatShown && v.startLocation.x < edgeZone { edge = .leading }
                            else if !chatShown && v.startLocation.x > w - edgeZone { edge = .trailing }
                            guard let e = edge else { return }
                            touchY = max(0.2, min(0.85, v.startLocation.y / h))
                            p = 0
                            bubbleInset = 22
                            lastDx = 0
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { dragEdge = e }
                        }
                        guard let e = dragEdge else { return }
                        let dx = e == .leading ? v.translation.width : -v.translation.width
                        var tx = Transaction()
                        tx.disablesAnimations = true
                        withTransaction(tx) {
                            p = max(0, min(1, dx / w))
                            q = chatShown ? p : 1 - p
                        }
                        // Bubble keeps up with fast drags: the faster the finger,
                        // the more of its travel the bubble copies (0.55x -> 0.95x),
                        // and a very short interactive spring smooths touch jitter.
                        let speed = min(1, abs(v.velocity.width) / 1800)
                        let k = 0.55 + 0.4 * speed
                        let next = bubbleInset + (dx - lastDx) * k
                        bubbleInset = max(22, min(next, 22 + max(dx, 0), w * 0.92))
                        lastDx = dx
                    }
                    .onEnded { v in
                        defer { tracking = false }
                        guard let e = dragEdge else { return }
                        let predicted = (e == .leading ? v.predictedEndTranslation.width
                                                       : -v.predictedEndTranslation.width) / w
                        let shouldCommit = p > 0.35 || predicted > 0.6
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) { dragEdge = nil }
                        if shouldCommit {
                            go(toChat: !chatShown)
                        } else {
                            withAnimation(cancelAnim) { q = chatShown ? 0 : 1 }
                        }
                    }
            )
            // Safety net: if the system cancels the gesture, never leave the bubble stuck.
            .onChange(of: gestureActive) { _, active in
                if !active, tracking {
                    tracking = false
                    if dragEdge != nil {
                        withAnimation(cancelAnim) {
                            dragEdge = nil
                            q = chatShown ? 0 : 1
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    // MARK: - Navigation

    /// Button / tap navigation: same transition, no drag bubble.
    private func go(toChat: Bool) {
        guard toChat != chatShown else { return }
        withAnimation(commitAnim) {
            chatShown = toChat
            q = toChat ? 0 : 1
        }
    }
}

// MARK: - Back / forward bubble

private struct BackBubble: View {
    let forward: Bool
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.20, green: 0.28, blue: 0.38).opacity(0.92))
                .frame(width: 52, height: 52)
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }
}

// MARK: - Front screen (chat)

private struct ChatScreen: View {
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Button(action: onBack) { Image(systemName: "arrow.left") }
                Text("Lisbon trip").font(.headline)
                Spacer()
                Image(systemName: "ellipsis")
            }
            .foregroundStyle(.white)
            .padding(.top, 60)

            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.06))
                .frame(height: 96)
                .overlay(alignment: .leading) {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(red: 0.12, green: 0.08, blue: 0.35))
                            .frame(width: 64, height: 64)
                            .overlay(Image(systemName: "square.on.square").foregroundStyle(.indigo))
                        VStack(alignment: .leading) {
                            Text("Trip Itinerary").font(.system(.title3, design: .serif))
                            Text("Document").foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                }

            Group {
                Text("I've updated the itinerary and saved it, so you can open it on your phone or laptop.")
                Text("What's new:").padding(.top, 4)
                bullet("Day 1:", "arrival, check-in and a relaxed evening walk by the river.")
                bullet("Day 2:", "morning museum visit, then lunch in the old town.")
                bullet("Day 3:", "a day trip to the coast with a late seafood dinner.")
                bullet("Packing:", "a short checklist added at the bottom of the page.")
            }
            .font(.system(size: 17, design: .serif))
            .foregroundStyle(.white.opacity(0.92))

            Spacer()

            HStack {
                Image(systemName: "plus").padding(14).background(Color.white.opacity(0.1), in: Circle())
                Text("Type a message").foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "mic").foregroundStyle(.secondary)
            }
            .padding(8)
            .background(Color.white.opacity(0.07), in: Capsule())
            .foregroundStyle(.white)
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.10, green: 0.10, blue: 0.10))
    }

    private func bullet(_ bold: String, _ rest: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text("**\(bold)** \(rest)")
        }
    }
}

// MARK: - Back screen (list)

private struct ListScreen: View {
    let onOpen: () -> Void

    private let chats: [(String, String)] = [
        ("Lisbon trip planning", "Just now"),
        ("Packing checklist", "Yesterday"),
        ("Flight options", "Yesterday"),
        ("Hotel shortlist", "Mon"),
        ("Museum passes", "Sun"),
        ("Day trip ideas", "Oct 12, 2026"),
        ("Budget breakdown", "Oct 11, 2026"),
        ("Restaurant ideas", "Oct 9, 2026"),
        ("Train vs. rental car", "Oct 8, 2026"),
        ("Local phrases to learn", "Oct 6, 2026"),
        ("Weather and what to wear", "Oct 4, 2026")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Image(systemName: "ellipsis")
            }
            .padding(.top, 60)
            .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
              VStack(alignment: .leading, spacing: 20) {
            Text("Travel").font(.system(size: 34, design: .serif))

            ForEach(chats, id: \.0) { c in
                Button(action: onOpen) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 17))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.0).font(.system(size: 19, design: .serif))
                            Text(c.1).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
              }
              .padding(.bottom, 40)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.08, blue: 0.08))
    }
}

#Preview {
    ClaudeStyleNavigation()
}
