import SwiftUI
import WebKit

struct EditorView: View {
    let document: PrismDocument?
    let isDarkMode: Bool
    let isReadingMode: Bool
    let bridge: EditorBridge
    let onContentChanged: (String, Int) -> Void
    let onStateChanged: (EditorStateInfo) -> Void

    var body: some View {
        EditorWebView(
            document: document,
            isDarkMode: isDarkMode,
            isReadingMode: isReadingMode,
            bridge: bridge,
            onContentChanged: onContentChanged,
            onStateChanged: onStateChanged
        )
        .background(KColors.canvas)
    }
}

// MARK: - Platform WebView

#if os(macOS)

struct EditorWebView: NSViewRepresentable {
    let document: PrismDocument?
    let isDarkMode: Bool
    let isReadingMode: Bool
    let bridge: EditorBridge
    let onContentChanged: (String, Int) -> Void
    let onStateChanged: (EditorStateInfo) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let webView = createWebView(bridge: bridge, coordinator: context.coordinator)
        bridge.webView = webView
        loadEditor(webView, theme: isDarkMode ? "dark" : "light")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(
            document: document,
            isDarkMode: isDarkMode,
            isReadingMode: isReadingMode,
            bridge: bridge,
            onContentChanged: onContentChanged,
            onStateChanged: onStateChanged
        )
    }

    func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(
            document: document,
            isDarkMode: isDarkMode,
            isReadingMode: isReadingMode,
            bridge: bridge,
            onContentChanged: onContentChanged,
            onStateChanged: onStateChanged
        )
    }
}

#else

struct EditorWebView: UIViewRepresentable {
    let document: PrismDocument?
    let isDarkMode: Bool
    let isReadingMode: Bool
    let bridge: EditorBridge
    let onContentChanged: (String, Int) -> Void
    let onStateChanged: (EditorStateInfo) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let webView = createWebView(bridge: bridge, coordinator: context.coordinator)
        bridge.webView = webView
        webView.scrollView.keyboardDismissMode = .interactive
        loadEditor(webView, theme: isDarkMode ? "dark" : "light")
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(
            document: document,
            isDarkMode: isDarkMode,
            isReadingMode: isReadingMode,
            bridge: bridge,
            onContentChanged: onContentChanged,
            onStateChanged: onStateChanged
        )
    }

    func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(
            document: document,
            isDarkMode: isDarkMode,
            isReadingMode: isReadingMode,
            bridge: bridge,
            onContentChanged: onContentChanged,
            onStateChanged: onStateChanged
        )
    }
}

#endif

// MARK: - Shared Creation & Loading

// MARK: - Local HTTP Server for Editor

/// Minimal HTTP server serving bundled resources on localhost.
/// Gives WKWebView an http:// origin so YouTube embeds work.
private class LocalEditorServer {
    static let shared = LocalEditorServer()
    private var listener: (any NSObjectProtocol)?
    private(set) var port: UInt16 = 0
    private var serverSocket: Int32 = -1
    private var isRunning = false

    var baseURL: URL? {
        port > 0 ? URL(string: "http://localhost:\(port)") : nil
    }

