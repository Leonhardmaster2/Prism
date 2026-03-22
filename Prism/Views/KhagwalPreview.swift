import SwiftUI

// MARK: - Khagwal Design System Preview
// Standalone preview — not wired into the app.
// Showcases the "Smooth & Simple" / Soft Minimalism aesthetic.

// ╔══════════════════════════════════════════════════════════╗
// ║  DESIGN TOKENS                                           ║
// ╚══════════════════════════════════════════════════════════╝

private enum Khagwal {
    // Springs
    static let spring: Animation = .spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0)
    static let bouncySpring: Animation = .spring(response: 0.5, dampingFraction: 0.6)
    static let gentleSpring: Animation = .spring(response: 0.55, dampingFraction: 0.85)

    // Radii
    static let cardRadius: CGFloat = 24
    static let buttonRadius: CGFloat = 14
    static let smallRadius: CGFloat = 12

    // Shadows
    static func softShadow() -> some ViewModifier { SoftShadowModifier() }

    // Colors
    static let background: Color = .white
    static let secondaryFill: Color = Color.gray.opacity(0.1)
    static let subtleFill: Color = Color.primary.opacity(0.05)
}

// ╔══════════════════════════════════════════════════════════╗
// ║  BUTTON STYLE                                           ║
// ╚══════════════════════════════════════════════════════════╝

private struct KhagwalButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.black.opacity(0))
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  VIEW MODIFIERS                                         ║
// ╚══════════════════════════════════════════════════════════╝

private struct SoftShadowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.05), radius: 20, x: 0, y: 10)
    }
}

private struct KhagwalCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Khagwal.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Khagwal.cardRadius, style: .continuous)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 20, x: 0, y: 10)
    }
}

private struct KhagwalSolidCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Khagwal.background)
            .clipShape(RoundedRectangle(cornerRadius: Khagwal.cardRadius, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 20, x: 0, y: 10)
    }
}

private extension View {
    func khagwalCard() -> some View { modifier(KhagwalCardModifier()) }
    func khagwalSolidCard() -> some View { modifier(KhagwalSolidCardModifier()) }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  1. MORPHING ACTION BUTTON                              ║
// ║  Circle → Pill toolbar with inline checkmark feedback   ║
// ╚══════════════════════════════════════════════════════════╝

private struct MorphingActionButton: View {
    @State private var isExpanded = false
    @State private var feedbackItem: String?
    @Namespace private var morphNS

    private let icons = ["photo", "camera", "mic.fill", "doc.text"]

    var body: some View {
        ZStack {
            if !isExpanded {
                Button {
                    withAnimation(Khagwal.spring) { isExpanded = true }
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(
                            Circle()
                                .fill(.black)
                                .matchedGeometryEffect(id: "morph-bg", in: morphNS)
                        )
                }
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                .zIndex(1)
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(icons.enumerated()), id: \.offset) { index, icon in
                        Button {
                            withAnimation(Khagwal.spring) { feedbackItem = icon }
                            Task {
                                try? await Task.sleep(for: .milliseconds(700))
                                withAnimation(Khagwal.spring) {
                                    feedbackItem = nil
                                    isExpanded = false
                                }
                            }
                        } label: {
                            Image(systemName: feedbackItem == icon ? "checkmark" : icon)
                                .font(.body.weight(.semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .scaleEffect(feedbackItem == icon ? 1.15 : 1.0)
                        .animation(Khagwal.bouncySpring.delay(Double(index) * 0.04), value: isExpanded)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 56)
                .background(
                    Capsule()
                        .fill(.black)
                        .matchedGeometryEffect(id: "morph-bg", in: morphNS)
                )
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .animation(Khagwal.spring, value: isExpanded)
        .animation(Khagwal.spring, value: feedbackItem)
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  2. SPLIT DELETE BUTTON (Progressive Disclosure)        ║
// ║  Trash icon → splits into Delete / Cancel               ║
// ╚══════════════════════════════════════════════════════════╝

private struct SplitDeleteButton: View {
    @State private var phase: Phase = .idle
    @Namespace private var splitNS

    private enum Phase { case idle, confirming, deleted }

    var body: some View {
        ZStack {
            switch phase {
            case .idle:
                Button {
                    withAnimation(Khagwal.spring) { phase = .confirming }
                } label: {
                    Image(systemName: "trash")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: Khagwal.buttonRadius, style: .continuous)
                                .fill(.black)
                                .matchedGeometryEffect(id: "split-bg", in: splitNS)
                        )
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity))

            case .confirming:
                HStack(spacing: 10) {
                    Button {
                        withAnimation(Khagwal.spring) { phase = .deleted }
                        Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            withAnimation(Khagwal.spring) { phase = .idle }
                        }
                    } label: {
                        Text("Delete")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: Khagwal.buttonRadius, style: .continuous)
                                    .fill(Color.red)
                            )
                    }

                    Button {
                        withAnimation(Khagwal.spring) { phase = .idle }
                    } label: {
                        Text("Cancel")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: Khagwal.buttonRadius, style: .continuous)
                                    .fill(Khagwal.secondaryFill)
                            )
                    }
                }
                .background(
                    Capsule()
                        .fill(.clear)
                        .matchedGeometryEffect(id: "split-bg", in: splitNS)
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))

