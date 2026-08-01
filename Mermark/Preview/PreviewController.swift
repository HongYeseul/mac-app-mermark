import AppKit
import WebKit

/// WKWebView를 소유한다. 모드 전환으로 SwiftUI 뷰가 사라졌다 나타나도 웹뷰를 재생성하지 않아
/// HTML 재로드와 mermaid 재렌더 없이 스크롤 위치까지 그대로 유지된다.
final class PreviewController: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    let webView: WKWebView

    var onScrollToLine: ((Int) -> Void)?
    /// 프리뷰에서 다른 노트 링크를 눌렀을 때 (파일 URL, 앵커)
    var onOpenNote: ((URL, String?) -> Void)?
    /// 할 일 체크박스를 눌렀을 때 (원본 줄 번호)
    var onToggleTask: ((Int) -> Void)?
    /// 프리뷰의 태그를 눌렀을 때 (태그 이름)
    var onSelectTag: ((String) -> Void)?

    private var isPageReady = false
    private var latestMarkdown: String?
    private var renderWorkItem: DispatchWorkItem?
    private var pendingScrollLine: Int?
    private var pendingAnchor: String?

    private let resourceHandler: LocalResourceHandler

    override init() {
        // super.init() 전에는 self를 읽을 수 없어 지역 변수로 만든 뒤 저장한다
        let handler = LocalResourceHandler()
        resourceHandler = handler

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: LocalResourceHandler.scheme)
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        configuration.userContentController.add(self, name: "mermaidExport")
        configuration.userContentController.add(self, name: "previewScroll")
        configuration.userContentController.add(self, name: "toggleTask")
        configuration.userContentController.add(self, name: "selectTag")
        webView.navigationDelegate = self

        if let url = Bundle.main.url(forResource: "preview", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    /// 상대경로 이미지를 노트 위치 기준으로 풀 수 있게 현재 노트와 노트 폴더를 알려준다
    func setLocation(noteURL: URL?, folderURL: URL?) {
        resourceHandler.noteDirectory = noteURL?.deletingLastPathComponent()
        resourceHandler.rootDirectory = folderURL
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

    /// 지금 보이는 문서를 PDF로 저장한다
    func exportPDF(defaultName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = defaultName + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        PDFExporter.export(webView, to: url) { error in
            guard let error else { return }
            let alert = NSAlert()
            alert.messageText = "PDF 내보내기 오류"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    /// 노트를 새로 연 직후에는 렌더가 끝나야 앵커 위치를 알 수 있어 예약해 둔다
    func scroll(toAnchor anchor: String) {
        pendingAnchor = anchor
        applyPendingAnchor()
    }

    private func applyPendingAnchor() {
        guard isPageReady, let anchor = pendingAnchor,
              let data = try? JSONEncoder().encode(anchor),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.scrollPreviewToAnchor(\(json));") { [weak self] found, _ in
            // 아직 렌더 전이라 찾지 못했다면 다음 렌더 후에 다시 시도한다
            if (found as? Bool) == true { self?.pendingAnchor = nil }
        }
    }

    private func renderNow() {
        guard let markdown = latestMarkdown,
              let data = try? JSONEncoder().encode(markdown),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.renderMarkdown(\(json));") { [weak self] _, _ in
            guard let self else { return }
            if let line = self.pendingScrollLine {
                self.pendingScrollLine = nil
                self.scroll(toLine: line)
            }
            self.applyPendingAnchor()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isPageReady = true
        applyBrandColors()
        renderNow()
    }

    /// 고른 테마 색을 프리뷰에 넣는다. 값을 Swift에서 만들어 넘기므로 두 벌로 어긋나지 않는다.
    func applyBrandColors() {
        guard isPageReady,
              let data = try? JSONEncoder().encode(Brand.previewCSS()),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.applyBrandCSS(\(json));")
    }

    /// 프리뷰 페이지가 다른 문서로 바뀌지 않도록 링크 이동을 가로챈다 (PLAN.md 5)
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        switch PreviewLinkRouter.action(
            for: url,
            currentPage: webView.url,
            noteDirectory: resourceHandler.noteDirectory,
            rootDirectory: resourceHandler.rootDirectory
        ) {
        case .openNote(let noteURL, let anchor):
            decisionHandler(.cancel)
            onOpenNote?(noteURL, anchor)
        case .openExternally(let target):
            decisionHandler(.cancel)
            NSWorkspace.shared.open(target)
        case .allowInPage:
            decisionHandler(.allow)
        case .block:
            decisionHandler(.cancel)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "previewScroll":
            guard let line = (message.body as? NSNumber)?.intValue else { return }
            onScrollToLine?(line)
        case "toggleTask":
            guard let line = (message.body as? NSNumber)?.intValue else { return }
            onToggleTask?(line)
        case "selectTag":
            guard let tag = message.body as? String else { return }
            onSelectTag?(tag)
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
