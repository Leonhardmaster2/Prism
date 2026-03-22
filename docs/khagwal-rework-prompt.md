# UI Rework: Khagwal Design System — Claude Code Prompt

You are reworking the entire UI of this SwiftUI application to follow the **Khagwal Design System** — a "Soft Minimalism" aesthetic with "Physical Fluidity." This is a full visual overhaul. Every single view, component, and interaction must be touched. Do NOT skip files. Do NOT leave partial implementations.

---

## PHASE 0: SETUP — Read Before Touching Anything

1. **Read the full project tree** — list every `.swift` file, especially Views, Components, and any existing design system files.
2. **Create a shared design system file** (`KhagwalDesignSystem.swift`) containing ALL reusable constants, extensions, and helper views defined below. Every view in the app imports from this file — no inline magic numbers.
3. **Create a checklist** of every view file you find. After modifying each one, mark it done. At the end, verify nothing was skipped.

---

## PHASE 1: Design System Foundation (`KhagwalDesignSystem.swift`)

Create this file with ALL of the following. Do not omit any section.

### 1.1 Color Constants

```swift
enum KColors {
    static let canvas = Color.white                          // #FFFFFF — base layer, always
    static let primaryAction = Color.black                   // #000000 — buttons, active states
    static let secondarySurface = Color.primary.opacity(0.05) // inactive buttons, subtle containers
    static let border = Color.primary.opacity(0.1)           // hairline strokes
    static let shadowColor = Color.black.opacity(0.05)       // ambient shadow
    static let disabledOpacity: Double = 0.5
}
```

### 1.2 Spacing Constants (4pt Grid — mandatory)

```swift
enum KSpacing {
    static let nano: CGFloat = 8      // 2x — icon-to-label, tight grouping
    static let micro: CGFloat = 16    // 4x — related elements within a section
    static let standard: CGFloat = 24 // 6x — screen padding / margins
    static let macro: CGFloat = 32    // 8x — between distinct sections
    static let jumbo: CGFloat = 40    // 10x — large section gaps
}
```

### 1.3 Corner Radii (ALL must use `.continuous` style)

```swift
enum KRadius {
    static let small: CGFloat = 12    // chips, inline inputs
    static let medium: CGFloat = 18   // standard action buttons
    static let large: CGFloat = 28    // cards, floating panels
}
```

**CRITICAL RULE**: Every `RoundedRectangle` in the entire app MUST use `style: .continuous`. Search-and-replace any existing `RoundedRectangle(cornerRadius: X)` that lacks `.continuous`.

### 1.4 Spring Animations (NO easeIn/easeOut/linear ANYWHERE)

```swift
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
```

**CRITICAL RULE**: After creating these, do a **project-wide search** for `.easeIn`, `.easeOut`, `.easeInOut`, `.linear`, and `Animation.default`. Replace ALL of them with the appropriate khagwal spring. Zero exceptions.

### 1.5 Shadow Modifier

```swift
extension View {
    func khagwalShadow() -> some View {
        self.shadow(color: .black.opacity(0.04), radius: 16, x: 0, y: 8)
    }
}
```

### 1.6 Haptic Helper

```swift
enum KHaptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
```

### 1.7 Adaptive Container (reusable wrapper)

```swift
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
```

### 1.8 Typography Helpers

```swift
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
```

---

## PHASE 2: Global Replacements (Do These First, Across ALL Files)

Run these replacements **before** doing per-view work. This prevents you from forgetting them later.

| Find (regex-safe) | Replace With | Why |
|---|---|---|
| `RoundedRectangle(cornerRadius:` (without `.continuous`) | Add `, style: .continuous)` | Squircle rule |
| `.easeIn`, `.easeOut`, `.easeInOut`, `.linear` (in animation context) | `.khagwal` (or `.khagwalSnappy` / `.khagwalBouncy` as appropriate) | No standard easing |
| `.sheet(` / `.fullScreenCover(` / `.alert(` for custom UI | Replace with ZStack overlay + `matchedGeometryEffect` | Physical continuity rule |
| Hardcoded padding numbers | Replace with `KSpacing.*` constants | 4pt grid |
| Hardcoded corner radius numbers | Replace with `KRadius.*` constants | Consistency |
| Any gray background on root views (e.g. `Color(.systemGroupedBackground)`) | `KColors.canvas` (pure white) | White canvas rule |
| Inline shadow values | `.khagwalShadow()` | Consistent elevation |

---

## PHASE 3: Per-View Rework Checklist

