import AppKit
import WebKit

// 프리뷰 링크 라우팅 규칙과, 실제 렌더에서의 헤딩 앵커·링크 치환을 검증한다.

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

let folder = URL(fileURLWithPath: "/tmp/mermark-링크테스트")
let noteDir = folder.appendingPathComponent("하위 폴더")
let page = URL(string: "file:///Applications/Mermark.app/Contents/Resources/preview.html")!

func route(_ string: String) -> PreviewLinkRouter.Action {
    PreviewLinkRouter.action(
        for: URL(string: string)!,
        currentPage: page,
        noteDirectory: noteDir,
        rootDirectory: folder
    )
}

// MARK: - A. 라우팅 규칙

print("── A. 링크 라우팅")
check("노트 기준 .md 링크는 앱에서 연다",
      route("mermark-local://note/%EB%8B%A4%EB%A5%B8%20%EB%85%B8%ED%8A%B8.md")
        == .openNote(noteDir.appendingPathComponent("다른 노트.md"), anchor: nil),
      "\(route("mermark-local://note/%EB%8B%A4%EB%A5%B8%20%EB%85%B8%ED%8A%B8.md"))")

check("앵커가 붙은 .md 링크는 앵커까지 전달",
      route("mermark-local://note/./other.md#%EC%84%B9%EC%85%98")
        == .openNote(noteDir.appendingPathComponent("other.md"), anchor: "섹션"),
      "\(route("mermark-local://note/./other.md#%EC%84%B9%EC%85%98"))")

check("노트 폴더 최상위 기준 .md 링크",
      route("mermark-local://folder/폴더/note.md")
        == .openNote(folder.appendingPathComponent("폴더/note.md"), anchor: nil),
      "\(route("mermark-local://folder/폴더/note.md"))")

check("대문자 확장자도 노트로 인식",
      { if case .openNote = route("mermark-local://note/A.MD") { return true } else { return false } }(),
      "\(route("mermark-local://note/A.MD"))")

check("노트 폴더 안의 PDF는 기본 앱으로",
      route("mermark-local://note/문서.pdf")
        == .openExternally(noteDir.appendingPathComponent("문서.pdf")),
      "\(route("mermark-local://note/문서.pdf"))")

check("노트 폴더 밖 .md 링크는 막는다", route("mermark-local://note/../../외부.md") == .block,
      "\(route("mermark-local://note/../../외부.md"))")

print("\n── B. 외부 주소와 같은 문서 앵커")
check("https는 기본 브라우저로",
      route("https://example.com/a") == .openExternally(URL(string: "https://example.com/a")!))
check("mailto도 외부로", route("mailto:a@b.com") == .openExternally(URL(string: "mailto:a@b.com")!))
check("같은 문서 앵커는 웹뷰에 맡긴다",
      route(page.absoluteString + "#%EC%84%B9%EC%85%98") == .allowInPage,
      "\(route(page.absoluteString + "#섹션"))")
check("다른 file:// 문서로의 이동은 막는다",
      route("file:///etc/hosts") == .block, "\(route("file:///etc/hosts"))")
check("프래그먼트가 있어도 다른 문서면 막는다",
      route("file:///etc/hosts#x") == .block, "\(route("file:///etc/hosts#x"))")
check("알 수 없는 스킴은 막는다", route("javascript:alert(1)") == .block,
      "\(route("javascript:alert(1)"))")

// MARK: - C. 실제 렌더에서 앵커 id와 링크 치환

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 700, height: 600))
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
# 문서 제목

[다른 노트](./다른%20노트.md)
[앵커 링크](./other.md#섹션-이름)
[노트 폴더 기준](/폴더/note.md)
[외부](https://example.com)
[같은 문서](#두-번째-섹션)

## 두 번째 섹션

내용

## 두 번째 섹션

같은 제목이 또 나온다

### 특수문자! 제목?
"""

nav.onReady = {
    let encoded = String(data: try! JSONEncoder().encode(markdown), encoding: .utf8)!
    webView.evaluateJavaScript("window.renderMarkdown(\(encoded));") { _, _ in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let script = """
            (() => {
              const headings = [...document.querySelectorAll("#content h1,#content h2,#content h3")]
                .map(h => h.id);
              const links = [...document.querySelectorAll("#content a")].map(a => a.getAttribute("href"));
              const anchorHit = window.scrollPreviewToAnchor("두-번째-섹션");
              return JSON.stringify({ headings, links, anchorHit });
            })()
            """
            webView.evaluateJavaScript(script) { value, error in
                guard let json = value as? String,
                      let data = json.data(using: .utf8),
                      let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let headings = result["headings"] as? [String],
                      let links = result["links"] as? [String] else {
                    check("렌더 결과 조회", false, "\(String(describing: value)) \(String(describing: error))")
                    finish()
                    return
                }

                print("\n── C. 헤딩 앵커")
                check("헤딩마다 id 생성", headings.count == 4, "\(headings)")
                check("한글 제목 슬러그", headings.first == "문서-제목", "\(headings)")
                check("중복 제목은 번호로 구분",
                      headings[1] == "두-번째-섹션" && headings[2] == "두-번째-섹션-1", "\(headings)")
                check("특수문자 제거", headings[3] == "특수문자-제목", "\(headings)")
                check("scrollPreviewToAnchor가 헤딩을 찾음", (result["anchorHit"] as? Bool) == true)

                print("\n── D. 링크 치환")
                check("상대 .md 링크가 note 호스트로",
                      links[0].hasPrefix("mermark-local://note/"), "\(links[0])")
                check("퍼센트 인코딩 중복 없음", !links[0].contains("%25"), "\(links[0])")
                // markdown-it은 프래그먼트도 퍼센트 인코딩한다. 디코딩하면 슬러그와 일치해야 한다.
                check("앵커가 링크에 보존됨",
                      links[1].removingPercentEncoding?.hasSuffix("#섹션-이름") == true, "\(links[1])")
                check("/로 시작하면 folder 호스트로",
                      links[2].hasPrefix("mermark-local://folder/"), "\(links[2])")
                check("외부 주소는 그대로", links[3] == "https://example.com", "\(links[3])")
                check("같은 문서 앵커는 스킴 치환 없이 유지",
                      links[4].hasPrefix("#") && links[4].removingPercentEncoding == "#두-번째-섹션",
                      "\(links[4])")

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
