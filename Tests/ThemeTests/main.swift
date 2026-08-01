import AppKit
import WebKit

// 테마: 색 정의, 프리뷰로 넘기는 CSS, 아이콘이 테마별로 달라지는지 확인한다.

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

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

print("── A. 색 정의")
check("테마 5개", Theme.allCases.count == 5, "\(Theme.allCases.count)")
check("기본값은 민트", { UserDefaults.standard.removeObject(forKey: Theme.storageKey); return Theme.current == .mint }())

let logos = Theme.allCases.map(\.logo.cssHex)
check("테마마다 로고 색이 다름", Set(logos).count == Theme.allCases.count, "\(logos)")
check("라이트·다크 강조색이 서로 다름",
      Theme.allCases.allSatisfy { $0.accentLight.cssHex != $0.accentDark.cssHex })
check("아이콘 그러데이션은 밝은 쪽이 더 밝음",
      Theme.allCases.allSatisfy { theme in
          let light = theme.logoLight, deep = theme.logoDeep
          return (light.red + light.green + light.blue) > (deep.red + deep.green + deep.blue)
      })
check("16진수 변환 왕복", RGB(0x45C7B6).cssHex == "#45c7b6", RGB(0x45C7B6).cssHex)
check("알파값 표기", RGB(0x45C7B6).cssRGBA(alpha: 0.16) == "rgba(69, 199, 182, 0.16)",
      RGB(0x45C7B6).cssRGBA(alpha: 0.16))

print("\n── B. 프리뷰로 넘기는 CSS")
let mintCSS = Brand.previewCSS(for: .mint)
let plumCSS = Brand.previewCSS(for: .plum)
check("필요한 변수를 모두 정의",
      ["--brand-logo", "--brand-accent", "--brand-tint", "--brand-tint-strong"]
        .allSatisfy { mintCSS.contains($0) }, mintCSS)
check("다크 모드 블록 포함", mintCSS.contains("prefers-color-scheme: dark"))
check("테마마다 값이 다름", mintCSS != plumCSS)
check("민트 CSS에 민트 색이 들어감", mintCSS.contains(Theme.mint.logo.cssHex), mintCSS)
check("플럼 CSS에 민트 색이 없음", !plumCSS.contains(Theme.mint.logo.cssHex))

print("\n── C. 아이콘")
let mintIcon = AppIcon.bitmap(for: .mint, pixels: 128)
let copperIcon = AppIcon.bitmap(for: .copper, pixels: 128)
check("아이콘 크기", mintIcon.pixelsWide == 128 && mintIcon.pixelsHigh == 128)

// 배경(마크가 없는 위쪽)에서 색을 비교한다
let mintTop = mintIcon.colorAt(x: 64, y: 24)!
let copperTop = copperIcon.colorAt(x: 64, y: 24)!
check("테마에 따라 아이콘 색이 바뀜",
      abs(mintTop.redComponent - copperTop.redComponent) > 0.2,
      "민트 \(mintTop.redComponent) vs 코퍼 \(copperTop.redComponent)")
check("민트는 초록이 우세", mintTop.greenComponent > mintTop.redComponent)
check("코퍼는 빨강이 우세", copperTop.redComponent > copperTop.greenComponent)
check("모서리는 투명(둥근 판 밖)", mintIcon.colorAt(x: 1, y: 1)?.alphaComponent == 0,
      "\(mintIcon.colorAt(x: 1, y: 1)?.alphaComponent ?? -1)")
check("작은 크기도 그려짐", AppIcon.bitmap(for: .mint, pixels: 16).pixelsWide == 16)

print("\n── D. 프리뷰에 실제로 적용")
let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
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

