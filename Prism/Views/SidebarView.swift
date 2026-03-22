import SwiftUI
import SwiftData

struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState
    @Query(sort: \PrismDocument.modifiedAt, order: .reverse) private var allDocuments: [PrismDocument]
    @Query(sort: \Workspace.sortOrder) private var workspaces: [Workspace]

    @State private var editingFolderID: UUID?
    @State private var editingFolderName: String = ""
    @State private var renamingDocumentID: UUID?
    @State private var renamingDocumentTitle: String = ""
    @State private var documentToDelete: PrismDocument?
    @State private var folderToDelete: Workspace?
    @State private var contentCache: [UUID: String] = [:]
    @State private var expandedFolders: Set<UUID> = []
    @State private var hoveredItemID: String?
    @State private var dropTargetFolderID: UUID?

    // MARK: - Adaptive Colors

    private var colors: SidebarColorSet { SidebarColorSet(scheme: colorScheme) }

    var body: some View {
        Group {
            if appState.isSidebarExpanded {
                expandedSidebar
            } else {
                collapsedStrip
            }
        }
        .alert("Delete Document", isPresented: Binding(
            get: { documentToDelete != nil },
            set: { if !$0 { documentToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) { confirmDeleteDocument() }
            Button("Cancel", role: .cancel) { documentToDelete = nil }
        } message: {
            if let doc = documentToDelete {
                Text("Delete \"\(doc.title)\"? This cannot be undone.")
            }
        }
        .alert("Delete Folder", isPresented: Binding(
            get: { folderToDelete != nil },
            set: { if !$0 { folderToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) { confirmDeleteFolder() }
            Button("Cancel", role: .cancel) { folderToDelete = nil }
        } message: {
            if let folder = folderToDelete {
                Text("Delete \"\(folder.name)\"? Documents in this folder will not be deleted — they'll move to unfiled.")
            }
        }
    }

    // MARK: - Expanded Sidebar

    private var expandedSidebar: some View {
        VStack(spacing: 0) {
            // Title bar drag area with collapse button
            HStack {
                Spacer()
                Button {
                    appState.toggleSidebar()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Collapse sidebar")
                .padding(.trailing, 8)
            }
            .frame(height: 38)

            searchBar
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 2) {
                    sectionHeader("FILTERS")
                    filterRow("All Notes", icon: "doc.text", filter: .allNotes, count: allDocuments.count)
                    filterRow("Favorites", icon: "star", filter: .favorites, count: allDocuments.filter(\.isFavorite).count)
                    filterRow("Pinned", icon: "pin", filter: .pinned, count: allDocuments.filter(\.isPinned).count)

                    fileTreeSection
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
            }

            bottomBar
        }
        .frame(width: 240)
        .background(.ultraThinMaterial)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            TextField("Search...", text: Binding(
                get: { appState.searchQuery },
                set: { appState.searchQuery = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            if !appState.searchQuery.isEmpty {
                Button {
                    appState.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: KSpacing.nano, style: .continuous))
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private var filesHeaderWithMenu: some View {
        HStack {
            Text("FILES")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button { createDocument() } label: {
                    Label("New Document", systemImage: "doc.badge.plus")
                }
                Button { createFolder() } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    // MARK: - Smart Filter Rows

    private func filterRow(_ label: String, icon: String, filter: SidebarFilter, count: Int) -> some View {
        let isSelected = appState.sidebarFilter == filter && appState.searchQuery.isEmpty
        let itemID = "filter-\(label)"
        let isHovered = hoveredItemID == itemID

        return Button {
            KHaptics.light()
            appState.sidebarFilter = filter
            appState.searchQuery = ""
        } label: {
            HStack(spacing: KSpacing.nano) {
                Image(systemName: isSelected ? "\(icon).fill" : icon)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? colors.accent : .secondary)
                    .frame(width: KSpacing.micro)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.horizontal, KSpacing.nano)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: KRadius.small, style: .continuous)
                    .fill(isSelected ? colors.selectedRow : (isHovered ? colors.hoverRow : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.khagwalSnappy) {
                hoveredItemID = hovering ? itemID : nil
            }
        }
    }

    // MARK: - Unified File Tree

    private var fileTreeSection: some View {
        Group {
            filesHeaderWithMenu
                .padding(.top, 12)

            if !appState.searchQuery.isEmpty {
                // Search results: flat list
                ForEach(searchResults) { document in
                    fileTreeDocumentRow(document, indented: false)
                }
            } else {
                // Root-level folders (no parent)
                ForEach(workspaces.filter { $0.parent == nil }) { workspace in
                    fileTreeFolderRow(workspace, depth: 0)
                }
                // Unfiled documents (no folder) below folders — drop zone for un-filing
                ForEach(unfiledDocuments) { document in
                    fileTreeDocumentRow(document, indented: false)
                }
            }
        }
        .dropDestination(for: String.self) { items, _ in
            let service = DocumentService(modelContext: modelContext)
            for item in items {
                if item.hasPrefix("doc:"), let docID = UUID(uuidString: String(item.dropFirst(4))) {
                    if let document = allDocuments.first(where: { $0.id == docID }) {
                        try? service.moveDocument(document, to: nil)
                    }
                } else if item.hasPrefix("folder:"), let folderID = UUID(uuidString: String(item.dropFirst(7))) {
                    if let folder = workspaces.first(where: { $0.id == folderID }) {
                        try? service.moveWorkspace(folder, intoParent: nil)
                    }
                }
            }
            return true
        }
    }

    private var unfiledDocuments: [PrismDocument] {
        var docs = allDocuments.filter { $0.folder == nil }
        applySidebarFilterAndSort(&docs)
        return docs
    }

    private var searchResults: [PrismDocument] {
        guard !appState.searchQuery.isEmpty else { return [] }
        let query = appState.searchQuery.lowercased()
        var docs = allDocuments.filter { doc in
            if doc.title.lowercased().contains(query) { return true }
            if let content = contentCache[doc.id]?.lowercased(), content.contains(query) { return true }
            if let content = try? DocumentStorage.shared.readContent(for: doc), content.lowercased().contains(query) { return true }
            return false
        }
        docs.sort { $0.modifiedAt > $1.modifiedAt }
        return docs
    }

    private func applySidebarFilterAndSort(_ docs: inout [PrismDocument]) {
        switch appState.sidebarFilter {
        case .favorites: docs = docs.filter(\.isFavorite)
        case .pinned: docs = docs.filter(\.isPinned)
        default: break
        }
        docs.sort { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.modifiedAt > b.modifiedAt
        }
    }

    // MARK: - File Tree: Folder Row

    private func fileTreeFolderRow(_ workspace: Workspace, depth: Int) -> AnyView {
        let isExpanded = expandedFolders.contains(workspace.id)
        let itemID = "folder-\(workspace.id.uuidString)"
        let isHovered = hoveredItemID == itemID
        let isDropTarget = dropTargetFolderID == workspace.id
        let indent = CGFloat(depth) * 16

        return AnyView(VStack(spacing: 0) {
            if editingFolderID == workspace.id {
                HStack(spacing: 6) {
                    Image(systemName: workspace.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    TextField("Folder name", text: $editingFolderName, onCommit: {
                        finishRenamingFolder(workspace)
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                }
                .padding(.leading, 8 + indent)
                .padding(.trailing, 8)
                .padding(.vertical, 6)
            } else {
                Button {
                    withAnimation(.khagwalSnappy) {
                        if isExpanded {
                            expandedFolders.remove(workspace.id)
                        } else {
                            expandedFolders.insert(workspace.id)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 12)
                        Image(systemName: workspace.icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(workspace.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.leading, 6 + indent)
                    .padding(.trailing, 6)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: KRadius.small, style: .continuous)
                            .fill(isDropTarget ? colors.accent.opacity(0.2) : (isHovered ? colors.hoverRow : Color.clear))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: KRadius.small, style: .continuous)
                            .strokeBorder(isDropTarget ? colors.accent.opacity(0.5) : Color.clear, lineWidth: 1.5)
                    )
                    .overlay(alignment: .leading) {
                        if depth > 0 {
                            Color.primary.opacity(0.08)
                                .frame(width: 1)
                                .padding(.leading, 18 + CGFloat(depth - 1) * 16)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.khagwalSnappy) {
                        hoveredItemID = hovering ? itemID : nil
                    }
                }
                .draggable("folder:" + workspace.id.uuidString)
                .dropDestination(for: String.self) { items, _ in
                    let service = DocumentService(modelContext: modelContext)
                    for item in items {
                        if item.hasPrefix("doc:"), let docID = UUID(uuidString: String(item.dropFirst(4))) {
                            if let document = allDocuments.first(where: { $0.id == docID }) {
                                try? service.moveDocument(document, to: workspace)
                            }
                        } else if item.hasPrefix("folder:"), let folderID = UUID(uuidString: String(item.dropFirst(7))) {
                            if let folder = workspaces.first(where: { $0.id == folderID }), folder.id != workspace.id {
                                try? service.moveWorkspace(folder, intoParent: workspace)
                            }
                        }
                    }
                    _ = withAnimation(.khagwalSnappy) {
                        expandedFolders.insert(workspace.id)
                    }
                    return true
                } isTargeted: { isTargeted in
                    withAnimation(.khagwalSnappy) {
                        dropTargetFolderID = isTargeted ? workspace.id : nil
                    }
                }
                .contextMenu { folderContextMenu(workspace) }
            }

            // Expanded children with continuous indent line
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(workspace.children.sorted(by: { $0.sortOrder < $1.sortOrder })) { child in
                        fileTreeFolderRow(child, depth: depth + 1)
                    }
                    let folderDocs = documentsInFolder(workspace)
                    ForEach(folderDocs) { document in
                        fileTreeDocumentRow(document, indented: true, depth: depth + 1)
                    }
                    if workspace.children.isEmpty && folderDocs.isEmpty {
                        Text("Empty")
                            .font(.system(size: 11))
                            .foregroundStyle(.quaternary)
                            .padding(.leading, 34 + indent + 16)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .overlay(alignment: .leading) {
                    Color.primary.opacity(0.1)
                        .frame(width: 1)
                        .padding(.leading, 18 + indent)
                }
            }
        })
    }

    private func documentsInFolder(_ workspace: Workspace) -> [PrismDocument] {
        var docs = workspace.documents
        applySidebarFilterAndSort(&docs)
        return docs
    }

    // MARK: - File Tree: Document Row

    private func fileTreeDocumentRow(_ document: PrismDocument, indented: Bool, depth: Int = 1) -> some View {
        let isSelected = appState.selectedDocumentID == document.id
        let itemID = "doc-\(document.id.uuidString)"
        let isHovered = hoveredItemID == itemID
        let indent = indented ? CGFloat(depth) * 16 + 18 : CGFloat(0)

        return Button {
            appState.selectedDocumentID = document.id
        } label: {
            HStack(spacing: 4) {
                if document.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                }
                if renamingDocumentID == document.id {
                    TextField("Title", text: $renamingDocumentTitle, onCommit: {
                        finishRenamingDocument(document)
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                } else {
                    Text(document.title)
                        .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                }
                if document.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.yellow)
                }
                Spacer()
            }
            .padding(.leading, 8 + indent)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: KRadius.small, style: .continuous)
                    .fill(isSelected ? colors.selectedRow : (isHovered ? colors.hoverRow : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.khagwalSnappy) {
                hoveredItemID = hovering ? itemID : nil
            }
        }
        .draggable("doc:" + document.id.uuidString)
        .contextMenu { documentContextMenu(document) }
        #if os(iOS)
        .swipeActions(edge: .leading) {
            Button {
                let service = DocumentService(modelContext: modelContext)
                try? service.toggleFavorite(document)
            } label: { Label(document.isFavorite ? "Unfavorite" : "Favorite", systemImage: document.isFavorite ? "star.slash" : "star.fill") }
            .tint(.yellow)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { documentToDelete = document } label: { Label("Delete", systemImage: "trash") }
        }
        #endif
    }

    // MARK: - Drag & Drop

    // handleDrop now inline via .dropDestination on folder rows

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Button {
                KHaptics.light()
                withAnimation(.khagwal) { appState.showSettings = true }
            } label: {
                Image(systemName: "gear")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                KHaptics.light()
                appState.cycleAppearance()
            } label: {
                Image(systemName: appState.appearanceIcon)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .help("Appearance: \(appState.appearanceLabel)")
        }
        .padding(.horizontal, KSpacing.micro)
        .padding(.vertical, KSpacing.nano)
        .overlay(alignment: .top) {
            KColors.border.frame(height: 1)
        }
    }

    // MARK: - Collapsed Icon Strip

    private var collapsedStrip: some View {
        VStack(spacing: 0) {
            // Expand button
            Button {
                appState.toggleSidebar()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .help("Expand sidebar")
            .frame(height: 38)

            VStack(spacing: 12) {
                stripButton(icon: "magnifyingglass", tooltip: "Search") {
                    appState.toggleSidebar()
                    appState.isSearchFocused = true
                }
                Color.primary.opacity(0.06).frame(height: 1).padding(.horizontal, 8)
                stripButton(icon: "doc.text", tooltip: "All Notes", isActive: appState.sidebarFilter == .allNotes) {
                    appState.sidebarFilter = .allNotes
                    appState.toggleSidebar()
                }
                stripButton(icon: "star", tooltip: "Favorites", isActive: appState.sidebarFilter == .favorites) {
                    appState.sidebarFilter = .favorites
                    appState.toggleSidebar()
                }
                stripButton(icon: "pin", tooltip: "Pinned", isActive: appState.sidebarFilter == .pinned) {
                    appState.sidebarFilter = .pinned
                    appState.toggleSidebar()
                }
                if !workspaces.isEmpty {
                    Color.primary.opacity(0.06).frame(height: 1).padding(.horizontal, 8)
                    ForEach(workspaces) { workspace in
                        stripButton(icon: workspace.icon, tooltip: workspace.name) {
                            expandedFolders.insert(workspace.id)
                            appState.sidebarFilter = .allNotes
                            appState.toggleSidebar()
                        }
                    }
                }
            }
            .padding(.top, 4)

            Spacer()

            VStack(spacing: 12) {
                stripButton(icon: "plus", tooltip: "New Document") { createDocument() }
                stripButton(icon: "gear", tooltip: "Settings") { appState.showSettings = true }
                stripButton(icon: appState.appearanceIcon, tooltip: "Appearance") { appState.cycleAppearance() }
            }
            .padding(.bottom, 12)
        }
        .frame(width: 52)
        .background(.ultraThinMaterial)
    }

    private func stripButton(icon: String, tooltip: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            KHaptics.light()
            action()
        } label: {
            Image(systemName: isActive ? "\(icon).fill" : icon)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 44, height: 44)
                .foregroundColor(isActive ? colors.accent : Color.secondary.opacity(0.6))
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    // MARK: - Context Menus

    private func folderContextMenu(_ workspace: Workspace) -> some View {
        Group {
            Button {
                editingFolderID = workspace.id
                editingFolderName = workspace.name
            } label: { Label("Rename", systemImage: "pencil") }
            Menu {
                ForEach(folderIcons, id: \.self) { icon in
                    Button {
                        let service = DocumentService(modelContext: modelContext)
                        try? service.changeWorkspaceIcon(workspace, to: icon)
                    } label: { Label(icon, systemImage: icon) }
                }
            } label: { Label("Change Icon", systemImage: "face.smiling") }
            Divider()
            Button(role: .destructive) { folderToDelete = workspace } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func documentContextMenu(_ document: PrismDocument) -> some View {
        Group {
            Button {
                renamingDocumentID = document.id
                renamingDocumentTitle = document.title
            } label: { Label("Rename", systemImage: "pencil") }
            Button {
                let service = DocumentService(modelContext: modelContext)
                try? service.toggleFavorite(document)
            } label: { Label(document.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: document.isFavorite ? "star.slash" : "star") }
            Button {
                let service = DocumentService(modelContext: modelContext)
                try? service.togglePin(document)
            } label: { Label(document.isPinned ? "Unpin" : "Pin", systemImage: document.isPinned ? "pin.slash" : "pin") }
            if !workspaces.isEmpty {
                Menu {
                    Button {
                        let service = DocumentService(modelContext: modelContext)
                        try? service.moveDocument(document, to: nil)
                    } label: { Label("Unfiled", systemImage: "tray") }
                    Divider()
                    ForEach(workspaces) { workspace in
                        Button {
                            let service = DocumentService(modelContext: modelContext)
                            try? service.moveDocument(document, to: workspace)
                        } label: { Label(workspace.name, systemImage: workspace.icon) }
                    }
                } label: { Label("Move to Folder", systemImage: "folder") }
            }
            Divider()
            Button(role: .destructive) { documentToDelete = document } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private var folderIcons: [String] {
        ["folder", "folder.fill", "book.closed", "graduationcap", "atom", "flask",
         "heart", "star", "flag", "tag", "bookmark", "lightbulb",
         "pencil.and.ruler", "music.note", "globe", "cpu"]
    }

    // MARK: - Content Preview

    private func contentPreview(for document: PrismDocument) -> String? {
        if let cached = contentCache[document.id] {
            return firstNonHeadingLine(cached)
        }
        guard let content = try? DocumentStorage.shared.readContent(for: document) else { return nil }
        DispatchQueue.main.async { contentCache[document.id] = content }
        return firstNonHeadingLine(content)
    }

    private func firstNonHeadingLine(_ content: String) -> String? {
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            return trimmed
        }
        return nil
    }

    // MARK: - Actions

    func createDocument() {
        let service = DocumentService(modelContext: modelContext)
        do {
            let document = try service.createDocument(title: "Untitled")
            appState.selectedDocumentID = document.id
        } catch {
            print("[PRISM] Failed to create document: \(error)")
        }
    }

    private func confirmDeleteDocument() {
        guard let document = documentToDelete else { return }
        let wasSelected = appState.selectedDocumentID == document.id
        let service = DocumentService(modelContext: modelContext)
        do {
            try service.deleteDocument(document)
            documentToDelete = nil
            if wasSelected { appState.selectedDocumentID = nil }
        } catch {
            print("[PRISM] Failed to delete document: \(error)")
        }
    }

    private func createFolder() {
        let service = DocumentService(modelContext: modelContext)
        do {
            let workspace = try service.createWorkspace(name: "New Folder")
            editingFolderID = workspace.id
            editingFolderName = workspace.name
            expandedFolders.insert(workspace.id)
        } catch {
            print("[PRISM] Failed to create folder: \(error)")
        }
    }

    private func finishRenamingFolder(_ workspace: Workspace) {
        let name = editingFolderName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty && name != workspace.name {
            let service = DocumentService(modelContext: modelContext)
            try? service.renameWorkspace(workspace, to: name)
        }
        editingFolderID = nil
    }

    private func finishRenamingDocument(_ document: PrismDocument) {
        let title = renamingDocumentTitle.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty && title != document.title {
            let service = DocumentService(modelContext: modelContext)
            try? service.renameDocument(document, to: title)
        }
        renamingDocumentID = nil
    }

    private func confirmDeleteFolder() {
        guard let folder = folderToDelete else { return }
        let service = DocumentService(modelContext: modelContext)
        do {
            if case .folder(let id) = appState.sidebarFilter, id == folder.id {
                appState.sidebarFilter = .allNotes
            }
            try service.deleteWorkspace(folder)
            folderToDelete = nil
        } catch {
            print("[PRISM] Failed to delete folder: \(error)")
        }
    }
}

// MARK: - Adaptive Color Set

private struct SidebarColorSet {
    let scheme: ColorScheme

    var accent: Color { Color.accentColor }
    var selectedRow: Color { Color.accentColor.opacity(0.12) }
    var hoverRow: Color { scheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04) }
}
