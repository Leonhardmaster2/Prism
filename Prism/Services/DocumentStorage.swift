import Foundation

enum DocumentStorageError: LocalizedError {
    case documentsDirectoryUnavailable
    case fileNotFound(String)
    case fileAlreadyExists(String)
    case writeFailed(String)
    case deleteFailed(String)
    case renameFailed(String)

    var errorDescription: String? {
        switch self {
        case .documentsDirectoryUnavailable:
            return "Could not access the documents directory."
        case .fileNotFound(let name):
            return "File not found: \(name)"
        case .fileAlreadyExists(let name):
            return "A file named \"\(name)\" already exists."
        case .writeFailed(let detail):
            return "Failed to write file: \(detail)"
        case .deleteFailed(let detail):
            return "Failed to delete file: \(detail)"
        case .renameFailed(let detail):
            return "Failed to rename file: \(detail)"
        }
    }
}

final class DocumentStorage {

    static let shared = DocumentStorage()

    private let fileManager = FileManager.default
    private let prismDirectoryName = "Prism"
    private let fileExtension = "md"

    private init() {}

    // MARK: - Directory

    func getDocumentsDirectory() throws -> URL {
        guard let appDocuments = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw DocumentStorageError.documentsDirectoryUnavailable
        }

        let prismDir = appDocuments.appendingPathComponent(prismDirectoryName, isDirectory: true)

        if !fileManager.fileExists(atPath: prismDir.path) {
            try fileManager.createDirectory(at: prismDir, withIntermediateDirectories: true)
        }

