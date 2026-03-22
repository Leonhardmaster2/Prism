import Foundation
import WebKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct EditorStateInfo {
    var isBold: Bool = false
    var isItalic: Bool = false
    var isStrikethrough: Bool = false
    var isInlineCode: Bool = false
    var headingLevel: Int = 0
    var isInList: Bool = false
    var listType: String? = nil
    var isInBlockquote: Bool = false
    var isInCodeBlock: Bool = false
    var hasSelection: Bool = false
    var selectedText: String = ""
}

final class EditorBridge: NSObject, WKScriptMessageHandler {

    weak var webView: WKWebView?
    private var isReady = false
    private var pendingCommands: [() -> Void] = []
    private var currentDocumentID: UUID?

    var onReady: (() -> Void)?
    var onContentChanged: ((String, Int) -> Void)?
    var onStateChanged: ((EditorStateInfo) -> Void)?
    var onScrollChanged: ((Double) -> Void)?
    var onSaveRequested: (() -> Void)?
    var onLinkRequested: (() -> Void)?
    var onPlayVideo: ((String) -> Void)?

    // MARK: - WKScriptMessageHandler

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let messageBody = message.body
        Task { @MainActor in
            guard let body = messageBody as? String,
                  let data = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let action = json["action"] as? String
            else { return }

            let payload = json["data"] as? [String: Any] ?? [:]
            self.handleMessage(action: action, data: payload)
        }
    }

    private var hasReceivedReady = false

    private func handleMessage(action: String, data: [String: Any]) {
        switch action {
        case "ready":
            guard !hasReceivedReady else {
                print("[PRISM] Ignoring duplicate ready message")
                return
            }
            hasReceivedReady = true
            isReady = true
            flushPendingCommands()
            onReady?()

        case "contentChanged":
            guard let markdown = data["markdown"] as? String,
                  let wordCount = data["wordCount"] as? Int
            else { return }
            onContentChanged?(markdown, wordCount)

        case "stateChanged":
            var info = EditorStateInfo()
            info.isBold = data["isBold"] as? Bool ?? false
            info.isItalic = data["isItalic"] as? Bool ?? false
            info.isStrikethrough = data["isStrikethrough"] as? Bool ?? false
            info.isInlineCode = data["isInlineCode"] as? Bool ?? false
            info.headingLevel = data["headingLevel"] as? Int ?? 0
            info.isInList = data["isInList"] as? Bool ?? false
            info.listType = data["listType"] as? String
            info.isInBlockquote = data["isInBlockquote"] as? Bool ?? false
            info.isInCodeBlock = data["isInCodeBlock"] as? Bool ?? false
            info.hasSelection = data["hasSelection"] as? Bool ?? false
            info.selectedText = data["selectedText"] as? String ?? ""
            onStateChanged?(info)

        case "scrollChanged":
            guard let position = data["position"] as? Double else { return }
            onScrollChanged?(position)

        case "save":
            onSaveRequested?()

        case "requestLink":
            onLinkRequested?()

        case "jslog":
            let msg = data["msg"] as? String ?? ""
            print("[JS] \(msg)")

        case "fetchVideoMeta":
            guard let videoId = data["videoId"] as? String else { return }
            fetchYouTubeMeta(videoId: videoId)

        case "openURL":
            if let urlString = data["url"] as? String, let url = URL(string: urlString) {
                #if os(macOS)
                NSWorkspace.shared.open(url)
                #else
                UIApplication.shared.open(url)
                #endif
            }

        default:
            print("[PRISM] Unknown message action: \(action)")
        }
    }

    // MARK: - Swift → JS Commands

    func loadContent(_ markdown: String, forDocument docID: UUID?) {
        currentDocumentID = docID
        let escaped = escapeForJS(markdown)
        execute("window.loadContent('\(escaped)')")
    }

    func executeCommand(_ command: String, payload: [String: Any]? = nil) {
        if let payload = payload,
           let jsonData = try? JSONSerialization.data(withJSONObject: payload),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            execute("window.executeCommand('\(command)', \(jsonString))")
        } else {
            execute("window.executeCommand('\(command)')")
        }
    }

    func setTheme(_ theme: String) {
        execute("window.setTheme('\(theme)')")
    }

    func setEditable(_ editable: Bool) {
        execute("window.setEditable(\(editable))")
    }

    func getScrollPosition(completion: @escaping (Double) -> Void) {
        webView?.evaluateJavaScript("window.getScrollPosition()") { result, _ in
            completion(result as? Double ?? 0)
        }
    }

    func setScrollPosition(_ position: Double) {
        execute("window.setScrollPosition(\(position))")
    }

    func getCursorPosition(completion: @escaping (Int) -> Void) {
        webView?.evaluateJavaScript("window.getCursorPosition()") { result, _ in
            completion(result as? Int ?? 0)
        }
    }

    func setCursorPosition(_ offset: Int) {
        execute("window.setCursorPosition(\(offset))")
    }

    func getCurrentContent(completion: @escaping (String) -> Void) {
        webView?.evaluateJavaScript("window.getContent()") { result, _ in
            completion(result as? String ?? "")
        }
    }

    // MARK: - Helpers

    private func execute(_ js: String) {
        guard isReady else {
            pendingCommands.append { [weak self] in
                self?.webView?.evaluateJavaScript(js, completionHandler: nil)
            }
            return
        }
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    private func flushPendingCommands() {
        let commands = pendingCommands
        pendingCommands.removeAll()
        for command in commands {
            command()
        }
    }

    private func escapeForJS(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    func reset() {
        isReady = false
        hasReceivedReady = false
        pendingCommands.removeAll()
        currentDocumentID = nil
    }

    func focusEditor() {
        execute("window.focusEditor()")
    }

    // MARK: - YouTube oEmbed

    private func fetchYouTubeMeta(videoId: String) {
        let urlString = "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=\(videoId)&format=json"
        guard let url = URL(string: urlString) else {
            print("[YT] Invalid oEmbed URL")
            return
        }

        print("[YT] Fetching metadata for \(videoId)")
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            if let error = error {
                print("[YT] Fetch error: \(error.localizedDescription)")
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let title = json["title"] as? String
            else {
                print("[YT] Failed to parse oEmbed response")
                if let data = data, let str = String(data: data, encoding: .utf8) {
                    print("[YT] Response: \(str.prefix(200))")
                }
                return
            }

            let author = json["author_name"] as? String ?? ""
            let escapedTitle = title
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            let escapedAuthor = author
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")

            DispatchQueue.main.async {
                self?.webView?.evaluateJavaScript(
                    "window.setVideoMeta('\(videoId)', { title: '\(escapedTitle)', author: '\(escapedAuthor)' })",
                    completionHandler: nil
                )
            }
        }.resume()
    }

    func insertLink(url: String) {
        let escaped = escapeForJS(url)
        execute("window.insertLinkWithURL('\(escaped)')")
    }
}
