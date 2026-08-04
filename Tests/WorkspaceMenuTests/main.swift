import AppKit
import SwiftUI

// 사이드바 작업 공간 줄에서 우클릭이 실제로 먹는지 진짜 마우스 이벤트로 확인한다.
// 이름 글자 위에서만 되고 옆 빈 곳에서는 안 되던 적이 있다.

// 검증이 실제 ~/.config/mermark을 건드리지 않도록 전용 설정 폴더를 쓴다
WorkspaceConfig.directory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("mermark-config-wsmenu-\(ProcessInfo.processInfo.processIdentifier)")

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
    .appendingPathComponent("mermark-wsmenu-\(ProcessInfo.processInfo.processIdentifier)")
try? fm.removeItem(at: sandbox)
let 업무 = sandbox.appendingPathComponent("업무")
let 개인 = sandbox.appendingPathComponent("개인")
try! fm.createDirectory(at: 업무, withIntermediateDirectories: true)
try! fm.createDirectory(at: 개인, withIntermediateDirectories: true)
try! "# 보고서\n".write(to: 업무.appendingPathComponent("보고서.md"), atomically: true, encoding: .utf8)
try! "# 장보기\n".write(to: 개인.appendingPathComponent("장보기.md"), atomically: true, encoding: .utf8)

WorkspaceConfig.save([업무, 개인])
let store = NoteStore()
pump(0.4)
let workspace = store.workspaces[0]

print("── A. 이름 줄 어디를 눌러도 메뉴가 뜬다")
let header = NSHostingView(rootView: WorkspaceHeader(store: store, workspace: workspace))
header.frame = NSRect(x: 0, y: 0, width: 220, height: 22)
let window = NSWindow(contentRect: header.frame, styleMask: [.titled], backing: .buffered, defer: false)
window.contentView = header
window.makeKeyAndOrderFront(nil)
pump(0.6)
header.layoutSubtreeIfNeeded()

/// 그 지점에서 우클릭했을 때 뜨는 메뉴
func contextMenu(at point: CGPoint) -> NSMenu? {
    guard let event = NSEvent.mouseEvent(
        with: .rightMouseDown,
        location: point,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 1
    ) else { return nil }
    var view = header.hitTest(point)
    while let candidate = view {
        if let menu = candidate.menu(for: event) { return menu }
        view = candidate.superview
    }
    return nil
}

func titles(_ menu: NSMenu?) -> [String] {
    (menu?.items ?? []).map(\.title).filter { !$0.isEmpty }
}

// 이름 글자 위 (예전에도 되던 자리)
let onName = contextMenu(at: CGPoint(x: 20, y: 11))
check("이름 글자 위에서 메뉴가 뜸", onName != nil, "메뉴 없음")
check("연결 해제 항목이 있음", titles(onName).contains { $0.contains("연결 해제") }, "\(titles(onName))")
check("Finder에서 보기도 있음", titles(onName).contains { $0.contains("Finder") }, "\(titles(onName))")

// 이름 옆 빈 곳 — contentShape이 없으면 여기서 nil이 나온다
let onGap = contextMenu(at: CGPoint(x: 140, y: 11))
check("이름 옆 빈 곳에서도 메뉴가 뜸", onGap != nil, "빈 곳은 히트 테스트에서 빠짐")
check("빈 곳 메뉴도 같은 항목", titles(onGap) == titles(onName), "\(titles(onGap))")

print("\n── B. 확인 창을 거쳐 연결이 끊긴다")
check("처음에는 창이 없음", store.workspaceAwaitingDisconnect == nil)
store.requestDisconnect(workspace)
check("우클릭하면 창을 띄울 준비만 함", store.workspaceAwaitingDisconnect == workspace,
      store.workspaceAwaitingDisconnect?.name ?? "nil")
check("아직 연결돼 있음", store.workspaces.contains(workspace), "\(store.workspaces.map(\.name))")

store.cancelDisconnect()
check("취소하면 창이 닫힘", store.workspaceAwaitingDisconnect == nil)
check("취소하면 연결도 그대로", store.workspaces.contains(workspace), "\(store.workspaces.map(\.name))")

store.requestDisconnect(workspace)
store.confirmDisconnect()
check("확인하면 목록에서 빠짐", !store.workspaces.contains(workspace), "\(store.workspaces.map(\.name))")
check("확인 뒤 창이 닫힘", store.workspaceAwaitingDisconnect == nil)
check("다른 공간은 그대로", store.workspaces.map(\.name) == ["개인"], "\(store.workspaces.map(\.name))")
check("설정 파일에서도 빠짐", !WorkspaceConfig.load().map(\.path).contains(업무.path),
      "\(WorkspaceConfig.load().map(\.path))")

print("\n── C. 폴더와 파일은 그대로 남는다")
check("폴더가 남아 있음", fm.fileExists(atPath: 업무.path))
check("노트도 남아 있음", fm.fileExists(atPath: 업무.appendingPathComponent("보고서.md").path))
check("그 공간의 노트만 목록에서 빠짐", !store.notes.contains { $0.title == "보고서" },
      "\(store.notes.map(\.title))")
check("다른 공간 노트는 남음", store.notes.contains { $0.title == "장보기" }, "\(store.notes.map(\.title))")

check("잡아 둔 공간이 없으면 아무 일도 없음",
      { store.confirmDisconnect(); return store.workspaces.count == 1 }())

print("\n── D. 다시 연결하면 돌아온다")
check("다시 연결됨", store.addWorkspace(업무))
check("노트도 돌아옴", store.notes.contains { $0.title == "보고서" }, "\(store.notes.map(\.title))")

window.orderOut(nil)
try? fm.removeItem(at: sandbox)
try? fm.removeItem(at: WorkspaceConfig.directory)
print("\n" + (failures.isEmpty ? "ALL PASS (\(total) checks)" : "FAILURES(\(failures.count)/\(total)): \(failures.joined(separator: ", "))"))
exit(failures.isEmpty ? 0 : 1)
