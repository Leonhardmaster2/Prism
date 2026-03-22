import SwiftUI
import WebKit

struct VideoPlayerSheet: View {
    let videoId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    KHaptics.light()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .padding(KSpacing.nano)
            }

            YouTubePlayerView(videoId: videoId)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(KColors.canvas)
        .clipShape(RoundedRectangle(cornerRadius: KRadius.large, style: .continuous))
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 400)
        #endif
    }
}

#if os(macOS)
struct YouTubePlayerView: NSViewRepresentable {
    let videoId: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        let url = URL(string: "https://www.youtube.com/embed/\(videoId)?autoplay=1&rel=0")!
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else
struct YouTubePlayerView: UIViewRepresentable {
    let videoId: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        let url = URL(string: "https://www.youtube.com/embed/\(videoId)?autoplay=1&rel=0")!
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
