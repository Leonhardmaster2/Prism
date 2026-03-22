import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()

            DetailView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.all, edges: .top)
        .sheet(isPresented: Binding(
            get: { appState.showSettings },
            set: { appState.showSettings = $0 }
        )) {
            SettingsSheet()
        }
        .preferredColorScheme(appState.appearanceMode.colorScheme)
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .modelContainer(for: [PrismDocument.self, Workspace.self], inMemory: true)
}