        return prismDir
    }

    // MARK: - Read

    func readContent(for document: PrismDocument) throws -> String {
        let fileURL = try fileURL(for: document)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw DocumentStorageError.fileNotFound(document.fileName)
        }

        let raw = try String(contentsOf: fileURL, encoding: .utf8)
        let parsed = FrontmatterParser.parse(raw)
        return parsed.content
    }

    func readRawContent(for document: PrismDocument) throws -> String {
        let fileURL = try fileURL(for: document)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw DocumentStorageError.fileNotFound(document.fileName)
        }

        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    // MARK: - Write

    func writeContent(_ content: String, for document: PrismDocument) throws {
        let fileURL = try fileURL(for: document)
        let serialized = FrontmatterParser.serialize(content: content, tags: document.tags)

        do {
            try serialized.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw DocumentStorageError.writeFailed(error.localizedDescription)
        }
    }

    // MARK: - Create

    func createFile(named title: String) throws -> (url: URL, fileName: String) {
        let dir = try getDocumentsDirectory()
        let sanitized = sanitizeFileName(title)
        let fileName = uniqueFileName(sanitized, in: dir)
        let fileURL = dir.appendingPathComponent(fileName)

        let initialContent = "# \(title)\n"

        do {
            try initialContent.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw DocumentStorageError.writeFailed(error.localizedDescription)
        }

        return (fileURL, fileName)
    }

    // MARK: - Delete

    func deleteFile(for document: PrismDocument) throws {
        let fileURL = try fileURL(for: document)

        // Delete the .md file
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                try fileManager.removeItem(at: fileURL)
            } catch {
                throw DocumentStorageError.deleteFailed(error.localizedDescription)
            }
        }

        // Delete the .assets/ folder if it exists
        let assetsDir = try assetsDirectory(for: document)
        if fileManager.fileExists(atPath: assetsDir.path) {
            try fileManager.removeItem(at: assetsDir)
        }
    }

    // MARK: - Rename

    func renameFile(for document: PrismDocument, to newTitle: String) throws -> String {
        let dir = try getDocumentsDirectory()
        let oldURL = dir.appendingPathComponent(document.fileName)

        guard fileManager.fileExists(atPath: oldURL.path) else {
            throw DocumentStorageError.fileNotFound(document.fileName)
        }

        let sanitized = sanitizeFileName(newTitle)
        let newFileName = uniqueFileName(sanitized, in: dir, excluding: document.fileName)
        let newURL = dir.appendingPathComponent(newFileName)

        do {
            try fileManager.moveItem(at: oldURL, to: newURL)
        } catch {
            throw DocumentStorageError.renameFailed(error.localizedDescription)
        }

        // Rename assets folder if it exists
        let oldAssetsName = document.fileName
            .replacingOccurrences(of: ".\(fileExtension)", with: ".assets")
        let newAssetsName = newFileName
            .replacingOccurrences(of: ".\(fileExtension)", with: ".assets")
        let oldAssetsURL = dir.appendingPathComponent(oldAssetsName)
        let newAssetsURL = dir.appendingPathComponent(newAssetsName)

        if fileManager.fileExists(atPath: oldAssetsURL.path) {
            try fileManager.moveItem(at: oldAssetsURL, to: newAssetsURL)
        }

        return newFileName
    }

    // MARK: - Import / Export

    func importFile(from sourceURL: URL) throws -> (url: URL, fileName: String, title: String) {
        let dir = try getDocumentsDirectory()

        let originalName = sourceURL.deletingPathExtension().lastPathComponent
        let sanitized = sanitizeFileName(originalName)
        let fileName = uniqueFileName(sanitized, in: dir)
        let destURL = dir.appendingPathComponent(fileName)

        let content = try String(contentsOf: sourceURL, encoding: .utf8)

        do {
            try content.write(to: destURL, atomically: true, encoding: .utf8)
        } catch {
            throw DocumentStorageError.writeFailed(error.localizedDescription)
        }

        return (destURL, fileName, originalName)
    }

    func exportFile(for document: PrismDocument, to destinationURL: URL) throws {
        let fileURL = try fileURL(for: document)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw DocumentStorageError.fileNotFound(document.fileName)
        }

        try fileManager.copyItem(at: fileURL, to: destinationURL)
    }

    // MARK: - Helpers

    func fileURL(for document: PrismDocument) throws -> URL {
        let dir = try getDocumentsDirectory()
        return dir.appendingPathComponent(document.fileName)
    }

    func assetsDirectory(for document: PrismDocument) throws -> URL {
        let dir = try getDocumentsDirectory()
        let assetsName = document.fileName
            .replacingOccurrences(of: ".\(fileExtension)", with: ".assets")
        return dir.appendingPathComponent(assetsName, isDirectory: true)
    }

    func fileExists(named fileName: String) throws -> Bool {
        let dir = try getDocumentsDirectory()
        return fileManager.fileExists(atPath: dir.appendingPathComponent(fileName).path)
    }

    // MARK: - File Name Utilities

    func sanitizeFileName(_ title: String) -> String {
        // Allow letters, numbers, spaces, hyphens, underscores
        var sanitized = title.components(separatedBy: CharacterSet.alphanumerics
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: "-_"))
            .inverted)
            .joined()
            .trimmingCharacters(in: .whitespaces)

        // Replace spaces with hyphens
        sanitized = sanitized
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: "-")

        // Lowercase
        sanitized = sanitized.lowercased()

        if sanitized.isEmpty {
            sanitized = "untitled"
        }

        return sanitized
    }

    private func uniqueFileName(_ baseName: String, in directory: URL, excluding: String? = nil) -> String {
        let candidate = "\(baseName).\(fileExtension)"

        // If there's no collision (or the collision is the file we're excluding), use as-is
        if !fileManager.fileExists(atPath: directory.appendingPathComponent(candidate).path)
            || candidate == excluding {
            return candidate
        }

        var counter = 2
        while true {
            let numberedCandidate = "\(baseName)-\(counter).\(fileExtension)"
            if !fileManager.fileExists(atPath: directory.appendingPathComponent(numberedCandidate).path)
                || numberedCandidate == excluding {
                return numberedCandidate
            }
            counter += 1
        }
    }
}
