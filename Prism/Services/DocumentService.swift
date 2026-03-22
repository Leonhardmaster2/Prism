import Foundation
import SwiftData

final class DocumentService {

    private let storage = DocumentStorage.shared
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Create

    func createDocument(title: String, in folder: Workspace? = nil) throws -> PrismDocument {
        let (_, fileName) = try storage.createFile(named: title)

        let document = PrismDocument(
            title: title,
            fileName: fileName,
            folder: folder
        )
        modelContext.insert(document)
        try modelContext.save()

        return document
    }

    // MARK: - Delete

    func deleteDocument(_ document: PrismDocument) throws {
        try storage.deleteFile(for: document)
        modelContext.delete(document)
        try modelContext.save()
    }

    // MARK: - Update Content

    func updateContent(_ document: PrismDocument, content: String, wordCount: Int) throws {
        // Write to disk immediately
        try storage.writeContent(content, for: document)
        // Update metadata without saving to SwiftData on every keystroke
        document.wordCount = wordCount
        document.modifiedAt = Date()
        // Don't call modelContext.save() here — let SwiftData auto-save
        // This prevents SwiftUI re-render cascades on every content change
    }

    // MARK: - Read Content

    func readContent(for document: PrismDocument) throws -> String {
        try storage.readContent(for: document)
    }

    // MARK: - Toggle Favorite / Pin

    func toggleFavorite(_ document: PrismDocument) throws {
        document.isFavorite.toggle()
        try modelContext.save()
    }

    func togglePin(_ document: PrismDocument) throws {
        document.isPinned.toggle()
        try modelContext.save()
    }

    // MARK: - Move

    func moveDocument(_ document: PrismDocument, to folder: Workspace?) throws {
        document.folder = folder
        document.modifiedAt = Date()
        try modelContext.save()
    }

    // MARK: - Rename

    func renameDocument(_ document: PrismDocument, to newTitle: String) throws {
        let newFileName = try storage.renameFile(for: document, to: newTitle)
        document.title = newTitle
        document.fileName = newFileName
        document.modifiedAt = Date()
        try modelContext.save()
    }

    // MARK: - Import

    func importMarkdown(from url: URL) throws -> PrismDocument {
        let (_, fileName, title) = try storage.importFile(from: url)

        // Parse the imported file for tags
        let rawContent = try String(contentsOf: url, encoding: .utf8)
        let parsed = FrontmatterParser.parse(rawContent)

        let document = PrismDocument(
            title: title,
            fileName: fileName,
            tags: parsed.tags
        )

        // Count words in the content
        document.wordCount = countWords(in: parsed.content)

        modelContext.insert(document)
        try modelContext.save()

        return document
    }

    // MARK: - Export

    func exportMarkdown(for document: PrismDocument, to url: URL) throws {
        try storage.exportFile(for: document, to: url)
    }

    // MARK: - Workspace

    func createWorkspace(name: String, icon: String = "folder") throws -> Workspace {
        // Determine sort order
        let descriptor = FetchDescriptor<Workspace>(
            sortBy: [SortDescriptor(\.sortOrder, order: .reverse)]
        )
        let existing = try modelContext.fetch(descriptor)
        let nextOrder = (existing.first?.sortOrder ?? -1) + 1

        let workspace = Workspace(name: name, icon: icon, sortOrder: nextOrder)
        modelContext.insert(workspace)
        try modelContext.save()

        return workspace
    }

    func deleteWorkspace(_ workspace: Workspace) throws {
        modelContext.delete(workspace)
        try modelContext.save()
    }

    func renameWorkspace(_ workspace: Workspace, to newName: String) throws {
        workspace.name = newName
        try modelContext.save()
    }

    func moveWorkspace(_ workspace: Workspace, intoParent parent: Workspace?) throws {
        // Prevent circular nesting
        if let parent = parent {
            var current: Workspace? = parent
            while let c = current {
                if c.id == workspace.id { return }
                current = c.parent
            }
        }
        workspace.parent = parent
        try modelContext.save()
    }

    func changeWorkspaceIcon(_ workspace: Workspace, to icon: String) throws {
        workspace.icon = icon
        try modelContext.save()
    }

    // MARK: - Helpers

    private func countWords(in text: String) -> Int {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return words.count
    }
}
