import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Namespace private var settingsNS

    var body: some View {
        ZStack {
            KColors.canvas
                .ignoresSafeArea()

            HStack(spacing: 0) {
                SidebarView()

                DetailView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea(.all, edges: .top)

            // Settings overlay (replaces .sheet for physical continuity)
            if appState.showSettings {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.khagwal) {
                            appState.showSettings = false
                        }
                    }
                    .transition(.opacity)

                SettingsSheet()
                    .frame(maxWidth: 420, maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: KRadius.large, style: .continuous))
                    .khagwalShadow()
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.khagwal, value: appState.showSettings)
        .preferredColorScheme(appState.appearanceMode.colorScheme)
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .modelContainer(for: [PrismDocument.self, Workspace.self], inMemory: true)
}
