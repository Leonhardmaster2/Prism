import Foundation
import SwiftUI
import Observation

enum SidebarFilter: Equatable {
    case allNotes
    case favorites
    case pinned
    case folder(UUID)
}

enum AppearanceMode: String {
    case system
    case light
    case dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@Observable
final class AppState {

    var selectedDocumentID: UUID? {
        didSet {
            if let id = selectedDocumentID {
                UserDefaults.standard.set(id.uuidString, forKey: Self.lastOpenedKey)
            }
        }
    }

    var sidebarFilter: SidebarFilter = .allNotes
    var isSidebarExpanded: Bool = true
    var isReadingMode: Bool = false
    var searchQuery: String = ""
    var isSearchFocused: Bool = false
    var showSettings: Bool = false

    var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: Self.appearanceKey)
        }
    }

    private static let lastOpenedKey = "lastOpenedDocumentID"
    private static let appearanceKey = "appearanceMode"

    init() {
        if let stored = UserDefaults.standard.string(forKey: Self.lastOpenedKey),
           let uuid = UUID(uuidString: stored) {
            self.selectedDocumentID = uuid
        }
        if let raw = UserDefaults.standard.string(forKey: Self.appearanceKey),
           let mode = AppearanceMode(rawValue: raw) {
            self.appearanceMode = mode
        } else {
            self.appearanceMode = .system
        }
    }

    func toggleSidebar() {
        withAnimation(.khagwal) {
            isSidebarExpanded.toggle()
        }
    }

    func cycleAppearance() {
        switch appearanceMode {
        case .system: appearanceMode = .light
        case .light: appearanceMode = .dark
        case .dark: appearanceMode = .system
        }
    }

    var appearanceIcon: String {
        switch appearanceMode {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var appearanceLabel: String {
        switch appearanceMode {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}
