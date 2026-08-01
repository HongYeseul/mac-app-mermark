import AppKit
import WebKit
import UniformTypeIdentifiers

/// 오프스크린 WKWebView에서 Mermaid 코드를 단독 렌더한 뒤 takeSnapshot으로 고해상도 PNG를 뽑는다. (PLAN.md 3-b)
final class MermaidExporter: NSObject, WKNavigationDelegate {
    static let shared = MermaidExporter()

    enum Destination {
        case savePanel
        case clipboard
        case file(URL)
    }

    private enum Kind {
        case png(destination: Destination)
        case svgSave
    }

    private struct Job {
        let code: String
        let kind: Kind
        let options: ExportOptions
    }

    /// 일괄 내보내기 진행 상태. 파일마다 알림을 띄우지 않고 끝에 한 번만 요약한다.
    private struct Batch {
        var written: [URL] = []
        var failures = 0
        /// 크기 때문에 배율이 낮아진 다이어그램 수
        var reducedCount = 0
        let completion: (_ written: [URL], _ failures: Int, _ reduced: Int) -> Void
    }

    private let webView: WKWebView
    private let hostWindow: NSWindow
    private var isPageReady = false
    private var isExporting = false
    private var pendingJobs: [Job] = []
    private var batch: Batch?
    /// 단건 내보내기에서 배율이 낮아졌을 때 마칠 무렵 알릴 문구
    private var pendingScaleNotice: String?

    // 렌더 측정 전에는 충분히 큰 프레임이어야 SVG가 자연 크기로 배치된다
    private static let stagingSize = NSSize(width: 2000, height: 2000)
    /// 아주 긴 다이어그램에서 스냅샷이 과도하게 커지는 것을 막는다
    static let maxPixelDimension: Double = 8192

    /// 픽셀 상한을 넘지 않도록 낮춘 실제 배율.
    /// 1x로도 상한을 넘는 다이어그램은 더 낮추지 않고 1x로 둔다(글자가 뭉개지므로).
    static func effectiveScale(
        requested: Int,
        width: Double,
        height: Double,
        maxDimension: Double = maxPixelDimension
    ) -> Double {
        let longestSide = max(width, height)
        guard longestSide > 0 else { return Double(requested) }
        return max(1, min(Double(requested), maxDimension / longestSide))
    }

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

