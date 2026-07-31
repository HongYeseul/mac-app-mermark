import AppKit
import WebKit

// 내보내기 옵션이 실제 PNG 픽셀에 반영되는지 확인한다.
// 앱 번들 대신 소스 트리의 Resources/export.html을 직접 로드해 렌더 → 스냅샷까지 실행한다.

var failures: [String] = []
var total = 0
func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
    total += 1
    print("\(condition ? "PASS" : "FAIL"): \(name)\(condition ? "" : "  → \(detail())")")
    if !condition { failures.append(name) }
}

guard let resourcePath = ProcessInfo.processInfo.environment["MERMARK_RESOURCES"] else {
    print("FAIL: MERMARK_RESOURCES 환경변수가 필요합니다")
    exit(2)
}
let resources = URL(fileURLWithPath: resourcePath)

// MARK: - A. 옵션 매핑 (순수 로직)

print("── A. 옵션 매핑")
check("라이트 테마 → default", ExportTheme.light.mermaidTheme(systemIsDark: true) == "default")
check("다크 테마 → dark", ExportTheme.dark.mermaidTheme(systemIsDark: false) == "dark")
check("시스템 따름은 시스템 값을 반영",
      ExportTheme.system.mermaidTheme(systemIsDark: true) == "dark"
      && ExportTheme.system.mermaidTheme(systemIsDark: false) == "default")
check("투명 배경", ExportBackground.transparent.cssValue(isDarkTheme: false) == "transparent")
check("흰 배경은 테마와 무관", ExportBackground.white.cssValue(isDarkTheme: true) == "#ffffff")
check("테마 맞춤 배경은 다크에서 어두운 색",
      ExportBackground.theme.cssValue(isDarkTheme: true) == "#1e1e1e"
      && ExportBackground.theme.cssValue(isDarkTheme: false) == "#ffffff")

UserDefaults.standard.removeObject(forKey: ExportOptions.scaleKey)
UserDefaults.standard.removeObject(forKey: ExportOptions.themeKey)
UserDefaults.standard.removeObject(forKey: ExportOptions.backgroundKey)
let defaults = ExportOptions.current
check("기본값은 2x / 라이트 / 투명",
      defaults.scale == 2 && defaults.theme == .light && defaults.background == .transparent,
      "\(defaults)")

UserDefaults.standard.set(99, forKey: ExportOptions.scaleKey)
check("범위 밖 배율은 3x로 제한", ExportOptions.current.scale == 3, "\(ExportOptions.current.scale)")
UserDefaults.standard.removeObject(forKey: ExportOptions.scaleKey)

// MARK: - B. 실제 렌더 → 스냅샷

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let sampleCode = "flowchart LR\n    A[시작] --> B[끝]"

final class Harness: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let window: NSWindow
    private var onReady: (() -> Void)?

    init(resources: URL) {
        let frame = NSRect(x: 0, y: 0, width: 2000, height: 2000)
        webView = WKWebView(frame: frame, configuration: WKWebViewConfiguration())
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        window.contentView = webView
        window.isReleasedWhenClosed = false
    }

    func load(completion: @escaping () -> Void) {
        onReady = completion
        let html = resources.appendingPathComponent("export.html")
        webView.loadFileURL(html, allowingReadAccessTo: resources)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onReady?()
        onReady = nil
    }

    /// 실제 앱과 동일한 순서: 렌더로 크기 측정 → 창 리사이즈 → takeSnapshot
    func exportPNG(code: String, theme: String, background: String, scale: Double,
                   completion: @escaping (NSBitmapImageRep?) -> Void) {
        window.setContentSize(NSSize(width: 2000, height: 2000))
        webView.callAsyncJavaScript(
            "return await window.renderForExport(code, theme, background);",
            arguments: ["code": code, "theme": theme, "background": background],
            in: nil, in: .page
        ) { result in
            guard case .success(let value) = result,
                  let size = value as? [String: Any],
                  let width = (size["width"] as? NSNumber)?.doubleValue,
                  let height = (size["height"] as? NSNumber)?.doubleValue else {
                completion(nil)
                return
            }
            self.window.setContentSize(NSSize(width: width, height: height))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let config = WKSnapshotConfiguration()
                config.rect = NSRect(x: 0, y: 0, width: width, height: height)
                let backing = self.window.backingScaleFactor > 0 ? self.window.backingScaleFactor : 1
                config.snapshotWidth = NSNumber(value: width * scale / backing)
                self.webView.takeSnapshot(with: config) { image, _ in
                    guard let tiff = image?.tiffRepresentation else {
                        completion(nil)
                        return
                    }
                    completion(NSBitmapImageRep(data: tiff))
                }
            }
        }
    }

    func exportSVG(code: String, theme: String, completion: @escaping (String?) -> Void) {
        webView.callAsyncJavaScript(
            "return await window.renderForExportSVG(code, theme);",
            arguments: ["code": code, "theme": theme],
            in: nil, in: .page
        ) { result in
            completion((try? result.get()) as? String)
        }
    }
}

