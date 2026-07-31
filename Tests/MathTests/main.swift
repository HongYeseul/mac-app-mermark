import AppKit
import WebKit

// KaTeX 수식이 실제로 조판되는지, 폰트가 번들에서 로드되는지 확인한다.
// 폰트는 하위 폴더 없이 평면으로 두므로 CSS의 경로 재작성이 유지되는지도 함께 본다.

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

// MARK: - A. 번들 구성

print("── A. 번들 파일")
check("katex.min.js 있음", fm.fileExists(atPath: resources.appendingPathComponent("katex.min.js").path))
check("katex.min.css 있음", fm.fileExists(atPath: resources.appendingPathComponent("katex.min.css").path))
check("texmath.js 있음", fm.fileExists(atPath: resources.appendingPathComponent("texmath.js").path))

let fonts = ((try? fm.contentsOfDirectory(atPath: resources.path)) ?? [])
    .filter { $0.hasPrefix("KaTeX_") && $0.hasSuffix(".woff2") }
check("KaTeX woff2 폰트 20개", fonts.count == 20, "\(fonts.count)개")

let css = (try? String(contentsOf: resources.appendingPathComponent("katex.min.css"), encoding: .utf8)) ?? ""
check("CSS가 폰트를 평면 경로로 참조", !css.contains("url(fonts/"), "fonts/ 경로가 남아 있음")
check("번들하지 않는 woff/ttf 대체는 제거됨",
      !css.contains(".woff)") && !css.contains(".ttf)"), "woff/ttf 참조가 남아 있음")

// CSS가 참조하는 폰트가 모두 실제로 존재하는지
let referenced = Set(css.components(separatedBy: "url(").dropFirst().compactMap { chunk -> String? in
    guard let end = chunk.firstIndex(of: ")") else { return nil }
    return String(chunk[chunk.startIndex..<end])
}.filter { $0.hasSuffix(".woff2") })
let missing = referenced.filter { !fm.fileExists(atPath: resources.appendingPathComponent($0).path) }
check("CSS가 참조하는 폰트가 모두 존재", missing.isEmpty, "없는 폰트: \(missing.sorted())")

// MARK: - B. 실제 렌더

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
final class Nav: NSObject, WKNavigationDelegate {
    var onReady: (() -> Void)?
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { onReady?(); onReady = nil }
}
let nav = Nav()
webView.navigationDelegate = nav

func finish() {
    print("\n" + (failures.isEmpty ? "ALL PASS (\(total) checks)" : "FAILURES(\(failures.count)/\(total)): \(failures.joined(separator: ", "))"))
    exit(failures.isEmpty ? 0 : 1)
}

let markdown = """
# 수식

인라인: $E = mc^2$ 끝.

밑줄이 기울임이 되면 안 된다: $x_1 + y_2 = z_3$

$$
\\int_{0}^{\\infty} e^{-x^2}\\,dx = \\frac{\\sqrt{\\pi}}{2}
$$

가격은 $5에서 $10 사이입니다.

```swift
let cost = $100
```

잘못된 수식: $\\frac{1}{$
"""

nav.onReady = {
    let encoded = String(data: try! JSONEncoder().encode(markdown), encoding: .utf8)!
    webView.evaluateJavaScript("window.renderMarkdown(\(encoded));") { _, _ in
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // callAsyncJavaScript는 전달한 문자열 자체가 async 함수 본문이다 (IIFE로 감싸면 안 됨)
            let script = """
            await document.fonts.ready;
            const katexEls = [...document.querySelectorAll("#content .katex")];
            const paragraphs = [...document.querySelectorAll("#content p")].map(p => p.textContent);
            return JSON.stringify({
              katexCount: katexEls.length,
              hasDisplay: !!document.querySelector("#content .katex-display"),
              emInsideMath: !!document.querySelector("#content .katex em"),
              mathFont: getComputedStyle(document.querySelector("#content .katex .mord")).fontFamily,
              mathFontLoaded: document.fonts.check('10px "KaTeX_Math"'),
              mainFontLoaded: document.fonts.check('10px "KaTeX_Main"'),
              codeText: document.querySelector("#content pre code")?.textContent || "",
              currencyParagraph: paragraphs.find(t => t.includes("가격은")) || "",
              libs: { katex: typeof katex, texmath: typeof texmath }
            });
            """
            webView.callAsyncJavaScript(script, in: nil, in: .page) { result in
                guard case .success(let value) = result,
                      let json = value as? String,
                      let data = json.data(using: .utf8),
                      let r = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    check("렌더 결과 조회", false, "\(result)")
                    finish()
                    return
                }

                print("\n── B. 수식 렌더")
                let libs = r["libs"] as? [String: String] ?? [:]
                check("katex / texmath 전역 로드", libs["katex"] == "object" && libs["texmath"] == "function", "\(libs)")
                // 인라인 2개 + 블록 1개 (잘못된 수식은 오류 표시로 렌더될 수 있어 최소값으로 본다)
                check("수식 3개 이상 조판", (r["katexCount"] as? Int ?? 0) >= 3, "\(r["katexCount"] ?? "nil")")
                check("블록 수식은 display 모드", (r["hasDisplay"] as? Bool) == true)
                check("수식 안 밑줄이 기울임이 되지 않음", (r["emInsideMath"] as? Bool) == false)

                print("\n── C. 폰트")
                check("수식이 KaTeX_Math로 그려짐",
                      (r["mathFont"] as? String)?.contains("KaTeX_Math") == true, "\(r["mathFont"] ?? "nil")")
                check("KaTeX_Math 폰트 로드됨", (r["mathFontLoaded"] as? Bool) == true)
                check("KaTeX_Main 폰트 로드됨", (r["mainFontLoaded"] as? Bool) == true)

                print("\n── D. 오탐 방지")
                check("통화 표기는 수식으로 잡지 않음",
                      (r["currencyParagraph"] as? String)?.contains("$5") == true,
                      "\(r["currencyParagraph"] ?? "nil")")
                check("코드 블록 안의 $는 그대로",
                      (r["codeText"] as? String)?.contains("$100") == true, "\(r["codeText"] ?? "nil")")

                finish()
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
