import SwiftUI

struct SettingsSheet: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: KSpacing.standard) {
            // Header
            HStack {
                Text("Settings")
                    .khagwalTitle()
                Spacer()
                Button {
                    KHaptics.light()
                    withAnimation(.khagwal) {
                        appState.showSettings = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            // Appearance section
            VStack(alignment: .leading, spacing: KSpacing.nano) {
                Text("Appearance")
                    .khagwalHeadline()

                HStack(spacing: KSpacing.nano) {
                    ForEach([AppearanceMode.system, .light, .dark], id: \.rawValue) { mode in
                        let isSelected = appState.appearanceMode == mode

                        Button {
                            KHaptics.light()
                            withAnimation(.khagwalSnappy) {
                                appState.appearanceMode = mode
                            }
                        } label: {
                            VStack(spacing: KSpacing.nano) {
                                Image(systemName: iconForMode(mode))
                                    .symbolRenderingMode(.hierarchical)
                                    .symbolVariant(isSelected ? .fill : .none)
                                    .font(.title3)
                                Text(labelForMode(mode))
                                    .font(.caption.weight(.medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, KSpacing.micro)
                            .background(
                                isSelected ? KColors.primaryAction.opacity(0.08) : KColors.secondarySurface,
                                in: RoundedRectangle(cornerRadius: KRadius.small, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: KRadius.small, style: .continuous)
                                    .stroke(isSelected ? KColors.primaryAction.opacity(0.2) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()
        }
        .padding(KSpacing.standard)
        .background(KColors.canvas)
    }

    private func iconForMode(_ mode: AppearanceMode) -> String {
        switch mode {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    private func labelForMode(_ mode: AppearanceMode) -> String {
        switch mode {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}
