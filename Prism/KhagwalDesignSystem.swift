import SwiftUI

// MARK: - Khagwal Design System
// "Soft Minimalism" with "Physical Fluidity"
// Every view imports from this file — no inline magic numbers.

// MARK: 1.1 — Color Constants

enum KColors {
    static let canvas = Color.white                            // #FFFFFF — base layer, always
    static let primaryAction = Color.black                     // #000000 — buttons, active states
    static let secondarySurface = Color.primary.opacity(0.05)  // inactive buttons, subtle containers
    static let border = Color.primary.opacity(0.1)             // hairline strokes
    static let shadowColor = Color.black.opacity(0.05)         // ambient shadow
    static let disabledOpacity: Double = 0.5
}

// MARK: 1.2 — Spacing Constants (4pt Grid)

enum KSpacing {
    static let nano: CGFloat = 8       // 2x — icon-to-label, tight grouping
    static let micro: CGFloat = 16     // 4x — related elements within a section
    static let standard: CGFloat = 24  // 6x — screen padding / margins
    static let macro: CGFloat = 32     // 8x — between distinct sections
    static let jumbo: CGFloat = 40     // 10x — large section gaps
}

// MARK: 1.3 — Corner Radii (ALL use .continuous style)

enum KRadius {
    static let small: CGFloat = 12     // chips, inline inputs
    static let medium: CGFloat = 18    // standard action buttons
    static let large: CGFloat = 28     // cards, floating panels
}

// MARK: 1.4 — Spring Animations (NO easeIn/easeOut/linear ANYWHERE)

extension Animation {
    /// Default for all UI transitions
    static var khagwal: Animation {
        .spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0)
    }
    /// Playful / bouncy (fan menus, drag release)
    static var khagwalBouncy: Animation {
        .spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0)
    }
    /// Quick snap feedback (checkmarks, highlights)
    static var khagwalSnappy: Animation {
        .spring(response: 0.2, dampingFraction: 0.9, blendDuration: 0)
    }
}

// MARK: 1.5 — Shadow Modifier

extension View {
    func khagwalShadow() -> some View {
        self.shadow(color: .black.opacity(0.04), radius: 16, x: 0, y: 8)
    }
}

// MARK: 1.6 — Haptic Helper

enum KHaptics {
    static func light() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    static func medium() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}

// MARK: 1.7 — Adaptive Container

struct KContainer<Content: View>: View {
    var padding: CGFloat
    var cornerRadius: CGFloat
    var content: Content

    init(padding: CGFloat = KSpacing.micro, cornerRadius: CGFloat = KRadius.large, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .khagwalShadow()
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(KColors.border, lineWidth: 1)
            )
    }
}

// MARK: 1.8 — Typography Helpers

extension View {
    func khagwalTitle() -> some View {
        self.font(.title2.weight(.bold)).tracking(-0.5)
    }
    func khagwalHeadline() -> some View {
        self.font(.headline.weight(.semibold)).tracking(-0.3)
    }
    func khagwalBody() -> some View {
        self.font(.body.weight(.regular))
    }
    func khagwalCaption() -> some View {
        self.font(.caption.weight(.regular)).foregroundStyle(.secondary)
    }
}
