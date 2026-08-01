import AppKit
import WebKit

// 할 일 목록: 체크박스로 렌더되는지, 누르면 원본 줄이 뒤집히는지 확인한다.

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

// MARK: - A. 원본 줄 뒤집기

print("── A. 원본 줄 뒤집기")
let doc = """
# 할 일

- [x] PNG 내보내기
- [ ] 다음 작업
* [X] 별표 목록
1. [ ] 번호 목록
- 일반 항목
본문에 [x] 가 있어도 항목이 아님
"""

func toggled(_ line: Int) -> String? { MarkdownTaskList.toggle(in: doc, line: line) }
func lineOf(_ text: String?, _ index: Int) -> String? {
    text?.components(separatedBy: "\n")[index]
}

check("체크된 항목을 풀기", lineOf(toggled(2), 2) == "- [ ] PNG 내보내기", "\(lineOf(toggled(2), 2) ?? "nil")")
check("빈 항목을 체크", lineOf(toggled(3), 3) == "- [x] 다음 작업", "\(lineOf(toggled(3), 3) ?? "nil")")
check("대문자 X도 인식", lineOf(toggled(4), 4) == "* [ ] 별표 목록", "\(lineOf(toggled(4), 4) ?? "nil")")
check("번호 목록도 인식", lineOf(toggled(5), 5) == "1. [x] 번호 목록", "\(lineOf(toggled(5), 5) ?? "nil")")
check("일반 목록 항목은 그대로", toggled(6) == nil, "\(lineOf(toggled(6), 6) ?? "nil")")
check("본문 중간의 [x]는 건드리지 않음", toggled(7) == nil, "\(lineOf(toggled(7), 7) ?? "nil")")
check("헤딩 줄은 그대로", toggled(0) == nil)
check("범위 밖 줄은 안전하게 무시", MarkdownTaskList.toggle(in: doc, line: 999) == nil)
check("다른 줄은 바뀌지 않음",
      toggled(3)?.components(separatedBy: "\n")[2] == "- [x] PNG 내보내기",
      "\(lineOf(toggled(3), 2) ?? "nil")")

// 들여쓴 하위 항목
let nested = "- [ ] 상위\n  - [x] 하위"
check("들여쓴 항목도 인식",
      MarkdownTaskList.toggle(in: nested, line: 1) == "- [ ] 상위\n  - [ ] 하위",
      "\(MarkdownTaskList.toggle(in: nested, line: 1) ?? "nil")")

// MARK: - B. 실제 렌더

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

nav.onReady = {
    let encoded = String(data: try! JSONEncoder().encode(doc), encoding: .utf8)!
    webView.evaluateJavaScript("window.renderMarkdown(\(encoded));") { _, _ in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let script = """
            const items = [...document.querySelectorAll("#content li")];
            return JSON.stringify(items.map(li => {
              const box = li.querySelector('input[type="checkbox"]');
              return {
                text: li.textContent.trim(),
                hasBox: !!box,
                checked: box ? box.checked : null,
                disabled: box ? box.disabled : null,
                taskLine: li.dataset.taskLine ?? null,
                isTaskItem: li.classList.contains("task-item")
              };
            }));
            """
            webView.callAsyncJavaScript(script, in: nil, in: .page) { result in
                guard case .success(let value) = result,
                      let json = value as? String,
                      let data = json.data(using: .utf8),
                      let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    check("렌더 결과 조회", false, "\(result)")
                    finish()
                    return
                }

                print("\n── B. 실제 렌더")
                let boxes = items.filter { ($0["hasBox"] as? Bool) == true }
                check("할 일 항목 4개에 체크박스 생성", boxes.count == 4, "\(items)")
                // 뒤 줄이 목록 항목에 이어 붙으므로 텍스트 전체 일치가 아니라 포함으로 본다
                check("일반 목록 항목에는 체크박스 없음",
                      items.contains {
                          (($0["text"] as? String) ?? "").contains("일반 항목") && ($0["hasBox"] as? Bool) == false
                      },
                      "\(items.map { $0["text"] ?? "" })")

                check("체크된 항목은 checked", (boxes.first?["checked"] as? Bool) == true,
                      "\(boxes.first ?? [:])")
                check("빈 항목은 unchecked",
                      (boxes.first { ($0["text"] as? String) == "다음 작업" }?["checked"] as? Bool) == false,
                      "\(boxes)")

                check("대괄호 글자가 사라짐",
                      boxes.allSatisfy { !(($0["text"] as? String) ?? "").hasPrefix("[") },
                      "\(boxes.map { $0["text"] ?? "" })")

                check("누를 수 있도록 활성화됨",
                      boxes.allSatisfy { ($0["disabled"] as? Bool) == false }, "\(boxes)")

                // 클릭 시 Swift로 넘길 줄 번호가 원본과 맞아야 한다
                let firstLine = boxes.first?["taskLine"] as? String
                check("첫 항목의 줄 번호가 원본과 일치", firstLine == "2", "\(firstLine ?? "nil")")
                check("줄 번호로 되짚으면 같은 항목",
                      lineOf(toggled(Int(firstLine ?? "-1") ?? -1), 2) == "- [ ] PNG 내보내기",
                      "\(firstLine ?? "nil")")

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
