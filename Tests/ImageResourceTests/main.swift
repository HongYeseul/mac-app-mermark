import AppKit
import WebKit

// 노트 기준 상대경로 이미지가 실제 WKWebView에서 로드되는지 확인한다.
// 경로 해석 규칙(노트 폴더 밖 차단 포함)과 실제 렌더를 함께 본다.

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

let fm = FileManager.default
let root = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("mermark-image-\(ProcessInfo.processInfo.processIdentifier)")
let folder = root.appendingPathComponent("노트 폴더")
let noteDir = folder.appendingPathComponent("하위 폴더")
try! fm.createDirectory(at: noteDir, withIntermediateDirectories: true)
try! fm.createDirectory(at: folder.appendingPathComponent("assets"), withIntermediateDirectories: true)

/// 지정한 픽셀 크기의 빨간 PNG를 만든다.
/// NSImage.lockFocus는 레티나에서 2배 크기로 만들어지므로 비트맵을 직접 다룬다.
func writePNG(to url: URL, pixels: Int) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.red.setFill()
    NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

writePNG(to: noteDir.appendingPathComponent("그림.png"), pixels: 8)
writePNG(to: folder.appendingPathComponent("assets/로고.png"), pixels: 16)
try! "비밀".write(to: root.appendingPathComponent("노트 폴더밖.txt"), atomically: true, encoding: .utf8)

func url(_ string: String) -> URL { URL(string: string)! }
func resolve(_ string: String) -> URL? {
    LocalResourceHandler.resolve(url(string), noteDirectory: noteDir, rootDirectory: folder)
}

// MARK: - A. 경로 해석 규칙

// 전체 경로로 비교한다. lastPathComponent만 보면 상위 폴더가 잘못 잡혀도 통과해 버린다.
func path(_ url: URL) -> String { url.standardizedFileURL.path }