            case .deleted:
                Label("Removed", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(Khagwal.spring, value: phase)
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  3. FAN MENU                                            ║
// ║  Floating button → arc of staggered options             ║
// ╚══════════════════════════════════════════════════════════╝

private struct FanMenu: View {
    @State private var isOpen = false
    @State private var tappedIndex: Int?

    private let items: [(icon: String, color: Color)] = [
        ("heart.fill", .pink),
        ("star.fill", .orange),
        ("bookmark.fill", .blue),
        ("bell.fill", .purple),
        ("flag.fill", .green),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let totalSpread = Double.pi * 0.6
                let startAngle = -Double.pi / 2 - totalSpread / 2
                let step = totalSpread / Double(items.count - 1)
                let angle = startAngle + step * Double(index)
                let radius: CGFloat = 90

                Button {
                    withAnimation(Khagwal.bouncySpring) { tappedIndex = index }
                    Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        withAnimation(Khagwal.spring) {
                            tappedIndex = nil
                            isOpen = false
                        }
                    }
                } label: {
                    Image(systemName: tappedIndex == index ? "checkmark" : item.icon)
                        .font(.body.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(tappedIndex == index ? .primary : item.color)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(Khagwal.background)
                                .overlay(Circle().stroke(.black.opacity(0.06), lineWidth: 1))
                        )
                        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
                        .contentTransition(.symbolEffect(.replace))
                }
                .offset(
                    x: isOpen ? cos(angle) * radius : 0,
                    y: isOpen ? sin(angle) * radius : 0
                )
                .scaleEffect(isOpen ? (tappedIndex == index ? 1.15 : 1.0) : 0.2)
                .opacity(isOpen ? 1 : 0)
                .animation(
                    Khagwal.bouncySpring.delay(Double(index) * 0.05),
                    value: isOpen
                )
                .animation(Khagwal.bouncySpring, value: tappedIndex)
            }

            // Center trigger
            Button {
                withAnimation(Khagwal.spring) { isOpen.toggle() }
            } label: {
                Image(systemName: isOpen ? "xmark" : "ellipsis")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(.black))
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(width: 240, height: 200)
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  4. CONTEXTUAL TOOLBAR                                  ║
// ║  Mode picker swaps tools with spring transitions        ║
// ╚══════════════════════════════════════════════════════════╝

private struct ContextualToolbar: View {
    @State private var mode: ToolMode = .text

    private enum ToolMode: String, CaseIterable {
        case text, image, draw

        var tools: [(icon: String, label: String)] {
            switch self {
            case .text:  [("bold", "Bold"), ("italic", "Italic"), ("list.bullet", "List"), ("link", "Link")]
            case .image: [("crop", "Crop"), ("slider.horizontal.3", "Adjust"), ("wand.and.stars", "Filter"), ("arrow.up.left.and.arrow.down.right", "Resize")]
            case .draw:  [("pencil.tip", "Pen"), ("paintbrush", "Brush"), ("eraser", "Eraser"), ("eyedropper", "Pick")]
            }
        }

        var icon: String {
            switch self {
            case .text:  "textformat"
            case .image: "photo"
            case .draw:  "paintpalette"
            }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 4) {
                ForEach(ToolMode.allCases, id: \.self) { m in
                    Button {
                        withAnimation(Khagwal.spring) { mode = m }
                    } label: {
                        Image(systemName: m.icon)
                            .font(.subheadline.weight(.semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(mode == m ? .white : .secondary)
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(mode == m ? .black : .clear)
                            )
                    }
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: Khagwal.buttonRadius, style: .continuous)
                    .fill(Khagwal.subtleFill)
            )

            HStack(spacing: 16) {
                ForEach(Array(mode.tools.enumerated()), id: \.element.icon) { index, tool in
                    VStack(spacing: 6) {
                        Image(systemName: tool.icon)
                            .font(.body.weight(.semibold))
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: Khagwal.smallRadius, style: .continuous)
                                    .fill(Khagwal.background)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Khagwal.smallRadius, style: .continuous)
                                            .stroke(.black.opacity(0.06), lineWidth: 1)
                                    )
                            )
                            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)

                        Text(tool.label)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity).animation(Khagwal.bouncySpring.delay(Double(index) * 0.04)),
                            removal: .scale(scale: 0.9).combined(with: .opacity)
                        )
                    )
                }
            }
            .animation(Khagwal.spring, value: mode)
        }
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  5. INLINE COPY BUTTON                                  ║
// ║  Icon morphs to checkmark with inline "Copied!" text    ║
// ╚══════════════════════════════════════════════════════════╝

private struct InlineCopyButton: View {
    @State private var copied = false
    @Namespace private var copyNS

    var body: some View {
        Button {
            withAnimation(Khagwal.spring) { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(Khagwal.spring) { copied = false }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.symbolEffect(.replace))

                if copied {
                    Text("Copied!")
                        .font(.subheadline.weight(.semibold))
                        .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
                }
            }
            .foregroundStyle(copied ? .white : .primary)
            .padding(.horizontal, copied ? 18 : 14)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: Khagwal.buttonRadius, style: .continuous)
                    .fill(copied ? .black : Khagwal.secondaryFill)
                    .matchedGeometryEffect(id: "copy-bg", in: copyNS)
            )
        }
        .animation(Khagwal.spring, value: copied)
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  6. TOGGLE PILL                                         ║
// ║  Segmented control that slides a background pill        ║
// ╚══════════════════════════════════════════════════════════╝

