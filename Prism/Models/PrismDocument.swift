import Foundation
import SwiftData

@Model
final class PrismDocument {
    @Attribute(.unique) var id: UUID
    var title: String
    var fileName: String
    var createdAt: Date
    var modifiedAt: Date
    var tags: [String]
    var isFavorite: Bool
    var isPinned: Bool
    var wordCount: Int
    var lastCursorPosition: Int
    var lastScrollPosition: Double
    var folder: Workspace?

    init(
        title: String,
        fileName: String,
        tags: [String] = [],
        folder: Workspace? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.fileName = fileName
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.tags = tags
        self.isFavorite = false
        self.isPinned = false
        self.wordCount = 0
        self.lastCursorPosition = 0
        self.lastScrollPosition = 0
        self.folder = folder
    }
}