let harness = Harness(resources: resources)
var done = false

func finish() {
    print("\n" + (failures.isEmpty ? "ALL PASS (\(total) checks)" : "FAILURES(\(failures.count)/\(total)): \(failures.joined(separator: ", "))"))
    exit(failures.isEmpty ? 0 : 1)
}

harness.load {
    print("\n── B. 배율이 픽셀 크기에 반영")
    harness.exportPNG(code: sampleCode, theme: "default", background: "transparent", scale: 1) { oneX in
        guard let oneX else {
            check("1x 스냅샷 생성", false, "nil")
            finish()
            return
        }
        let baseWidth = oneX.pixelsWide
        check("1x 스냅샷 생성", baseWidth > 0, "\(baseWidth)")

        harness.exportPNG(code: sampleCode, theme: "default", background: "transparent", scale: 3) { threeX in
            guard let threeX else {
                check("3x 스냅샷 생성", false, "nil")
                finish()
                return
            }
            check("3x는 1x의 3배 폭", abs(threeX.pixelsWide - baseWidth * 3) <= 3,
                  "1x \(baseWidth) vs 3x \(threeX.pixelsWide)")
            check("투명 배경이면 모서리 알파 0", threeX.colorAt(x: 0, y: 0)?.alphaComponent == 0,
                  "\(threeX.colorAt(x: 0, y: 0)?.alphaComponent ?? -1)")

            print("\n── C. 배경 옵션")
            harness.exportPNG(code: sampleCode, theme: "default", background: "#ffffff", scale: 2) { white in
                guard let white, let corner = white.colorAt(x: 0, y: 0) else {
                    check("흰 배경 스냅샷 생성", false, "nil")
                    finish()
                    return
                }
                check("흰 배경이면 모서리가 불투명", corner.alphaComponent == 1, "\(corner.alphaComponent)")
                check("흰 배경이면 모서리가 흰색",
                      corner.redComponent > 0.95 && corner.greenComponent > 0.95 && corner.blueComponent > 0.95,
                      "\(corner)")

                print("\n── D. 테마 옵션")
                harness.exportPNG(code: sampleCode, theme: "dark", background: "#1e1e1e", scale: 2) { dark in
                    guard let dark, let darkCorner = dark.colorAt(x: 0, y: 0) else {
                        check("다크 배경 스냅샷 생성", false, "nil")
                        finish()
                        return
                    }
                    check("테마 맞춤 배경이면 모서리가 어두움",
                          darkCorner.alphaComponent == 1 && darkCorner.redComponent < 0.2,
                          "\(darkCorner)")

                    harness.exportSVG(code: sampleCode, theme: "dark") { darkSVG in
                        harness.exportSVG(code: sampleCode, theme: "default") { lightSVG in
                            guard let darkSVG, let lightSVG else {
                                check("SVG 렌더", false, "nil")
                                finish()
                                return
                            }
                            check("SVG도 테마에 따라 달라짐", darkSVG != lightSVG)
                            check("SVG에 foreignObject 없음 (외부 앱 호환)", !darkSVG.contains("foreignObject"))
                            check("SVG에 xmlns 선언 포함", darkSVG.contains("xmlns=\"http://www.w3.org/2000/svg\""))
                            finish()
                        }
                    }
                }
            }
        }
    }
}

DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
    check("시간 초과 없이 완료", false, "timeout")
    finish()
}
app.run()
