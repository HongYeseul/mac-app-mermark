import AppKit
import WebKit

/// WKWebView를 소유한다. 모드 전환으로 SwiftUI 뷰가 사라졌다 나타나도 웹뷰를 재생성하지 않아
/// HTML 재로드와 mermaid 재렌더 없이 스크롤 위치까지 그대로 유지된다.
final class PreviewController: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    let webView: WKWebView

    var onScrollToLine: ((Int) -> Void)?

    private var isPageReady = false
    private var latestMarkdown: String?
    private var renderWorkItem: DispatchWorkItem?
    private var pendingScrollLine: Int?

    override init() {
        let configuration = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        configuration.userContentController.add(self, name: "mermaidExport")
        configuration.userContentController.add(self, name: "previewScroll")
        webView.navigationDelegate = self

        if let url = Bundle.main.url(forResource: "preview", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    // mermaid 재렌더 비용이 있어 타이핑 중에는 디바운스
    func render(_ markdown: String) {
        guard latestMarkdown != markdown else { return }
        latestMarkdown = markdown
        guard isPageReady else { return }
        renderWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.renderNow() }
        renderWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    func scroll(toLine line: Int) {
        guard isPageReady else {
            pendingScrollLine = line
            return
        }
        webView.evaluateJavaScript("window.scrollPreviewToLine(\(line));")
    }

    private func renderNow() {
        guard let markdown = latestMarkdown,
              let data = try? JSONEncoder().encode(markdown),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.renderMarkdown(\(json));") { [weak self] _, _ in
            guard let self, let line = self.pendingScrollLine else { return }
            self.pendingScrollLine = nil
            self.scroll(toLine: line)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isPageReady = true
        renderNow()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "previewScroll":
            guard let line = (message.body as? NSNumber)?.intValue else { return }
            onScrollToLine?(line)
        case "mermaidExport":
            guard let body = message.body as? [String: String],
                  let code = body["code"], let action = body["action"] else { return }
            switch action {
            case "savePNG":
                MermaidExporter.shared.exportPNG(code: code, destination: .savePanel)
            case "copyPNG":
                MermaidExporter.shared.exportPNG(code: code, destination: .clipboard)
            case "saveSVG":
                MermaidExporter.shared.exportSVG(code: code)
            default:
                break
            }
        default:
            break
        }
    }
}
