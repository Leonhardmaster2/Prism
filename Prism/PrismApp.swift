import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@main
struct PrismApp: App {
    @State private var appState = AppState()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PrismDocument.self,
            Workspace.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        if let path = try? DocumentStorage.shared.getDocumentsDirectory().path {
            print("[PRISM] Documents directory: \(path)")
        }

        // Debug: verify bundled editor resources
        let resources = ["editor.html", "editor.css", "editor.js", "milkdown-bundle.js"]
        for name in resources {
            let parts = name.split(separator: ".")
            let url = Bundle.main.url(forResource: String(parts[0]), withExtension: String(parts[1]))
            print("[PRISM] Resource \(name): \(url?.path ?? "NOT FOUND")")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                #if os(macOS)
                .frame(minWidth: 700, minHeight: 500)
                #endif
                .fileImporter(
                    isPresented: Binding(
                        get: { appState.showImporter },
                        set: { appState.showImporter = $0 }
                    ),
                    allowedContentTypes: [.plainText],
                    allowsMultipleSelection: true
                ) { result in
                    handleImport(result)
                }
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
        .commands {
            PrismCommands(appState: appState, modelContainer: sharedModelContainer)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let context = ModelContext(sharedModelContainer)
            let service = DocumentService(modelContext: context)
            var lastImported: PrismDocument?
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    let doc = try service.importMarkdown(from: url)
                    lastImported = doc
                    print("[PRISM] Imported: \(url.lastPathComponent)")
                } catch {
                    print("[PRISM] Import failed for \(url.lastPathComponent): \(error)")
                }
            }
            if let doc = lastImported {
                appState.selectedDocumentID = doc.id
            }
        case .failure(let error):
            print("[PRISM] File picker error: \(error)")
        }
    }
}

struct PrismCommands: Commands {
    let appState: AppState
    let modelContainer: ModelContainer

    var body: some Commands {
        // Cmd+N — New Document
        CommandGroup(replacing: .newItem) {
            Button("New Document") {
                let context = ModelContext(modelContainer)
                let service = DocumentService(modelContext: context)
                do {
                    let document = try service.createDocument(title: "Untitled")
                    appState.selectedDocumentID = document.id
                } catch {
                    print("[PRISM] Failed to create document: \(error)")
                }
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Import Markdown...") {
                appState.showImporter = true
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        CommandGroup(after: .toolbar) {
            // Cmd+0 — Toggle sidebar
            Button("Toggle Sidebar") {
                appState.toggleSidebar()
            }
            .keyboardShortcut("0", modifiers: .command)

            // Cmd+Shift+F — Focus search
            Button("Find in Documents") {
                if !appState.isSidebarExpanded {
                    appState.toggleSidebar()
                }
                appState.isSearchFocused = true
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
        }

        // Cmd+W — Deselect document
        CommandGroup(replacing: .saveItem) {
            Button("Close Document") {
                appState.selectedDocumentID = nil
            }
            .keyboardShortcut("w", modifiers: .command)

            Button("Toggle Reading Mode") {
                appState.isReadingMode.toggle()
            }
            .keyboardShortcut(".", modifiers: .command)
        }

        // Cmd+, — Settings
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                appState.showSettings = true
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
