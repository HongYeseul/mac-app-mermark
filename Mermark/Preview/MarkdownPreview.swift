import SwiftUI
import WebKit

struct MarkdownPreview: NSViewRepresentable {
    let controller: PreviewController
    var markdown: String
    var noteURL: URL?
    var rootURL: URL?

    func makeNSView(context: Context) -> WKWebView {
        controller.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // 렌더보다 먼저 위치를 알려야 이미지 요청이 올바른 폴더에서 해석된다
        controller.setLocation(noteURL: noteURL, rootURL: rootURL)
        controller.render(markdown)
    }
}
