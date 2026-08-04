import AppKit
import SwiftUI
import WebKit

// 상단 탭 줄이 본문을 가리지 않는지 실제 창에서 좌표로 잰다.

// 검증이 실제 ~/.config/mermark을 건드리지 않도록 전용 설정 폴더를 쓴다
WorkspaceConfig.directory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("mermark-config-layout-\(ProcessInfo.processInfo.processIdentifier)")

var failures: [String] = []
var total = 0
func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
    total += 1
    print("\(condition ? "PASS" : "FAIL"): \(name)\(condition ? "" : "  → \(detail())")")
    if !condition { failures.append(name) }
}
func pump(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let fm = FileManager.default
let sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("mermark-layout-\(ProcessInfo.processInfo.processIdentifier)")
try? fm.removeItem(at: sandbox)
try! fm.createDirectory(at: sandbox, withIntermediateDirectories: true)

let 노트 = sandbox.appendingPathComponent("긴 노트.md")
try! (["# 맨 위 제목"] + (1...80).map { "본문 \($0)줄" }).joined(separator: "\n")
    .write(to: 노트, atomically: true, encoding: .utf8)

WorkspaceConfig.save([sandbox])
let store = NoteStore()
pump(0.4)
store.select(노트)

let content = ContentView(store: store)
let hosting = NSHostingView(rootView: content)
hosting.frame = NSRect(x: 0, y: 0, width: 1200, height: 700)
let window = NSWindow(
    contentRect: hosting.frame,
    styleMask: [.titled, .resizable, .fullSizeContentView],
    backing: .buffered, defer: false
)
// 실제 앱 창에는 툴바가 있고, 그 안전 영역 때문에 본문이 위로 붙는다.
// 툴바가 없으면 겹침이 재현되지 않는다.
let toolbar = NSToolbar(identifier: "layout-test")
window.toolbar = toolbar
window.toolbarStyle = .unified
window.titlebarAppearsTransparent = true
window.contentView = hosting
window.makeKeyAndOrderFront(nil)
pump(1.5)

/// 뷰 트리에서 조건에 맞는 뷰를 찾는다
func find<T: NSView>(_ type: T.Type, in view: NSView, where matches: (T) -> Bool = { _ in true }) -> T? {
    if let match = view as? T, matches(match) { return match }
    for child in view.subviews {
        if let found = find(type, in: child, where: matches) { return found }
    }
    return nil
}

print("── A. 화면에 붙었는지")
let scrollView = find(NSScrollView.self, in: hosting) { $0.documentView is NSTextView }
let webView = find(WKWebView.self, in: hosting)
check("에디터 스크롤 뷰를 찾음", scrollView != nil, "NSTextView를 품은 스크롤 뷰가 없음")
check("프리뷰 웹뷰를 찾음", webView != nil)

print("\n── B. 탭 줄이 본문을 가리지 않는다")
// safeAreaInset은 자식의 프레임을 줄이지 않고 안전 영역만 알려준다.
// NSViewRepresentable로 감싼 NSScrollView와 WKWebView는 그걸 무시하고 프레임 전체를 쓰므로
// 본문이 탭 줄 밑으로 들어간다. 그래서 "본문 높이가 탭 줄만큼 줄었는지"로 확인한다.
let tabBarHeight: CGFloat = 30
// 창 위쪽 툴바가 차지하는 만큼. 본문은 이 아래에서 시작한다.
let toolbarInset = hosting.bounds.height - window.contentLayoutRect.height
// 본문이 쓸 수 있는 높이 = 툴바 아래 영역에서 탭 줄을 뺀 것
let expectedContentHeight = window.contentLayoutRect.height - tabBarHeight

if let scrollView {
    check("에디터가 탭 줄 자리를 비워 둠",
          scrollView.frame.height <= expectedContentHeight + 1,
          "에디터 \(Int(scrollView.frame.height))pt인데 \(Int(expectedContentHeight))pt여야 함 — 탭 줄 밑으로 들어감")
    let box = hosting.convert(scrollView.bounds, from: scrollView)
    let gapAbove = hosting.isFlipped ? box.minY : hosting.bounds.height - box.maxY
    check("에디터 위쪽이 툴바 + 탭 줄만큼 내려와 있음",
          gapAbove >= toolbarInset + tabBarHeight - 1,
          "위쪽 여백 \(Int(gapAbove))pt인데 툴바 \(Int(toolbarInset)) + 탭 줄 \(Int(tabBarHeight))만큼이어야 함")
}

if let webView {
    check("프리뷰가 탭 줄 자리를 비워 둠",
          webView.frame.height <= expectedContentHeight + 1,
          "프리뷰 \(Int(webView.frame.height))pt인데 \(Int(expectedContentHeight))pt여야 함 — 탭 줄 밑으로 들어감")
}

print("\n── C. 탭이 늘어도 본문 자리가 그대로")
let 둘째 = sandbox.appendingPathComponent("둘째.md")
try! "# 둘째\n".write(to: 둘째, atomically: true, encoding: .utf8)
pump(1.0)
let beforeHeight = scrollView?.frame.height ?? -1
store.select(둘째)
pump(0.8)
check("탭이 늘어도 본문 높이가 그대로", abs(beforeHeight - (scrollView?.frame.height ?? -2)) < 1,
      "\(Int(beforeHeight))pt → \(Int(scrollView?.frame.height ?? -2))pt")

print("\n── D. 사라진 작업 공간이 화면을 가로막지 않는다")
// 멀쩡한 공간이 있는데도 오류 화면이 뜨면 에디터가 화면에서 사라진다
let 사라진공간 = sandbox.appendingPathComponent("사라진-공간")
WorkspaceConfig.save([sandbox, 사라진공간])
let mixed = NoteStore()
pump(0.4)
mixed.select(노트)
let mixedHosting = NSHostingView(rootView: ContentView(store: mixed))
mixedHosting.frame = NSRect(x: 0, y: 0, width: 1200, height: 700)
let mixedWindow = NSWindow(contentRect: mixedHosting.frame,
                           styleMask: [.titled, .resizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
mixedWindow.toolbar = NSToolbar(identifier: "layout-test-2")
mixedWindow.contentView = mixedHosting
mixedWindow.makeKeyAndOrderFront(nil)
pump(1.5)

check("사라진 공간을 알아챘음", mixed.missingWorkspacePaths == [사라진공간.path],
      "\(mixed.missingWorkspacePaths)")
check("멀쩡한 공간은 연결돼 있음", mixed.workspaces.count == 1, "\(mixed.workspaces.map(\.name))")
check("에디터가 그대로 보임",
      find(NSScrollView.self, in: mixedHosting, where: { $0.documentView is NSTextView }) != nil,
      "오류 화면이 본문을 덮음")
check("프리뷰도 그대로 보임", find(WKWebView.self, in: mixedHosting) != nil, "오류 화면이 본문을 덮음")

mixedWindow.orderOut(nil)

window.orderOut(nil)
try? fm.removeItem(at: sandbox)
try? fm.removeItem(at: WorkspaceConfig.directory)
print("\n" + (failures.isEmpty ? "ALL PASS (\(total) checks)" : "FAILURES(\(failures.count)/\(total)): \(failures.joined(separator: ", "))"))
exit(failures.isEmpty ? 0 : 1)
