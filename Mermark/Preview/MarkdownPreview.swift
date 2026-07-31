import SwiftUI
import WebKit

struct MarkdownPreview: NSViewRepresentable {
    let controller: PreviewController
    var markdown: String

    func makeNSView(context: Context) -> WKWebView {
        controller.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        controller.render(markdown)
    }
}