/// 내보내기 툴바: 버튼을 늘어놓는 대신 복사 하나 + 저장 메뉴 하나
func checkExportToolbar() {
    let script = """
    await window.renderMarkdown("```mermaid\\nflowchart LR\\n  A --> B\\n```");
    await new Promise(r => setTimeout(r, 400));
    const bar = document.querySelector(".mermaid-toolbar");
    if (!bar) return JSON.stringify({ error: "툴바 없음" });
    bar.style.display = "flex";

    const top = bar.querySelectorAll(":scope > .mermaid-action, :scope > .mermaid-menu-wrap");
    const wrap = document.querySelector(".mermaid-menu-wrap");
    const before = wrap.classList.contains("open");
    wrap.querySelector("[data-menu='toggle']").click();
    const opened = wrap.classList.contains("open");
    const kinds = [...wrap.querySelectorAll(".mermaid-menu button")].map(b => b.dataset.export);

    const sent = [];
    window.webkit = { messageHandlers: { mermaidExport: { postMessage: (m) => sent.push(m.action) } } };
    wrap.querySelectorAll(".mermaid-menu button")[1].click();
    const closedAfterPick = !wrap.classList.contains("open");

    bar.style.display = "flex";
    document.querySelector("[data-export='copyPNG']").click();

    return JSON.stringify({ topCount: top.length, before, opened, kinds, sent, closedAfterPick });
    """
    webView.callAsyncJavaScript(script, in: nil, in: .page) { result in
        guard case .success(let value) = result, let json = value as? String,
              let data = json.data(using: .utf8),
              let r = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            check("툴바 조회", false, "\(result)")
            finish()
            return
        }

        print("\n── E. 내보내기 툴바")
        check("툴바 항목은 복사·저장 둘뿐", (r["topCount"] as? Int) == 2, "\(r["topCount"] ?? "nil")")
        check("메뉴는 처음 닫혀 있음", (r["before"] as? Bool) == false)
        check("저장을 누르면 열림", (r["opened"] as? Bool) == true)
        check("PNG·SVG 두 선택지",
              (r["kinds"] as? [String]) == ["savePNG", "saveSVG"], "\(r["kinds"] ?? "nil")")
        check("고르면 메뉴가 닫힘", (r["closedAfterPick"] as? Bool) == true)
        check("고른 형식과 복사가 각각 전달됨",
              (r["sent"] as? [String]) == ["saveSVG", "copyPNG"], "\(r["sent"] ?? "nil")")
        finish()
    }
}

nav.onReady = {
    let css = String(data: try! JSONEncoder().encode(Brand.previewCSS(for: .plum)), encoding: .utf8)!
    webView.evaluateJavaScript("window.applyBrandCSS(\(css));") { _, _ in
        webView.evaluateJavaScript("window.renderMarkdown('#정산 태그');") { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                let script = """
                const pill = document.querySelector("#content .tag");
                const root = getComputedStyle(document.documentElement);
                return JSON.stringify({
                  accentVar: root.getPropertyValue("--brand-accent").trim(),
                  pillColor: pill ? getComputedStyle(pill).color : null
                });
                """
                webView.callAsyncJavaScript(script, in: nil, in: .page) { result in
                    guard case .success(let value) = result, let json = value as? String,
                          let data = json.data(using: .utf8),
                          let r = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        check("프리뷰 조회", false, "\(result)")
                        finish()
                        return
                    }
                    let accent = (r["accentVar"] as? String) ?? ""
                    check("주입한 테마 색이 CSS 변수에 반영",
                          accent == Theme.plum.accentLight.cssHex || accent == Theme.plum.accentDark.cssHex,
                          accent)
                    check("태그가 그 색을 씀", (r["pillColor"] as? String)?.isEmpty == false,
                          "\(r["pillColor"] ?? "nil")")
                    checkExportToolbar()
                }
            }
        }
    }
}
webView.loadFileURL(resources.appendingPathComponent("preview.html"), allowingReadAccessTo: resources)
DispatchQueue.main.asyncAfter(deadline: .now() + 40) {
    check("시간 초과 없이 완료", false, "timeout")
    finish()
}
app.run()