For **every single view** in the project, apply ALL of the following. Do not skip any view.

### Background & Surface
- [ ] Root background is `KColors.canvas` (pure white `#FFFFFF`) — no gray, no systemBackground
- [ ] Content sections wrapped in `KContainer` where appropriate (floating island look)
- [ ] Glass layers (floating headers, context bars) use `.ultraThinMaterial`
- [ ] No edge-to-edge containers unless it's a full-screen transition

### Typography
- [ ] All titles use `.khagwalTitle()` (bold, negative tracking)
- [ ] Headlines use `.khagwalHeadline()`
- [ ] Body text uses `.khagwalBody()`
- [ ] Captions use `.khagwalCaption()`
- [ ] NO hardcoded font sizes without using the helpers

### Spacing
- [ ] Screen margins: `KSpacing.standard` (24pt)
- [ ] Section gaps: `KSpacing.macro` (32pt) or `KSpacing.jumbo` (40pt)
- [ ] Related element spacing: `KSpacing.micro` (16pt)
- [ ] Icon-to-label / tight groups: `KSpacing.nano` (8pt)
- [ ] ALL spacing values are multiples of 4

### Corners & Shapes
- [ ] Every `RoundedRectangle` uses `style: .continuous`
- [ ] Large cards: `KRadius.large`
- [ ] Buttons: `KRadius.medium`
- [ ] Chips/small inputs: `KRadius.small`

### Shadows & Borders
- [ ] Floating elements have `.khagwalShadow()`
- [ ] Container borders use `KColors.border` (0.1 opacity stroke)
- [ ] No heavy drop shadows anywhere

### Animation
- [ ] ALL `withAnimation` blocks use `.khagwal`, `.khagwalBouncy`, or `.khagwalSnappy`
- [ ] NO standard easing curves remain
- [ ] State transitions that change shape/size use `matchedGeometryEffect` with `@Namespace`
- [ ] Staggered entrances for lists: `delay(Double(index) * 0.05)`
- [ ] Content inside morphing containers uses `.transition(.opacity)` with slight delay

### Interaction & Feedback
- [ ] All buttons call `KHaptics.light()` on tap
- [ ] Pressed state: `.scaleEffect(0.98)` with `.khagwalSnappy`
- [ ] Disabled state: `.opacity(KColors.disabledOpacity)`
- [ ] Min touch target: 44x44pt
- [ ] Interactive elements have clear default/pressed/active/disabled states

### Icons
- [ ] All icons are SF Symbols
- [ ] Prefer `.hierarchical` rendering mode
- [ ] Active states use `.symbolVariant(.fill)`

### Overlays & Modals
- [ ] Custom overlays use `ZStack`, NOT `.sheet` / `.fullScreenCover` / `.alert`
- [ ] Expanding elements have higher `.zIndex`
- [ ] Expanding containers use `.clipped()` and `.contentShape(Rectangle())`
- [ ] Background shape animates first, content fades in with 0.05–0.1s delay

### Navigation
- [ ] If using floating headers: `HStack` pinned to top with `.ultraThinMaterial` (only on scroll)
- [ ] ScrollView content respects safe areas properly

---

## PHASE 4: Verification

After all views are modified:

1. **Search the entire project** for violations:
   - `grep -rn "easeIn\|easeOut\|easeInOut\|\.linear" --include="*.swift"` → must return 0 results
   - `grep -rn "RoundedRectangle(cornerRadius:" --include="*.swift"` → every hit must have `.continuous`
   - `grep -rn "\.sheet(\|\.fullScreenCover(\|\.alert(" --include="*.swift"` → only system alerts allowed, no custom UI
   - `grep -rn "systemGroupedBackground\|systemBackground" --include="*.swift"` → must return 0 results

2. **Verify the file checklist** — every `.swift` view file found in Phase 0 must be marked as modified.

3. **List any files you did NOT modify** and explain why (e.g., pure model files with no UI).

---

## RULES OF ENGAGEMENT

- **Do NOT skip files.** If a view exists, it gets reworked.
- **Do NOT leave TODOs.** Every change is implemented fully.
- **Do NOT use hardcoded values.** Everything references `KSpacing`, `KRadius`, `KColors`, or the animation extensions.
- **Do NOT mix old and new styles.** If one button is updated, ALL buttons in that file are updated.
- **Do NOT forget haptics.** Every button, every toggle, every meaningful interaction.
- **Work file by file.** Open each file, apply the full checklist, close it, move to next.
- **After finishing all files**, run the Phase 4 verification grep commands and fix any remaining violations.
