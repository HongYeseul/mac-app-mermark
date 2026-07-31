import AppKit
import Foundation

var failures: [String] = []
var total = 0
func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
    total += 1
    print("\(condition ? "PASS" : "FAIL"): \(name)\(condition ? "" : "  → \(detail())")")
    if !condition { failures.append(name) }
}
func pump(_ seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

print("── A. LineMath 순수 함수")
let sample = "첫째 줄\n둘째 줄\n\n넷째 줄"
check("첫 문자는 0줄", LineMath.lineNumber(atCharacterIndex: 0, in: sample) == 0)
check("둘째 줄 시작 인덱스", LineMath.characterIndex(ofLine: 1, in: sample) == 5,
      "\(LineMath.characterIndex(ofLine: 1, in: sample))")
check("빈 줄(2줄)도 정확", LineMath.characterIndex(ofLine: 2, in: sample) == 10,
      "\(LineMath.characterIndex(ofLine: 2, in: sample))")
check("인덱스 → 줄 왕복", (0..<4).allSatisfy { line in
    LineMath.lineNumber(atCharacterIndex: LineMath.characterIndex(ofLine: line, in: sample), in: sample) == line
})
check("마지막 줄 초과 시 마지막 줄 시작", LineMath.characterIndex(ofLine: 99, in: sample) == 11,
      "\(LineMath.characterIndex(ofLine: 99, in: sample))")
check("한글/이모지 섞여도 정확", LineMath.lineNumber(atCharacterIndex: ("가나다🎉\n라마" as NSString).length, in: "가나다🎉\n라마") == 1)

print("\n── B. EditorController 스크롤 (실제 NSTextView)")
let controller = EditorController()
let frame = NSRect(x: 0, y: 0, width: 600, height: 400)
let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
window.contentView = controller.scrollView
controller.scrollView.frame = frame

let doc = (0..<300).map { "줄 \($0) — 내용 텍스트" }.joined(separator: "\n")
controller.setText(doc)
controller.scrollView.layoutSubtreeIfNeeded()
pump(0.3)

check("문서가 스크롤 가능한 높이",
      (controller.scrollView.documentView?.frame.height ?? 0) > frame.height,
      "\(controller.scrollView.documentView?.frame.height ?? 0)")

var reported: [Int] = []
controller.onScrollToLine = { reported.append($0) }

var roundTripErrors: [(Int, Int)] = []
for line in [0, 5, 20, 50, 120, 200] {
    controller.scroll(toLine: line)
    controller.scrollView.layoutSubtreeIfNeeded()
    let got = controller.topVisibleLine
    if got != line { roundTripErrors.append((line, got)) }
}
check("scroll(toLine:) → topVisibleLine 왕복 일치", roundTripErrors.isEmpty, "\(roundTripErrors)")

print("\n── C. 되돌림 루프 방지")
reported.removeAll()
controller.scroll(toLine: 100)
pump(0.1)
check("프로그램 스크롤 직후에는 보고 억제", reported.isEmpty, "\(reported)")

pump(0.3)  // 억제 구간(0.25초) 종료 대기
reported.removeAll()
controller.scrollView.contentView.scroll(to: NSPoint(x: 0, y: 1500))
controller.scrollView.reflectScrolledClipView(controller.scrollView.contentView)
pump(0.1)
check("억제 해제 후 사용자 스크롤은 보고됨", !reported.isEmpty, "\(reported)")
check("보고된 줄이 실제 최상단 줄과 일치", reported.last == controller.topVisibleLine,
      "보고 \(reported.last.map(String.init) ?? "nil") vs 실제 \(controller.topVisibleLine)")

print("\n── D. 텍스트 교체")
controller.setText("짧은 문서")
controller.scrollView.layoutSubtreeIfNeeded()
check("텍스트 교체 반영", controller.text == "짧은 문서")
check("짧은 문서에서 topVisibleLine은 0", controller.topVisibleLine == 0, "\(controller.topVisibleLine)")

print("\n" + (failures.isEmpty ? "ALL PASS (\(total) checks)" : "FAILURES(\(failures.count)/\(total)): \(failures.joined(separator: ", "))"))
exit(failures.isEmpty ? 0 : 1)