        if let resources = Self.resourcesURL {
            webView.loadFileURL(resources.appendingPathComponent("export.html"), allowingReadAccessTo: resources)
        }
    }

    /// 기본값은 앱 번들. 검증 하네스가 소스 트리의 Resources를 가리키도록 바꿔 쓴다.
    static var resourcesURL: URL? = Bundle.main.resourceURL

    // MARK: - 공개 API

    func exportPNG(code: String, destination: Destination) {
        enqueue(Job(code: code, kind: .png(destination: destination), options: .current))
    }

    func exportSVG(code: String) {
        enqueue(Job(code: code, kind: .svgSave, options: .current))
    }

    /// 문서 안의 모든 다이어그램을 `문서명-1.png` 형태로 한 폴더에 저장한다.
    func exportAll(codes: [String], baseName: String) {
        guard !codes.isEmpty else {
            showAlert(title: "내보낼 다이어그램이 없습니다", message: "이 문서에는 mermaid 블록이 없습니다.")
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "이 폴더에 저장"
        panel.message = "다이어그램 \(codes.count)개를 저장할 폴더를 선택하세요"
        guard panel.runModal() == .OK, let directory = panel.url else { return }

        exportAll(codes: codes, baseName: baseName, to: directory) { [weak self] written, failures, reduced in
            guard let self else { return }
            guard !written.isEmpty else {
                self.showAlert(title: "내보내기 실패", message: "다이어그램을 저장하지 못했습니다.")
                return
            }
            var message = failures == 0
                ? "다이어그램 \(written.count)개를 저장했습니다."
                : "다이어그램 \(written.count)개를 저장했고 \(failures)개는 실패했습니다."
            if reduced > 0 {
                message += "\n\(reduced)개는 크기가 커서 배율을 낮춰 저장했습니다."
            }
            self.showAlert(title: "일괄 내보내기 완료", message: message)
            NSWorkspace.shared.activateFileViewerSelecting(written)
        }
    }

    /// 폴더 선택 없이 바로 저장한다. 파일명은 `문서명-1.png`, `문서명-2.png` 순.
    func exportAll(codes: [String], baseName: String, to directory: URL,
                   completion: @escaping (_ written: [URL], _ failures: Int, _ reduced: Int) -> Void) {
        guard !codes.isEmpty else {
            completion([], 0, 0)
            return
        }
        batch = Batch(completion: completion)
        let options = ExportOptions.current
        for (index, code) in codes.enumerated() {
            let url = directory.appendingPathComponent("\(baseName)-\(index + 1).png")
            enqueue(Job(code: code, kind: .png(destination: .file(url)), options: options))
        }
    }

    // MARK: - 작업 큐

    private func enqueue(_ job: Job) {
        pendingJobs.append(job)
        processNextJobIfPossible()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isPageReady = true
        processNextJobIfPossible()
    }

    private func processNextJobIfPossible() {
        guard isPageReady, !isExporting else { return }
        guard !pendingJobs.isEmpty else {
            finalizeBatchIfNeeded()
            return
        }
        isExporting = true
        let job = pendingJobs.removeFirst()

        switch job.kind {
        case .png:
            renderPNG(job: job)
        case .svgSave:
            renderSVG(job: job)
        }
    }

    private func isDarkTheme(_ options: ExportOptions) -> Bool {
        let systemIsDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return options.theme.mermaidTheme(systemIsDark: systemIsDark) == "dark"
    }

    // MARK: - PNG

    private func renderPNG(job: Job) {
        hostWindow.setContentSize(Self.stagingSize)
        let dark = isDarkTheme(job.options)
        webView.callAsyncJavaScript(
            "return await window.renderForExport(code, theme, background);",
            arguments: [
                "code": job.code,
                "theme": dark ? "dark" : "default",
                "background": job.options.background.cssValue(isDarkTheme: dark),
            ],
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

    private func snapshot(job: Job, width: Double, height: Double) {
        guard case .png(let destination) = job.kind else {
            finishJob(error: "잘못된 작업 종류")
            return
        }
        hostWindow.setContentSize(NSSize(width: width, height: height))

        // 요청 배율이 픽셀 상한을 넘으면 상한에 맞춰 자동으로 낮춘다.
        // 조용히 낮추면 3x를 골랐는데 왜 작게 나오는지 알 수 없으므로 알려준다.
        let scale = Self.effectiveScale(requested: job.options.scale, width: width, height: height)
        if scale < Double(job.options.scale) {
            if batch != nil {
                batch?.reducedCount += 1
            } else {
                pendingScaleNotice = String(
                    format: "다이어그램이 커서 %dx 대신 %.1fx로 내보냈습니다. (한 변 최대 %d픽셀)",
                    job.options.scale, scale, Int(Self.maxPixelDimension)
                )
            }
        }

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

        case .file(let url):
            do {
                try png.write(to: url)
                batch?.written.append(url)
                finishJob(error: nil)
            } catch {
                batch?.failures += 1
                finishJob(error: batch == nil ? "저장 실패: \(error.localizedDescription)" : nil)
            }

        case .savePanel:
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = "diagram.png"
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    do {
                        try png.write(to: url)
                    } catch {
                        self.showAlert(title: "Mermaid 내보내기 오류", message: "저장 실패: \(error.localizedDescription)")
                    }
                }
                self.finishJob(error: nil)
            }
        }
    }

    // MARK: - SVG

    private func renderSVG(job: Job) {
        webView.callAsyncJavaScript(
            "return await window.renderForExportSVG(code, theme);",
            arguments: [
                "code": job.code,
                "theme": isDarkTheme(job.options) ? "dark" : "default",
            ],
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
                    self.showAlert(title: "Mermaid 내보내기 오류", message: "저장 실패: \(error.localizedDescription)")
                }
            }
            self.finishJob(error: nil)
        }
    }

    // MARK: - 마무리

    private func finishJob(error: String?) {
        if let error { showAlert(title: "Mermaid 내보내기 오류", message: error) }
        if let notice = pendingScaleNotice {
            pendingScaleNotice = nil
            showAlert(title: "해상도를 낮춰 내보냈습니다", message: notice)
        }
        isExporting = false
        processNextJobIfPossible()
    }

    private func finalizeBatchIfNeeded() {
        guard let batch else { return }
        self.batch = nil
        batch.completion(batch.written, batch.failures, batch.reducedCount)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