private struct TogglePill: View {
    @State private var selection = 0
    private let labels = ["All", "Active", "Done"]
    @Namespace private var pillNS

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Button {
                    withAnimation(Khagwal.spring) { selection = index }
                } label: {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selection == index ? .white : .secondary)
                        .padding(.horizontal, 18)
                        .frame(height: 40)
                        .background {
                            if selection == index {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.black)
                                    .matchedGeometryEffect(id: "pill-bg", in: pillNS)
                            }
                        }
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Khagwal.subtleFill)
        )
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  7. EXPANDABLE SEARCH BAR                               ║
// ║  Icon morphs into full search field                     ║
// ╚══════════════════════════════════════════════════════════╝

private struct ExpandableSearchBar: View {
    @State private var isExpanded = false
    @State private var query = ""
    @FocusState private var isFocused: Bool
    @Namespace private var searchNS

    var body: some View {
        ZStack {
            if !isExpanded {
                Button {
                    withAnimation(Khagwal.spring) { isExpanded = true }
                    isFocused = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: Khagwal.buttonRadius, style: .continuous)
                                .fill(.black)
                                .matchedGeometryEffect(id: "search-bg", in: searchNS)
                        )
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField("Search...", text: $query)
                        .font(.body)
                        .focused($isFocused)
                        .textFieldStyle(.plain)

                    Button {
                        withAnimation(Khagwal.spring) {
                            query = ""
                            isExpanded = false
                            isFocused = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Khagwal.subtleFill))
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: Khagwal.buttonRadius, style: .continuous)
                        .fill(Khagwal.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: Khagwal.buttonRadius, style: .continuous)
                                .stroke(.black.opacity(0.08), lineWidth: 1)
                        )
                        .matchedGeometryEffect(id: "search-bg", in: searchNS)
                )
                .shadow(color: .black.opacity(0.05), radius: 16, x: 0, y: 8)
                .transition(.scale(scale: 0.9, anchor: .trailing).combined(with: .opacity))
            }
        }
        .animation(Khagwal.spring, value: isExpanded)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  8. NOTIFICATION BADGE MORPH                            ║
// ║  Bell icon → badge count appears / morphs               ║
// ╚══════════════════════════════════════════════════════════╝

private struct NotificationBadge: View {
    @State private var count = 0

    var body: some View {
        HStack(spacing: 16) {
            Button {
                withAnimation(Khagwal.bouncySpring) { count += 1 }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: count > 0 ? "bell.fill" : "bell")
                        .font(.title3.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: Khagwal.buttonRadius, style: .continuous)
                                .fill(Khagwal.secondaryFill)
                        )
                        .contentTransition(.symbolEffect(.replace))

                    if count > 0 {
                        Text("\(min(count, 99))")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Circle().fill(.red))
                            .offset(x: 6, y: -6)
                            .transition(.scale(scale: 0).combined(with: .opacity))
                    }
                }
            }

            Button {
                withAnimation(Khagwal.spring) { count = 0 }
            } label: {
                Text("Clear")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Khagwal.subtleFill)
                    )
            }
            .opacity(count > 0 ? 1 : 0.4)
            .animation(Khagwal.spring, value: count)
        }
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  9. DRAG-TO-DISMISS CARD                                ║
// ║  Card responds to vertical drag with rubber-banding     ║
// ╚══════════════════════════════════════════════════════════╝

private struct DraggableCard: View {
    @State private var offset: CGSize = .zero
    @State private var isDismissed = false

    var body: some View {
        if !isDismissed {
            HStack(spacing: 14) {
                Circle()
                    .fill(.black)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "bell.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("New message")
                        .font(.subheadline.weight(.semibold))
                    Text("Swipe up to dismiss")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("now")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Khagwal.background)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 16, x: 0, y: 8)
            .offset(offset)
            .opacity(1 - Double(abs(offset.height)) / 150)
            .scaleEffect(1 - abs(offset.height) / 800)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Rubber-band: allow free up-swipe, resist down
                        let h = value.translation.height
                        offset = CGSize(width: 0, height: h < 0 ? h : h * 0.3)
                    }
                    .onEnded { value in
                        if value.translation.height < -60 {
                            withAnimation(Khagwal.spring) { isDismissed = true }
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                withAnimation(Khagwal.spring) {
                                    isDismissed = false
                                    offset = .zero
                                }
                            }
                        } else {
                            withAnimation(Khagwal.bouncySpring) { offset = .zero }
                        }
                    }
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        } else {
            Text("Dismissed! Returning in 2s...")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(height: 70)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  10. STACKED AVATAR GROUP                               ║
// ║  Tap to fan out overlapping avatars                     ║
// ╚══════════════════════════════════════════════════════════╝

private struct StackedAvatars: View {
    @State private var expanded = false

    private let colors: [Color] = [.black, .blue, .purple, .orange, .pink]
    private let initials = ["LM", "AK", "JD", "SR", "NK"]

    var body: some View {
        HStack(spacing: expanded ? 8 : -12) {
            ForEach(Array(zip(colors, initials).enumerated()), id: \.offset) { index, pair in
                Text(pair.1)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(pair.0))
                    .overlay(Circle().stroke(Khagwal.background, lineWidth: 2))
                    .zIndex(Double(colors.count - index))
                    .animation(Khagwal.bouncySpring.delay(Double(index) * 0.03), value: expanded)
            }

            if expanded {
                Text("+3")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Khagwal.subtleFill))
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Khagwal.secondaryFill)
        )
        .onTapGesture {
            withAnimation(Khagwal.bouncySpring) { expanded.toggle() }
        }
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  11. PROGRESS MORPH BUTTON                              ║
// ║  Button → progress ring → checkmark                     ║
// ╚══════════════════════════════════════════════════════════╝

