import Foundation
import SwiftData

@Model
final class Workspace {
    @Attribute(.unique) var id: UUID
    var name: String
    var icon: String
    var createdAt: Date
    var sortOrder: Int
    var parent: Workspace?

    @Relationship(deleteRule: .nullify, inverse: \PrismDocument.folder)
    var documents: [PrismDocument]

    @Relationship(deleteRule: .nullify, inverse: \Workspace.parent)
    var children: [Workspace]

    init(name: String, icon: String = "folder", sortOrder: Int = 0, parent: Workspace? = nil) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.createdAt = Date()
        self.sortOrder = sortOrder
        self.parent = parent
        self.documents = []
        self.children = []
    }
}
