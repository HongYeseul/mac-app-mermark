import AppKit
import WebKit
import UniformTypeIdentifiers

/// 오프스크린 WKWebView에서 Mermaid 코드를 단독 렌더한 뒤 takeSnapshot으로 고해상도 PNG를 뽑는다. (PLAN.md 3-b)
final class MermaidExporter: NSObject, WKNavigationDelegate {
    static let shared = MermaidExporter()

    enum Destination {
        case savePanel
        case clipboard
    }

    private enum Kind {
        case png(scale: CGFloat, destination: Destination)
        case svgSave
    }

    private struct Job {
        let code: String
        let kind: Kind
    }

    private let webView: WKWebView
    private let hostWindow: NSWindow
    private var isPageReady = false
    private var isExporting = false
    private var pendingJobs: [Job] = []

    // 렌더 측정 전에는 충분히 큰 프레임이어야 SVG가 자연 크기로 배치된다
    private static let stagingSize = NSSize(width: 2000, height: 2000)

    private override init() {
        let initialFrame = NSRect(origin: .zero, size: Self.stagingSize)
        webView = WKWebView(frame: initialFrame, configuration: WKWebViewConfiguration())
        hostWindow = NSWindow(contentRect: initialFrame, styleMask: .borderless, backing: .buffered, defer: false)
        super.init()

        webView.navigationDelegate = self
        // 투명 배경 스냅샷용 사설 KVC — PLAN.md 3-b 주의사항 참고
        webView.setValue(false, forKey: "drawsBackground")
        hostWindow.contentView = webView
        hostWindow.isReleasedWhenClosed = false

        if let url = Bundle.main.url(forResource: "export", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    func exportPNG(code: String, scale: CGFloat = 2, destination: Destination) {
        pendingJobs.append(Job(code: code, kind: .png(scale: scale, destination: destination)))
        processNextJobIfPossible()
    }

    func exportSVG(code: String) {
        pendingJobs.append(Job(code: code, kind: .svgSave))
        processNextJobIfPossible()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isPageReady = true
        processNextJobIfPossible()
    }

    private func processNextJobIfPossible() {
        guard isPageReady, !isExporting, !pendingJobs.isEmpty else { return }
        isExporting = true
        let job = pendingJobs.removeFirst()

        switch job.kind {
        case .png:
            renderPNG(job: job)
        case .svgSave:
            renderSVG(job: job)
        }
    }

    private func renderPNG(job: Job) {
        hostWindow.setContentSize(Self.stagingSize)
        webView.callAsyncJavaScript(
            "return await window.renderForExport(code);",
            arguments: ["code": job.code],
            in: nil,
            in: .page
        ) { [weak self] result in
            switch result {
            case .success(let value):
                guard let size = value as? [String: Any],
                      let width = (size["width"] as? NSNumber)?.doubleValue,
                      let height = (size["height"] as? NSNumber)?.doubleValue else {
                    self?.finishJob(error: "렌더 결과 크기를 읽지 못했습니다")
                    return
                }
                self?.snapshot(job: job, width: width, height: height)
            case .failure(let error):
                self?.finishJob(error: "Mermaid 렌더 실패: \(error.localizedDescription)")
            }
        }
    }

    private func renderSVG(job: Job) {
        webView.callAsyncJavaScript(
            "return await window.renderForExportSVG(code);",
            arguments: ["code": job.code],
            in: nil,
            in: .page
        ) { [weak self] result in
            switch result {
            case .success(let value):
                guard let svg = value as? String else {
                    self?.finishJob(error: "SVG 렌더 결과를 읽지 못했습니다")
                    return
                }
                self?.deliverSVG(svg)
            case .failure(let error):
                self?.finishJob(error: "Mermaid 렌더 실패: \(error.localizedDescription)")
            }
        }
    }

    private func deliverSVG(_ svg: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.svg]
        panel.nameFieldStringValue = "diagram.svg"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                let content = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + svg
                do {
                    try content.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    self.showError("저장 실패: \(error.localizedDescription)")
                }
            }
            self.finishJob(error: nil)
        }
    }

    private func snapshot(job: Job, width: Double, height: Double) {
        guard case .png(let scale, let destination) = job.kind else {
            finishJob(error: "잘못된 작업 종류")
            return
        }
        hostWindow.setContentSize(NSSize(width: width, height: height))

        // 리사이즈가 웹 프로세스 레이아웃에 반영될 시간을 준 뒤 스냅샷
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            let config = WKSnapshotConfiguration()
            config.rect = NSRect(x: 0, y: 0, width: width, height: height)
            // snapshotWidth는 포인트 단위 → 결과 픽셀은 backingScaleFactor 배. 요청 스케일이 그대로 나오도록 보정.
            let backingScale = self.hostWindow.backingScaleFactor > 0 ? self.hostWindow.backingScaleFactor : 1
            config.snapshotWidth = NSNumber(value: width * scale / backingScale)
            self.webView.takeSnapshot(with: config) { image, error in
                guard let image else {
                    self.finishJob(error: "스냅샷 실패: \(error?.localizedDescription ?? "unknown")")
                    return
                }
                self.deliver(image: image, destination: destination)
            }
        }
    }

    private func deliver(image: NSImage, destination: Destination) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            finishJob(error: "PNG 인코딩 실패")
            return
        }

        switch destination {
        case .clipboard:
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.declareTypes([.png, .tiff], owner: nil)
            pasteboard.setData(png, forType: .png)
            pasteboard.setData(tiff, forType: .tiff)
            finishJob(error: nil)
        case .savePanel:
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = "diagram.png"
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    do {
                        try png.write(to: url)
                    } catch {
                        self.showError("저장 실패: \(error.localizedDescription)")
                    }
                }
                self.finishJob(error: nil)
            }
        }
    }

    private func finishJob(error: String?) {
        if let error { showError(error) }
        isExporting = false
        processNextJobIfPossible()
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Mermaid 내보내기 오류"
        alert.informativeText = message
        alert.runModal()
    }
}