print("── A. 경로 해석")
check("노트 기준 상대경로는 노트가 든 폴더에서 풀린다",
      resolve("mermark-local://note/%EA%B7%B8%EB%A6%BC.png").map(path) == path(noteDir.appendingPathComponent("그림.png")),
      "\(resolve("mermark-local://note/%EA%B7%B8%EB%A6%BC.png")?.path ?? "nil")")
check("노트 기준 하위 폴더 경로",
      resolve("mermark-local://note/img/a.png").map(path) == path(noteDir.appendingPathComponent("img/a.png")),
      "\(resolve("mermark-local://note/img/a.png")?.path ?? "nil")")
check("노트 폴더 최상위 기준 경로",
      resolve("mermark-local://folder/assets/%EB%A1%9C%EA%B3%A0.png").map(path)
        == path(folder.appendingPathComponent("assets/로고.png")),
      "\(resolve("mermark-local://folder/assets/%EB%A1%9C%EA%B3%A0.png")?.path ?? "nil")")
check("노트 기준 상위 폴더 이동은 노트 폴더 안이면 허용",
      resolve("mermark-local://note/../assets/%EB%A1%9C%EA%B3%A0.png").map(path)
        == path(folder.appendingPathComponent("assets/로고.png")),
      "\(resolve("mermark-local://note/../assets/%EB%A1%9C%EA%B3%A0.png")?.path ?? "nil")")

check("노트 폴더 밖으로 나가는 경로는 거부", resolve("mermark-local://note/../../%EB%B3%BC%ED%8A%B8%EB%B0%96.txt") == nil,
      "\(resolve("mermark-local://note/../../%EB%B3%BC%ED%8A%B8%EB%B0%96.txt")?.path ?? "nil")")
check("깊은 상위 이동도 거부", resolve("mermark-local://note/../../../../etc/hosts") == nil)
check("알 수 없는 host는 거부", resolve("mermark-local://other/그림.png") == nil)
check("빈 경로는 거부", resolve("mermark-local://note/") == nil)
check("노트 폴더가 없으면 거부",
      LocalResourceHandler.resolve(url("mermark-local://note/a.png"), noteDirectory: noteDir, rootDirectory: nil) == nil)

// MARK: - B. 실제 WKWebView 렌더

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let handler = LocalResourceHandler()
handler.noteDirectory = noteDir
handler.rootDirectory = folder

let configuration = WKWebViewConfiguration()
configuration.setURLSchemeHandler(handler, forURLScheme: LocalResourceHandler.scheme)
let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)

final class Nav: NSObject, WKNavigationDelegate {
    var onReady: (() -> Void)?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onReady?()
        onReady = nil
    }
}
let nav = Nav()
webView.navigationDelegate = nav

func finish() {
    try? fm.removeItem(at: root)
    print("\n" + (failures.isEmpty ? "ALL PASS (\(total) checks)" : "FAILURES(\(failures.count)/\(total)): \(failures.joined(separator: ", "))"))
    exit(failures.isEmpty ? 0 : 1)
}

let markdown = """
# 이미지 문서

노트 기준: ![그림](./그림.png)

노트 폴더 기준: ![로고](/assets/로고.png)

외부 주소: ![원격](https://example.com/x.png)

없는 파일: ![없음](./없는파일.png)
"""

nav.onReady = {
    let encoded = String(data: try! JSONEncoder().encode(markdown), encoding: .utf8)!
    // 이미지 로드 실패를 잡아두면 실패 시 원인을 바로 알 수 있다 (error는 버블링하지 않아 캡처 단계로 듣는다)
    let installErrorCapture = """
    window.__imgErrors = [];
    document.addEventListener("error", (e) => {
      if (e.target && e.target.tagName === "IMG") window.__imgErrors.push(e.target.getAttribute("src"));
    }, true);
    "ok"
    """
    webView.evaluateJavaScript(installErrorCapture) { _, _ in
    webView.evaluateJavaScript("window.renderMarkdown(\(encoded));") { _, _ in
        // 이미지 로드는 렌더 이후 비동기로 끝난다
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let script = """
            (() => {
              const imgs = [...document.querySelectorAll("#content img")];
              return JSON.stringify(imgs.map(i => ({
                src: i.getAttribute("src"),
                width: i.naturalWidth,
                complete: i.complete,
                failed: (window.__imgErrors || []).includes(i.getAttribute("src"))
              })));
            })()
            """
            webView.evaluateJavaScript(script) { value, error in
                guard let json = value as? String,
                      let data = json.data(using: .utf8),
                      let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    check("이미지 정보 조회", false, "\(String(describing: value)) \(String(describing: error))")
                    finish()
                    return
                }

                print("\n── B. 실제 렌더")
                check("이미지 4개 렌더", items.count == 4, "\(items.count)")

                let noteImage = items[0]
                check("노트 기준 이미지가 전용 스킴으로 치환",
                      (noteImage["src"] as? String)?.hasPrefix("mermark-local://note/") == true,
                      "\(noteImage["src"] ?? "nil")")
                // markdown-it이 이미 인코딩한 값을 다시 인코딩하면 "%"가 "%25"가 되어 로드가 깨진다
                check("퍼센트 인코딩이 중복되지 않음",
                      (noteImage["src"] as? String)?.contains("%25") == false,
                      "\(noteImage["src"] ?? "nil")")
                check("노트 기준 이미지 실제 로드됨 (8px)",
                      (noteImage["width"] as? Int) == 8, "\(noteImage["width"] ?? "nil")")

                let folderImage = items[1]
                check("노트 폴더 기준 이미지가 folder 호스트로 치환",
                      (folderImage["src"] as? String)?.hasPrefix("mermark-local://folder/") == true,
                      "\(folderImage["src"] ?? "nil")")
                check("노트 폴더 기준 이미지 실제 로드됨 (16px)",
                      (folderImage["width"] as? Int) == 16, "\(folderImage["width"] ?? "nil")")

                let remote = items[2]
                check("외부 https 주소는 그대로 둠",
                      (remote["src"] as? String) == "https://example.com/x.png", "\(remote["src"] ?? "nil")")

                let missing = items[3]
                check("없는 파일은 로드되지 않음", (missing["width"] as? Int) == 0, "\(missing["width"] ?? "nil")")

                finish()
            }
        }
    }
    }
}

webView.loadFileURL(resources.appendingPathComponent("preview.html"), allowingReadAccessTo: resources)

DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
    check("시간 초과 없이 완료", false, "timeout")
    finish()
}
app.run()
