import SwiftUI
import AppKit

// 컨트롤러가 소유한 NSView가 SwiftUI 조건부 분기에서 제거 → 재삽입되어도
// 재생성 없이 살아남고 정상 부착되는지 확인 (모드 전환의 핵심 가정)

var failures: [String] = []
var total = 0
func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
    total += 1
    print("\(condition ? "PASS" : "FAIL"): \(name)\(condition ? "" : "  → \(detail())")")
    if !condition { failures.append(name) }
}
func pump(_ s: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

final class Mode: ObservableObject {
    @Published var showEditor = true
    @Published var showPreview = true
}

final class FakeController: ObservableObject {
    let view: NSScrollView
    var makeCount = 0
    init() {
        view = NSTextView.scrollableTextView()
        (view.documentView as! NSTextView).string = "본문 내용"
    }
}

struct Rep: NSViewRepresentable {
    let controller: FakeController
    func makeNSView(context: Context) -> NSScrollView {
        controller.makeCount += 1
        return controller.view
    }
    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

struct Root: View {
    @ObservedObject var mode: Mode
    let editor: FakeController
    let preview: FakeController
    var body: some View {
        HSplitView {
            if mode.showEditor { Rep(controller: editor).frame(minWidth: 100) }
            if mode.showPreview { Rep(controller: preview).frame(minWidth: 100) }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let mode = Mode()
let editor = FakeController()
let preview = FakeController()

let hosting = NSHostingView(rootView: Root(mode: mode, editor: editor, preview: preview))
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
                      styleMask: [.titled], backing: .buffered, defer: false)
window.contentView = hosting
window.orderFront(nil)
pump(0.4)

// 화면에 살아 있는지의 기준은 superview가 아니라 window — SwiftUI가 자체 컨테이너로 감싸기 때문
check("분할 모드: 에디터가 창에 표시됨", editor.view.window != nil)
check("분할 모드: 프리뷰가 창에 표시됨", preview.view.window != nil)

// 스크롤 위치 보존 확인용 (PLAN.md: 전환 시 스크롤 위치 보존이 관건)
let editorText = (editor.view.documentView as! NSTextView)
editorText.string = (0..<200).map { "줄 \($0)" }.joined(separator: "\n")
editor.view.layoutSubtreeIfNeeded()
editor.view.contentView.scroll(to: NSPoint(x: 0, y: 700))
editor.view.reflectScrolledClipView(editor.view.contentView)
let savedScrollY = editor.view.contentView.bounds.origin.y

// 뷰어 전용 모드로 전환 (에디터 제거)
mode.showEditor = false
pump(0.4)
check("뷰어 모드: 에디터가 창에서 빠짐", editor.view.window == nil)
check("뷰어 모드: 프리뷰는 유지", preview.view.window != nil)

// 다시 분할 모드로
mode.showEditor = true
pump(0.4)
check("분할 복귀: 에디터 재표시", editor.view.window != nil)
check("에디터가 동일 인스턴스로 유지(재생성 아님)",
      (editor.view.documentView as! NSTextView) === editorText)
check("전환 후에도 스크롤 위치 보존", editor.view.contentView.bounds.origin.y == savedScrollY,
      "저장 \(savedScrollY) vs 현재 \(editor.view.contentView.bounds.origin.y)")

// 에디터 전용 모드
mode.showPreview = false
pump(0.4)
check("에디터 모드: 프리뷰가 창에서 빠짐", preview.view.window == nil)
check("에디터는 유지", editor.view.window != nil)

// 왕복 반복 — 재부착이 반복돼도 안정적인지
for _ in 0..<5 {
    mode.showPreview = true; pump(0.15)
    mode.showPreview = false; pump(0.15)
}
mode.showPreview = true
pump(0.4)
check("반복 전환 후에도 프리뷰 표시", preview.view.window != nil)
check("반복 전환 후에도 내용 보존", (preview.view.documentView as! NSTextView).string == "본문 내용")
check("반복 전환 후에도 에디터 스크롤 위치 유지",
      editor.view.contentView.bounds.origin.y == savedScrollY,
      "저장 \(savedScrollY) vs 현재 \(editor.view.contentView.bounds.origin.y)")

print("\n" + (failures.isEmpty ? "ALL PASS (\(total) checks)" : "FAILURES(\(failures.count)/\(total)): \(failures.joined(separator: ", "))"))
exit(failures.isEmpty ? 0 : 1)
