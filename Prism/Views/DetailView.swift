import SwiftUI
import SwiftData

private struct VideoItem: Identifiable {
    let id: String
}

struct DetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query private var allDocuments: [PrismDocument]
    @State private var editorState = EditorStateInfo()
    @State private var bridge = EditorBridge()

    var body: some View {
        if allDocuments.isEmpty {
            welcomeState
        } else if let selectedID = appState.selectedDocumentID,
                  let document = allDocuments.first(where: { $0.id == selectedID }) {
            editorArea(document)
        } else {
            emptyState
        }
    }

    private func editorArea(_ document: PrismDocument) -> some View {
        let isDark: Bool = {
            switch appState.appearanceMode {
            case .dark: return true
            case .light: return false
            case .system: return false
            }
        }()

        return ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                EditorView(
                    document: document,
                    isDarkMode: isDark,
                    isReadingMode: appState.isReadingMode,
                    bridge: bridge,
                    onContentChanged: { markdown, wordCount in
                        handleContentChanged(document: document, markdown: markdown, wordCount: wordCount)
                    },
                    onStateChanged: { info in
                        editorState = info
                    }
                )

                // Metadata bar
                HStack(spacing: 12) {
                    Text("\(document.wordCount) words")
                    Text(document.modifiedAt, style: .relative)
                }
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(.bar)
            }

            // Formatting toolbar — visible only in editing mode
            if !appState.isReadingMode {
                FormattingToolbar(
                    editorState: editorState,
                    onCommand: { command, payload in
                        print("[TOOLBAR] Executing: \(command) payload: \(String(describing: payload))")
                        bridge.executeCommand(command, payload: payload)
                    }
                )
                .padding(.bottom, 28) // above the metadata bar
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            bridge.onSaveRequested = { [weak modelContext] in
                guard let ctx = modelContext else { return }
                let service = DocumentService(modelContext: ctx)
                bridge.getCurrentContent { markdown in
                    let wordCount = markdown.split(whereSeparator: \.isWhitespace).count
                    do {
                        try service.updateContent(document, content: markdown, wordCount: wordCount)
                        print("[PRISM] Saved via Cmd+S")
                    } catch {
                        print("[PRISM] Save failed: \(error)")
                    }
                }
            }
        }
    }

    private func handleContentChanged(document: PrismDocument, markdown: String, wordCount: Int) {
        // Save content to disk (doesn't trigger SwiftUI re-render)
        let service = DocumentService(modelContext: modelContext)
        do {
            try service.updateContent(document, content: markdown, wordCount: wordCount)
        } catch {
            print("[PRISM] Failed to save content: \(error)")
        }

        // Update title only if actually different — avoid unnecessary SwiftData mutations
        let title = extractTitle(from: markdown)
        if title != document.title {
            // Debounce title updates to avoid feedback loops
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak modelContext] in
                guard let ctx = modelContext else { return }
                if title != document.title {
                    document.title = title
                    try? ctx.save()
                }
            }
        }
    }

    private func extractTitle(from markdown: String) -> String {
        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                let title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { return title }
            }
        }
        return "Untitled"
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("Select a document or create a new one")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            Button {
                createDocument()
            } label: {
                Text("New Document")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var welcomeState: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Welcome to Prism")
                .font(.system(size: 28, weight: .bold))
            Text("Your notes, beautifully rendered")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            Button {
                createDocument()
            } label: {
                Text("Create your first document")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func createDocument() {
        let service = DocumentService(modelContext: modelContext)
        do {
            let document = try service.createDocument(title: "Untitled")
            appState.selectedDocumentID = document.id
        } catch {
            print("[PRISM] Failed to create document: \(error)")
        }
    }
}
