import AppKit
import WebKit
import PDFKit

// 프론트매터 표시와 문서 전체 PDF 내보내기를 실제 렌더로 확인한다.

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
let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("mermark-pdf-\(ProcessInfo.processInfo.processIdentifier).pdf")

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
    try? fm.removeItem(at: outputURL)
    print("\n" + (failures.isEmpty ? "ALL PASS (\(total) checks)" : "FAILURES(\(failures.count)/\(total)): \(failures.joined(separator: ", "))"))
    exit(failures.isEmpty ? 0 : 1)
}

let markdown = """
---
title: 분기 보고서
author: 홍예슬
tags:
  - 정산
  - 검토
---

# 분기 보고서

첫 문단입니다.

## 두 번째 섹션

내용이 이어집니다.

수식도 포함: $E = mc^2$
"""

nav.onReady = {
    let encoded = String(data: try! JSONEncoder().encode(markdown), encoding: .utf8)!
    webView.evaluateJavaScript("window.renderMarkdown(\(encoded));") { _, _ in
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            let script = """
            const box = document.querySelector("#content .frontmatter");
            const keys = [...document.querySelectorAll("#content .fm-key")].map(e => e.textContent);
            const values = [...document.querySelectorAll("#content .fm-value")].map(e => e.textContent);
            const firstHeading = document.querySelector("#content h1");
            return JSON.stringify({
              hasBox: !!box,
              boxLine: box ? box.dataset.line : null,
              keys, values,
              headingLine: firstHeading ? firstHeading.dataset.line : null,
              headingText: firstHeading ? firstHeading.textContent : null,
              // 프론트매터가 수평선이나 제목으로 잘못 해석되지 않았는지
              hrCount: document.querySelectorAll("#content hr").length,
              h2Texts: [...document.querySelectorAll("#content h2")].map(e => e.textContent)
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

                print("── A. 프론트매터 표시")
                check("프론트매터 블록이 렌더됨", (r["hasBox"] as? Bool) == true)
                let keys = r["keys"] as? [String] ?? []
                let values = r["values"] as? [String] ?? []
                check("키를 모두 뽑음", keys == ["title", "author", "tags"], "\(keys)")
                check("값을 모두 뽑음", values.first == "분기 보고서" && values.count == 3, "\(values)")
                check("목록 값은 한 줄로 합침", values.last == "정산, 검토", "\(values)")

                check("수평선으로 잘못 해석되지 않음", (r["hrCount"] as? Int) == 0, "\(r["hrCount"] ?? "nil")")
                check("setext 제목으로 잘못 해석되지 않음",
                      (r["h2Texts"] as? [String]) == ["두 번째 섹션"], "\(r["h2Texts"] ?? "nil")")

                // 프론트매터가 줄 번호를 밀어내면 스크롤 동기화가 어긋난다
                check("프론트매터 앵커는 0번 줄", (r["boxLine"] as? String) == "0", "\(r["boxLine"] ?? "nil")")
                // 프론트매터 6줄(0~6) + 빈 줄 1개 뒤이므로 8번 줄. 프론트매터가 줄을 밀지 않았다는 뜻.
                check("본문 제목의 줄 번호가 원본과 일치",
                      (r["headingLine"] as? String) == "8", "\(r["headingLine"] ?? "nil")")

                print("\n── B. PDF 내보내기")
                PDFExporter.export(webView, to: outputURL) { error in
                    if let error {
                        check("PDF 내보내기 성공", false, "\(error)")
                        finish()
                        return
                    }
                    check("PDF 파일 생성", fm.fileExists(atPath: outputURL.path))

                    guard let pdf = PDFDocument(url: outputURL) else {
                        check("유효한 PDF", false, "PDFDocument 생성 실패")
                        finish()
                        return
                    }
                    check("유효한 PDF", true)
                    check("쪽이 하나 이상", pdf.pageCount >= 1, "\(pdf.pageCount)")

                    let text = pdf.string ?? ""
                    check("본문 제목 포함", text.contains("분기 보고서"), "앞부분: \(text.prefix(80))")
                    check("두 번째 섹션도 포함", text.contains("두 번째 섹션"), "앞부분: \(text.prefix(80))")
                    check("프론트매터 값도 포함", text.contains("홍예슬"), "앞부분: \(text.prefix(80))")
                    check("문서 길이만큼 페이지가 길어짐",
                          (pdf.page(at: 0)?.bounds(for: .mediaBox).height ?? 0) > 200,
                          "\(pdf.page(at: 0)?.bounds(for: .mediaBox).height ?? -1)")
                    let size = (try? fm.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
                    check("빈 파일이 아님", size > 2000, "\(size) bytes")

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