    func start() {
        guard !isRunning, let resourceURL = Bundle.main.resourceURL else { return }

        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else { print("[SERVER] socket() failed"); return }

        var reuse: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0 // Let OS pick a port

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bindResult == 0 else { print("[SERVER] bind() failed"); close(serverSocket); return }

        guard Darwin.listen(serverSocket, 5) == 0 else { print("[SERVER] listen() failed"); close(serverSocket); return }

        // Get the assigned port
        var boundAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &boundAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(serverSocket, $0, &addrLen) }
        }
        port = UInt16(bigEndian: boundAddr.sin_port)
        isRunning = true
        print("[SERVER] Listening on http://localhost:\(port)")

        // Accept connections on a background queue
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while let self = self, self.isRunning {
                let client = accept(self.serverSocket, nil, nil)
                if client < 0 { continue }
                self.handleClient(client, resourceURL: resourceURL)
            }
        }
    }

    private func handleClient(_ client: Int32, resourceURL: URL) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = recv(client, &buffer, buffer.count, 0)
        guard bytesRead > 0 else { close(client); return }

        let request = String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""
        let firstLine = request.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { close(client); return }

        var path = parts[1]
        if path == "/" { path = "/editor.html" }
        if path.hasPrefix("/") { path = String(path.dropFirst()) }
        // Remove query string
        if let q = path.firstIndex(of: "?") { path = String(path[..<q]) }

        let fileURL = resourceURL.appendingPathComponent(path)
        let ext = (path as NSString).pathExtension.lowercased()

        let mimeType: String
        switch ext {
        case "html": mimeType = "text/html; charset=utf-8"
        case "css": mimeType = "text/css; charset=utf-8"
        case "js": mimeType = "application/javascript; charset=utf-8"
        case "json": mimeType = "application/json"
        case "woff": mimeType = "font/woff"
        case "woff2": mimeType = "font/woff2"
        case "ttf": mimeType = "font/ttf"
        case "png": mimeType = "image/png"
        case "jpg", "jpeg": mimeType = "image/jpeg"
        case "svg": mimeType = "image/svg+xml"
        default: mimeType = "application/octet-stream"
        }

        if let data = try? Data(contentsOf: fileURL) {
            let header = "HTTP/1.1 200 OK\r\nContent-Type: \(mimeType)\r\nContent-Length: \(data.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
            send(client, header, header.utf8.count, 0)
            data.withUnsafeBytes { send(client, $0.baseAddress!, data.count, 0) }
        } else {
            let body = "Not Found"
            let header = "HTTP/1.1 404 Not Found\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            send(client, header, header.utf8.count, 0)
            send(client, body, body.utf8.count, 0)
        }
        close(client)
    }
}

private func createWebView(bridge: EditorBridge, coordinator: EditorCoordinator) -> WKWebView {
    let contentController = WKUserContentController()
    contentController.add(bridge, name: "prism")

    let config = WKWebViewConfiguration()
    config.userContentController = contentController
    #if os(iOS)
    config.allowsInlineMediaPlayback = true
    config.mediaTypesRequiringUserActionForPlayback = []
    #endif

    #if os(macOS)
    let webView = WKWebView(frame: .zero, configuration: config)
    webView.setValue(false, forKey: "drawsBackground")
    #else
    let webView = WKWebView(frame: .zero, configuration: config)
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.backgroundColor = .clear
    #endif

    webView.navigationDelegate = coordinator

    #if DEBUG
    if #available(macOS 13.3, iOS 16.4, *) {
        webView.isInspectable = true
    }
    #endif

    return webView
}

private func loadEditor(_ webView: WKWebView, theme: String = "light") {
    // Inject theme immediately via user script BEFORE any page content loads
    let themeScript = WKUserScript(
        source: "document.documentElement.setAttribute('data-theme', '\(theme)');",
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
    )
    webView.configuration.userContentController.addUserScript(themeScript)

    // Start local server and load via http://localhost
    LocalEditorServer.shared.start()
    if let baseURL = LocalEditorServer.shared.baseURL {
        let editorURL = baseURL.appendingPathComponent("editor.html")
        print("[SERVER] Loading editor from \(editorURL)")
        webView.load(URLRequest(url: editorURL))
    } else {
        // Fallback to file:// if server fails
        print("[SERVER] Failed to start, falling back to file://")
        guard let resourceURL = Bundle.main.resourceURL else { return }
        let htmlURL = resourceURL.appendingPathComponent("editor.html")
        webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceURL)
    }
}

// MARK: - Coordinator

class EditorCoordinator: NSObject, WKNavigationDelegate {
    private var currentDocumentID: UUID?
    private var document: PrismDocument?
    private var isDarkMode: Bool
    private var isReadingMode: Bool
    private var bridge: EditorBridge
    private var onContentChanged: (String, Int) -> Void
    private var onStateChanged: (EditorStateInfo) -> Void
    private var hasLoadedInitialContent = false
    private var pendingDocumentLoad: UUID?