private struct ProgressMorphButton: View {
    @State private var phase: ProgressPhase = .idle
    @State private var progress: CGFloat = 0
    @Namespace private var progressNS

    private enum ProgressPhase { case idle, loading, done }

    var body: some View {
        ZStack {
            switch phase {
            case .idle:
                Button {
                    withAnimation(Khagwal.spring) { phase = .loading }
                    Task {
                        for i in 1...20 {
                            try? await Task.sleep(for: .milliseconds(80))
                            withAnimation(Khagwal.gentleSpring) {
                                progress = CGFloat(i) / 20
                            }
                        }
                        withAnimation(Khagwal.bouncySpring) { phase = .done }
                        try? await Task.sleep(for: .seconds(1.5))
                        withAnimation(Khagwal.spring) {
                            phase = .idle
                            progress = 0
                        }
                    }
                } label: {
                    Text("Upload")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: Khagwal.buttonRadius, style: .continuous)
                                .fill(.black)
                                .matchedGeometryEffect(id: "progress-bg", in: progressNS)
                        )
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity))

            case .loading:
                ZStack {
                    Circle()
                        .stroke(Khagwal.subtleFill, lineWidth: 3)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(.black, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(Khagwal.background)
                        .matchedGeometryEffect(id: "progress-bg", in: progressNS)
                )
                .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 4)
                .transition(.scale(scale: 0.9).combined(with: .opacity))

            case .done:
                Image(systemName: "checkmark")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(.black)
                            .matchedGeometryEffect(id: "progress-bg", in: progressNS)
                    )
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(Khagwal.spring, value: phase)
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  12. ACCORDION LIST                                     ║
// ║  Tap to expand rows with smooth height animation        ║
// ╚══════════════════════════════════════════════════════════╝

private struct AccordionList: View {
    @State private var expanded: Int?

    private let items: [(title: String, icon: String, detail: String)] = [
        ("Notifications", "bell.fill", "Push, email, and in-app notification preferences. Control what alerts you receive and how they're delivered."),
        ("Appearance", "paintbrush.fill", "Customize themes, font sizes, and display density. Make the app feel like yours."),
        ("Privacy", "lock.fill", "Manage data sharing, analytics opt-in, and account visibility settings."),
    ]

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                VStack(spacing: 0) {
                    Button {
                        withAnimation(Khagwal.spring) {
                            expanded = expanded == index ? nil : index
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: item.icon)
                                .font(.body.weight(.semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Khagwal.subtleFill)
                                )

                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(expanded == index ? 90 : 0))
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    }

                    if expanded == index {
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 14)
                            .padding(.leading, 50)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .background(Khagwal.background)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 16, x: 0, y: 8)
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  13. FLOATING TOAST                                     ║
// ║  Inline non-disruptive feedback toast                   ║
// ╚══════════════════════════════════════════════════════════╝

private struct FloatingToastDemo: View {
    @State private var showToast = false

    var body: some View {
        ZStack {
            Button {
                withAnimation(Khagwal.bouncySpring) { showToast = true }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(Khagwal.spring) { showToast = false }
                }
            } label: {
                Text("Trigger Toast")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: Khagwal.buttonRadius, style: .continuous)
                            .fill(.black)
                    )
            }

            if showToast {
                VStack {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.green)

                        Text("Action completed")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 48)
                    .background(Khagwal.background)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(.black.opacity(0.06), lineWidth: 1))
                    .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 10)

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .offset(y: -80)
            }
        }
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  14. GLASSMORPHIC CARD                                  ║
// ║  Content card with frosted background on white          ║
// ╚══════════════════════════════════════════════════════════╝

private struct SampleCard: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .symbolVariant(.fill)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: Khagwal.buttonRadius, style: .continuous)
                        .fill(Khagwal.subtleFill)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .tracking(-0.2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 6)
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  15. LIKE BUTTON WITH PARTICLE BURST                    ║
// ║  Heart toggles with scale bounce + particles            ║
// ╚══════════════════════════════════════════════════════════╝

private struct LikeButton: View {
    @State private var isLiked = false
    @State private var particles: [Particle] = []

    private struct Particle: Identifiable {
        let id = UUID()
        let angle: Double
        let distance: CGFloat
    }

