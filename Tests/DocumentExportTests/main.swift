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

print("── 0. 쪽 나누는 지점 (이슈 #2)")
check("빈 문서는 한 쪽",
      PDFExporter.pageBreaks(blockTops: [], totalHeight: 0, pageHeight: 700).count == 2,
      "\(PDFExporter.pageBreaks(blockTops: [], totalHeight: 0, pageHeight: 700))")
check("한 쪽에 들어가면 나누지 않음",
      PDFExporter.pageBreaks(blockTops: [0, 100, 300], totalHeight: 400, pageHeight: 700) == [0, 400],
      "\(PDFExporter.pageBreaks(blockTops: [0, 100, 300], totalHeight: 400, pageHeight: 700))")
check("블록 경계에서 끊는다",
      PDFExporter.pageBreaks(blockTops: [0, 300, 650, 900], totalHeight: 1200, pageHeight: 700)
        == [0, 650, 1200],
      "\(PDFExporter.pageBreaks(blockTops: [0, 300, 650, 900], totalHeight: 1200, pageHeight: 700))")
check("한 쪽을 넘는 블록은 어쩔 수 없이 자름",
      PDFExporter.pageBreaks(blockTops: [0], totalHeight: 1600, pageHeight: 700) == [0, 700, 1400, 1600],
      "\(PDFExporter.pageBreaks(blockTops: [0], totalHeight: 1600, pageHeight: 700))")
let manyBreaks = PDFExporter.pageBreaks(blockTops: (0..<40).map { Double($0) * 120 },
                                        totalHeight: 4800, pageHeight: 700)
check("나눈 지점은 오름차순", zip(manyBreaks, manyBreaks.dropFirst()).allSatisfy { $0 < $1 },
      "\(manyBreaks)")
check("마지막은 문서 끝", manyBreaks.last == 4800, "\(manyBreaks.last ?? -1)")

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

\(  (1...40).map { "## 섹션 \($0)\n\n" + String(repeating: "본문 내용입니다. ", count: 10) }
        .joined(separator: "\n\n") )
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
                let h2Texts = r["h2Texts"] as? [String] ?? []
                check("setext 제목으로 잘못 해석되지 않음",
                      h2Texts.first == "두 번째 섹션"
                      && !h2Texts.contains { $0.contains("title") || $0.contains("author") },
                      "\(h2Texts.prefix(3))")

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
                    check("긴 문서는 여러 쪽으로 나뉨", pdf.pageCount > 1, "\(pdf.pageCount)쪽")

                    let text = pdf.string ?? ""
                    check("본문 제목 포함", text.contains("분기 보고서"), "앞부분: \(text.prefix(80))")
                    check("두 번째 섹션도 포함", text.contains("두 번째 섹션"), "앞부분: \(text.prefix(80))")
                    check("프론트매터 값도 포함", text.contains("홍예슬"), "앞부분: \(text.prefix(80))")
                    check("마지막 섹션까지 빠짐없이 들어감", text.contains("섹션 40"),
                          "끝부분: \(text.suffix(80))")

                    // 쪽 크기가 제각각이면 인쇄·공유할 때 어색하다
                    let sizes = Set((0..<pdf.pageCount).compactMap { index -> String? in
                        guard let bounds = pdf.page(at: index)?.bounds(for: .mediaBox) else { return nil }
                        return "\(Int(bounds.width))x\(Int(bounds.height))"
                    })
                    check("모든 쪽이 같은 크기", sizes.count == 1, "\(sizes)")
                    check("A4 크기(595x842)", sizes.first == "595x842", "\(sizes)")
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