    init(
        document: PrismDocument?,
        isDarkMode: Bool,
        isReadingMode: Bool,
        bridge: EditorBridge,
        onContentChanged: @escaping (String, Int) -> Void,
        onStateChanged: @escaping (EditorStateInfo) -> Void
    ) {
        self.document = document
        self.isDarkMode = isDarkMode
        self.isReadingMode = isReadingMode
        self.bridge = bridge
        self.onContentChanged = onContentChanged
        self.onStateChanged = onStateChanged
        super.init()

        setupBridgeCallbacks()
    }

    func update(
        document: PrismDocument?,
        isDarkMode: Bool,
        isReadingMode: Bool,
        bridge: EditorBridge,
        onContentChanged: @escaping (String, Int) -> Void,
        onStateChanged: @escaping (EditorStateInfo) -> Void
    ) {
        self.onContentChanged = onContentChanged
        self.onStateChanged = onStateChanged

        // Theme change
        if self.isDarkMode != isDarkMode {
            self.isDarkMode = isDarkMode
            bridge.setTheme(isDarkMode ? "dark" : "light")
        }

        // Reading mode change
        if self.isReadingMode != isReadingMode {
            self.isReadingMode = isReadingMode
            bridge.setEditable(!isReadingMode)
        }

        // Document change
        let newID = document?.id
        if newID != currentDocumentID {
            // Save current document's position before switching
            if currentDocumentID != nil, let oldDoc = self.document {
                savePositions(for: oldDoc)
            }

            self.document = document
            currentDocumentID = newID

            if let doc = document {
                loadDocument(doc)
            }
        }
    }

    private func setupBridgeCallbacks() {
        bridge.onReady = { [weak self] in
            guard let self else { return }
            print("[PRISM] Editor ready")
            self.bridge.setTheme(self.isDarkMode ? "dark" : "light")
            self.bridge.setEditable(!self.isReadingMode)

            if let doc = self.document {
                self.loadDocument(doc)
            }

            // Make WKWebView first responder so it accepts clicks/typing
            #if os(macOS)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.bridge.webView?.window?.makeFirstResponder(self.bridge.webView)
            }
            #endif
        }

        bridge.onContentChanged = { [weak self] markdown, wordCount in
            guard let self else { return }
            self.onContentChanged(markdown, wordCount)
        }

        bridge.onStateChanged = { [weak self] info in
            guard let self else { return }
            self.onStateChanged(info)
        }

        bridge.onScrollChanged = { [weak self] position in
            guard let self else { return }
            self.document?.lastScrollPosition = position
        }
    }

    private func loadDocument(_ document: PrismDocument) {
        pendingDocumentLoad = document.id

        let markdown: String
        do {
            markdown = try DocumentStorage.shared.readContent(for: document)
        } catch {
            print("[PRISM] Failed to read document: \(error)")
            markdown = ""
        }

        // Check this is still the document we want to load (prevents race conditions)
        guard pendingDocumentLoad == document.id else { return }

        bridge.loadContent(markdown, forDocument: document.id)

        // Restore positions and focus after a brief delay for the editor to render
        let scrollPos = document.lastScrollPosition
        let cursorPos = document.lastCursorPosition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard self?.currentDocumentID == document.id else { return }
            if scrollPos > 0 {
                self?.bridge.setScrollPosition(scrollPos)
            }
            if cursorPos > 0 {
                self?.bridge.setCursorPosition(cursorPos)
            }
            self?.bridge.focusEditor()
        }
    }

    private func savePositions(for document: PrismDocument) {
        bridge.getScrollPosition { position in
            document.lastScrollPosition = position
        }
        bridge.getCursorPosition { position in
            document.lastCursorPosition = position
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("[PRISM] WebView finished loading")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[PRISM] WebView navigation failed: \(error)")
    }

    private var reloadCount = 0
    private let maxReloads = 3

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        reloadCount += 1
        print("[PRISM] WebView process terminated (attempt \(reloadCount)/\(maxReloads))")
        if reloadCount <= maxReloads {
            bridge.reset()
            loadEditor(webView, theme: isDarkMode ? "dark" : "light")
        } else {
            print("[PRISM] Max reloads reached — giving up")
        }
    }
}