    var body: some View {
        ZStack {
            ForEach(particles) { p in
                Circle()
                    .fill(Color.pink.opacity(0.6))
                    .frame(width: 6, height: 6)
                    .offset(
                        x: cos(p.angle) * p.distance,
                        y: sin(p.angle) * p.distance
                    )
                    .opacity(p.distance > 20 ? 0 : 1)
            }

            Button {
                withAnimation(Khagwal.bouncySpring) {
                    isLiked.toggle()
                    if isLiked {
                        spawnParticles()
                    }
                }
            } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(isLiked ? .pink : .secondary)
                    .frame(width: 52, height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: Khagwal.buttonRadius, style: .continuous)
                            .fill(isLiked ? Color.pink.opacity(0.1) : Khagwal.secondaryFill)
                    )
                    .contentTransition(.symbolEffect(.replace))
                    .scaleEffect(isLiked ? 1.1 : 1.0)
            }
        }
    }

    private func spawnParticles() {
        particles = (0..<8).map { i in
            Particle(angle: Double(i) * .pi / 4, distance: 0)
        }
        withAnimation(Khagwal.bouncySpring) {
            particles = particles.map { p in
                Particle(angle: p.angle, distance: 30)
            }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            withAnimation(Khagwal.spring) { particles = [] }
        }
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  16. NUMERIC STEPPER                                    ║
// ║  Inline +/- with morphing count display                 ║
// ╚══════════════════════════════════════════════════════════╝

private struct NumericStepper: View {
    @State private var value = 1

    var body: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(Khagwal.spring) { value = max(0, value - 1) }
            } label: {
                Image(systemName: "minus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(value > 0 ? .primary : .quaternary)
                    .frame(width: 44, height: 44)
            }
            .disabled(value <= 0)

            Text("\(value)")
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .frame(width: 44)
                .contentTransition(.numericText(value: Double(value)))

            Button {
                withAnimation(Khagwal.spring) { value += 1 }
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Khagwal.buttonRadius, style: .continuous)
                .fill(Khagwal.secondaryFill)
        )
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  17. HOLD-TO-CONFIRM                                    ║
// ║  Long press fills a ring, then confirms                 ║
// ╚══════════════════════════════════════════════════════════╝

private struct HoldToConfirm: View {
    @State private var isHolding = false
    @State private var isComplete = false
    @State private var holdProgress: CGFloat = 0
    @Namespace private var holdNS

    var body: some View {
        ZStack {
            if isComplete {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.bold))
                    Text("Confirmed")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .frame(height: 52)
                .background(
                    Capsule()
                        .fill(.black)
                        .matchedGeometryEffect(id: "hold-bg", in: holdNS)
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                ZStack {
                    // Track
                    Capsule()
                        .fill(Khagwal.subtleFill)
                        .matchedGeometryEffect(id: "hold-bg", in: holdNS)

                    // Fill
                    GeometryReader { geo in
                        Capsule()
                            .fill(.black)
                            .frame(width: geo.size.width * holdProgress)
                    }
                    .clipShape(Capsule())

                    Text(isHolding ? "Keep holding..." : "Hold to confirm")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(holdProgress > 0.5 ? .white : .primary)
                }
                .frame(width: 200, height: 52)
                .clipShape(Capsule())
                .gesture(
                    LongPressGesture(minimumDuration: 1.5)
                        .onChanged { _ in
                            isHolding = true
                            withAnimation(Animation.khagwal) {
                                holdProgress = 1.0
                            }
                        }
                        .onEnded { _ in
                            isHolding = false
                            withAnimation(Khagwal.bouncySpring) {
                                isComplete = true
                            }
                            Task {
                                try? await Task.sleep(for: .seconds(1.5))
                                withAnimation(Khagwal.spring) {
                                    isComplete = false
                                    holdProgress = 0
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { _ in
                            if !isComplete {
                                isHolding = false
                                withAnimation(Khagwal.spring) { holdProgress = 0 }
                            }
                        }
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(Khagwal.spring, value: isComplete)
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  18. MAGNETIC DOCK                                      ║
// ║  Icons magnify on hover/proximity like macOS Dock       ║
// ╚══════════════════════════════════════════════════════════╝

private struct MagneticDock: View {
    @State private var hoveredIndex: Int?

    private let apps: [(icon: String, color: Color)] = [
        ("message.fill", .green),
        ("envelope.fill", .blue),
        ("calendar", .red),
        ("map.fill", .green),
        ("music.note", .pink),
        ("gearshape.fill", .gray),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(apps.enumerated()), id: \.offset) { index, app in
                let isHovered = hoveredIndex == index
                let isNeighbor = hoveredIndex != nil && abs(index - (hoveredIndex ?? -10)) == 1
                let scale: CGFloat = isHovered ? 1.5 : isNeighbor ? 1.2 : 1.0

                VStack(spacing: 4) {
                    Image(systemName: app.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(app.color)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Khagwal.background)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(.black.opacity(0.06), lineWidth: 1)
                                )
                        )
                        .shadow(color: .black.opacity(isHovered ? 0.1 : 0.04), radius: isHovered ? 12 : 6, x: 0, y: isHovered ? 8 : 3)
                        .scaleEffect(scale)
                        .offset(y: isHovered ? -12 : isNeighbor ? -4 : 0)

                    Circle()
                        .fill(.black)
                        .frame(width: 4, height: 4)
                        .opacity(isHovered ? 1 : 0)
                        .scaleEffect(isHovered ? 1 : 0.3)
                }
                .frame(width: 50)
                .animation(Khagwal.bouncySpring, value: hoveredIndex)
                .onTapGesture {
                    withAnimation(Khagwal.bouncySpring) {
                        hoveredIndex = hoveredIndex == index ? nil : index
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .padding(.bottom, 4)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.05), radius: 20, x: 0, y: 10)
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  19. FLIP CARD                                          ║
// ║  3D rotation reveal of back content                     ║
// ╚══════════════════════════════════════════════════════════╝

private struct FlipCard: View {
    @State private var isFlipped = false

    var body: some View {
        ZStack {
            // Back
            VStack(spacing: 10) {
                Image(systemName: "qrcode")
                    .font(.system(size: 44))
                    .foregroundStyle(.primary)
                Text("Scan to connect")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .background(Khagwal.background)
            .clipShape(RoundedRectangle(cornerRadius: Khagwal.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Khagwal.cardRadius, style: .continuous)
                    .stroke(.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 16, x: 0, y: 8)
            .rotation3DEffect(.degrees(isFlipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
            .opacity(isFlipped ? 1 : 0)

            // Front
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Premium")
                            .font(.title3.weight(.bold))
                            .tracking(-0.3)
                        Text("Active membership")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "crown.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                }

                Spacer()

                HStack {
                    Text("**** 4289")
                        .font(.footnote.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Tap to flip")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .background(.black)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: Khagwal.cardRadius, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
            .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            .opacity(isFlipped ? 0 : 1)
        }
        .onTapGesture {
            withAnimation(Khagwal.spring) { isFlipped.toggle() }
        }
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  20. ELASTIC SLIDER                                     ║
// ║  Thumb overshoots with spring, track fills fluidly      ║
// ╚══════════════════════════════════════════════════════════╝

private struct ElasticSlider: View {
    @State private var value: CGFloat = 0.4
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "speaker.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                GeometryReader { geo in
                    let width = geo.size.width
                    ZStack(alignment: .leading) {
                        // Track
                        Capsule()
                            .fill(Khagwal.subtleFill)
                            .frame(height: isDragging ? 10 : 6)

                        // Fill
                        Capsule()
                            .fill(.black)
                            .frame(width: width * value, height: isDragging ? 10 : 6)

                        // Thumb
                        Circle()
                            .fill(Khagwal.background)
                            .frame(width: isDragging ? 28 : 22, height: isDragging ? 28 : 22)
                            .overlay(
                                Circle().stroke(.black.opacity(0.08), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.1), radius: isDragging ? 8 : 4, x: 0, y: 2)
                            .offset(x: width * value - (isDragging ? 14 : 11))
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { drag in
                                        withAnimation(Khagwal.spring) { isDragging = true }
                                        let newValue = drag.location.x / width
                                        value = min(max(newValue, 0), 1)
                                    }
                                    .onEnded { _ in
                                        withAnimation(Khagwal.bouncySpring) { isDragging = false }
                                    }
                            )
                    }
                    .frame(height: 28)
                    .animation(Khagwal.spring, value: isDragging)
                }
                .frame(height: 28)

                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("\(Int(value * 100))%")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(value: Double(value)))
                .animation(Khagwal.spring, value: value)
        }
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  21. BREATHING ORBS                                     ║
// ║  Ambient pulsing circles, tap to spawn more             ║
// ╚══════════════════════════════════════════════════════════╝

private struct BreathingOrbs: View {
    @State private var breathe = false
    @State private var orbs: [Orb] = [
        Orb(x: 0.3, y: 0.4, size: 80, hue: 0.6),
        Orb(x: 0.7, y: 0.3, size: 60, hue: 0.8),
        Orb(x: 0.5, y: 0.7, size: 70, hue: 0.0),
    ]

    private struct Orb: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat
        var hue: Double
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(orbs.enumerated()), id: \.element.id) { index, orb in
                    Circle()
                        .fill(
                            Color(hue: orb.hue, saturation: 0.3, brightness: 0.95)
                                .gradient
                        )
                        .frame(width: orb.size, height: orb.size)
                        .blur(radius: 20)
                        .opacity(0.6)
                        .scaleEffect(breathe ? 1.15 : 0.85)
                        .offset(
                            x: orb.x * geo.size.width - geo.size.width / 2,
                            y: orb.y * geo.size.height - geo.size.height / 2
                        )
                        .animation({
                            let base: Animation = .khagwalBouncy
                            return base.repeatForever(autoreverses: true).delay(Double(index) * 0.4)
                        }(),
                            value: breathe
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { location in
                let newOrb = Orb(
                    x: location.x / geo.size.width,
                    y: location.y / geo.size.height,
                    size: CGFloat.random(in: 40...90),
                    hue: Double.random(in: 0...1)
                )
                withAnimation(Khagwal.bouncySpring) {
                    orbs.append(newOrb)
                }
                if orbs.count > 8 {
                    withAnimation(Khagwal.spring) {
                        orbs.removeFirst()
                    }
                }
            }
        }
        .frame(height: 180)
        .background(Khagwal.background)
        .clipShape(RoundedRectangle(cornerRadius: Khagwal.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Khagwal.cardRadius, style: .continuous)
                .stroke(.black.opacity(0.04), lineWidth: 1)
        )
        .onAppear { breathe = true }
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  22. REACTION PICKER                                    ║
// ║  iMessage-style reaction bar with scale + bounce        ║
// ╚══════════════════════════════════════════════════════════╝

private struct ReactionPicker: View {
    @State private var selected: String?
    @State private var showPicker = false

    private let reactions = ["😍", "😂", "👍", "🔥", "😮", "❤️"]

    var body: some View {
        VStack(spacing: 16) {
            // Message bubble
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("Check out these new components!")
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if let selected {
                        Text(selected)
                            .font(.title3)
                            .padding(4)
                            .background(
                                Circle()
                                    .fill(Khagwal.background)
                                    .overlay(Circle().stroke(.black.opacity(0.06), lineWidth: 1))
                            )
                            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 3)
                            .transition(.scale(scale: 0).combined(with: .opacity))
                            .offset(x: -8, y: -8)
                    }
                }
            }
            .onTapGesture {
                withAnimation(Khagwal.bouncySpring) { showPicker.toggle() }
            }

            // Picker bar
            if showPicker {
                HStack(spacing: 4) {
                    ForEach(Array(reactions.enumerated()), id: \.offset) { index, emoji in
                        Button {
                            withAnimation(Khagwal.bouncySpring) {
                                selected = emoji
                                showPicker = false
                            }
                        } label: {
                            Text(emoji)
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .scaleEffect(selected == emoji ? 1.3 : 1.0)
                        }
                        .transition(
                            .scale(scale: 0.1)
                                .combined(with: .opacity)
                                .animation(Khagwal.bouncySpring.delay(Double(index) * 0.04))
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Khagwal.background)
                        .overlay(Capsule().stroke(.black.opacity(0.06), lineWidth: 1))
                )
                .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 8)
                .transition(.scale(scale: 0.5, anchor: .bottom).combined(with: .opacity))
            }
        }
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  23. PARALLAX CARD STACK                                ║
// ║  Layered cards that shift with drag for depth           ║
// ╚══════════════════════════════════════════════════════════╝

private struct ParallaxCardStack: View {
    @State private var dragOffset: CGSize = .zero

    private let layers: [(color: Color, icon: String, offset: CGFloat)] = [
        (.black.opacity(0.03), "circle.fill", 0.15),
        (.black.opacity(0.06), "triangle.fill", 0.3),
        (.black, "star.fill", 0.5),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(layers.enumerated()), id: \.offset) { index, layer in
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(index == layers.count - 1 ? layer.color : Khagwal.background)
                    .overlay(
                        Group {
                            if index < layers.count - 1 {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(.black.opacity(0.04), lineWidth: 1)
                            }
                        }
                    )
                    .frame(height: 140)
                    .overlay(
                        Image(systemName: layer.icon)
                            .font(.title.weight(.semibold))
                            .foregroundStyle(index == layers.count - 1 ? .white : .black.opacity(0.15))
                    )
                    .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 6)
                    .offset(
                        x: dragOffset.width * layer.offset,
                        y: dragOffset.height * layer.offset * 0.5 - CGFloat(layers.count - 1 - index) * 8
                    )
                    .scaleEffect(1.0 - CGFloat(layers.count - 1 - index) * 0.04)
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = CGSize(
                        width: value.translation.width * 0.4,
                        height: value.translation.height * 0.4
                    )
                }
                .onEnded { _ in
                    withAnimation(Khagwal.bouncySpring) { dragOffset = .zero }
                }
        )
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  24. MORPH TABS                                         ║
// ║  Tab bar where icon + label morph on selection          ║
// ╚══════════════════════════════════════════════════════════╝

private struct MorphTabs: View {
    @State private var selected = 0
    @Namespace private var tabNS

    private let tabs: [(icon: String, label: String)] = [
        ("house.fill", "Home"),
        ("magnifyingglass", "Search"),
        ("heart.fill", "Likes"),
        ("person.fill", "Profile"),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                Button {
                    withAnimation(Khagwal.spring) { selected = index }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.body.weight(.semibold))
                            .symbolRenderingMode(.hierarchical)

                        if selected == index {
                            Text(tab.label)
                                .font(.subheadline.weight(.semibold))
                                .transition(.scale(scale: 0.5, anchor: .leading).combined(with: .opacity))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(selected == index ? .white : .secondary)
                    .padding(.horizontal, selected == index ? 16 : 12)
                    .frame(height: 44)
                    .background {
                        if selected == index {
                            Capsule()
                                .fill(.black)
                                .matchedGeometryEffect(id: "tab-bg", in: tabNS)
                        }
                    }
                }
            }
        }
        .padding(6)
        .background(
            Capsule()
                .fill(Khagwal.subtleFill)
        )
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  25. SWIPE ACTIONS ROW                                  ║
// ║  Horizontal swipe reveals action buttons behind         ║
// ╚══════════════════════════════════════════════════════════╝

private struct SwipeActionsRow: View {
    @State private var offset: CGFloat = 0
    @State private var actionTriggered: String?

    var body: some View {
        ZStack(alignment: .trailing) {
            // Revealed actions
            HStack(spacing: 0) {
                Spacer()
                Button {
                    withAnimation(Khagwal.spring) {
                        actionTriggered = "archive"
                        offset = 0
                    }
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        withAnimation(Khagwal.spring) { actionTriggered = nil }
                    }
                } label: {
                    Image(systemName: "archivebox.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 64)
                        .background(Color.orange)
                }

                Button {
                    withAnimation(Khagwal.spring) {
                        actionTriggered = "delete"
                        offset = 0
                    }
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        withAnimation(Khagwal.spring) { actionTriggered = nil }
                    }
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 64)
                        .background(Color.red)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Main row content
            HStack(spacing: 14) {
                Circle()
                    .fill(.black)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "envelope.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(actionTriggered == "archive" ? "Archived!" : actionTriggered == "delete" ? "Deleted!" : "Swipe me left")
                        .font(.subheadline.weight(.semibold))
                    Text("Reveal hidden actions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("2m")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 64)
            .background(Khagwal.background)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
            .offset(x: offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let drag = value.translation.width
                        offset = drag < 0 ? max(drag, -130) : drag * 0.2
                    }
                    .onEnded { value in
                        withAnimation(Khagwal.spring) {
                            offset = value.translation.width < -50 ? -120 : 0
                        }
                    }
            )
        }
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  26. ORBIT LOADER                                       ║
// ║  Dots orbit in a circle — custom loading indicator      ║
// ╚══════════════════════════════════════════════════════════╝

private struct OrbitLoader: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .fill(.black)
                    .frame(width: CGFloat(10 - index), height: CGFloat(10 - index))
                    .offset(y: -20)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation({
                        let base: Animation = .khagwal
                        return base.repeatForever(autoreverses: false).delay(Double(index) * 0.1)
                    }(),
                        value: isAnimating
                    )
            }
        }
        .frame(width: 52, height: 52)
        .onAppear { isAnimating = true }
    }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  MAIN PREVIEW VIEW                                      ║
// ╚══════════════════════════════════════════════════════════╝

struct KhagwalPreviewView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 44) {
                // Header
                VStack(spacing: 6) {
                    Text("Khagwal")
                        .font(.largeTitle.weight(.bold))
                        .tracking(-1)
                    Text("Smooth & Simple")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                }
                .padding(.top, 24)

                // 1. Glassmorphic Cards
                section("Glassmorphic Cards") {
                    VStack(spacing: 10) {
                        SampleCard(title: "Documents", subtitle: "23 files", icon: "doc.text")
                        SampleCard(title: "Photos", subtitle: "148 items", icon: "photo")
                        SampleCard(title: "Notes", subtitle: "12 entries", icon: "note.text")
                    }
                }

                // 2. Morphing Button
                section("Morphing Button", hint: "Tap + to expand, then tap an icon") {
                    MorphingActionButton()
                        .frame(height: 70)
                }

                // 3. Split Delete
                section("Progressive Disclosure", hint: "Tap trash to split") {
                    SplitDeleteButton()
                        .frame(height: 56)
                }

                // 4. Fan Menu
                section("Fan Menu", hint: "Tap to fan out") {
                    FanMenu()
                }

                // 5. Contextual Toolbar
                section("Contextual Toolbar", hint: "Switch modes to swap tools") {
                    ContextualToolbar()
                        .khagwalCard()
                }

                // 6. Inline Copy
                section("Inline Feedback", hint: "Tap to copy") {
                    InlineCopyButton()
                }

                // 7. Toggle Pill
                section("Segmented Pill", hint: "Sliding background indicator") {
                    TogglePill()
                }

                // 8. Expandable Search
                section("Expandable Search", hint: "Tap to morph into text field") {
                    ExpandableSearchBar()
                }

                // 9. Notification Badge
                section("Notification Badge", hint: "Tap bell to increment") {
                    NotificationBadge()
                }

                // 10. Progress Morph
                section("Progress Morph", hint: "Button → ring → checkmark") {
                    ProgressMorphButton()
                        .frame(height: 60)
                }

                // 11. Like Button
                section("Like with Particles", hint: "Tap to toggle") {
                    HStack(spacing: 20) {
                        LikeButton()
                        NumericStepper()
                    }
                }

                // 12. Stacked Avatars
                section("Stacked Avatars", hint: "Tap to fan out") {
                    StackedAvatars()
                }

                // 13. Draggable Card
                section("Drag to Dismiss", hint: "Swipe the card up") {
                    DraggableCard()
                        .padding(.horizontal, 4)
                }

                // 14. Accordion
                section("Accordion List", hint: "Tap rows to expand") {
                    AccordionList()
                }

                // 15. Floating Toast
                section("Floating Toast", hint: "Non-disruptive feedback") {
                    FloatingToastDemo()
                        .frame(height: 100)
                }

                // 16. Hold to Confirm
                section("Hold to Confirm", hint: "Long press to fill and confirm") {
                    HoldToConfirm()
                }

                // 17. Magnetic Dock
                section("Magnetic Dock", hint: "Tap icons to magnify") {
                    MagneticDock()
                }

                // 18. Flip Card
                section("3D Flip Card", hint: "Tap to flip over") {
                    FlipCard()
                }

                // 19. Elastic Slider
                section("Elastic Slider", hint: "Drag the thumb") {
                    ElasticSlider()
                }

                // 20. Breathing Orbs
                section("Breathing Orbs", hint: "Ambient pulse, tap to spawn") {
                    BreathingOrbs()
                }

                // 21. Reaction Picker
                section("Reaction Picker", hint: "Tap bubble, pick a reaction") {
                    ReactionPicker()
                }

                // 22. Parallax Card Stack
                section("Parallax Cards", hint: "Drag to shift layers") {
                    ParallaxCardStack()
                        .frame(height: 170)
                }

                // 23. Morph Tabs
                section("Morph Tab Bar", hint: "Tap tabs to morph") {
                    MorphTabs()
                }

                // 24. Swipe Actions
                section("Swipe Actions", hint: "Swipe left to reveal") {
                    SwipeActionsRow()
                }

                // 25. Orbit Loader
                section("Orbit Loader", hint: "Custom loading indicator") {
                    OrbitLoader()
                        .frame(height: 60)
                }

                Spacer(minLength: 60)
            }
            .padding(.horizontal, 24)
        }
        .background(Khagwal.background)
        .buttonStyle(KhagwalButtonStyle())
    }

    // MARK: - Section Builder

    private func section<Content: View>(
        _ title: String,
        hint: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                HStack {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                }
                if let hint {
                    HStack {
                        Text(hint)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                }
            }

            content()
        }
    }
}

// MARK: - Preview

#Preview("Khagwal Design System") {
    KhagwalPreviewView()
}
