import AppKit
import SwiftUI

// 상단 탭이 실제 파일 동작(열기·닫기·이름 변경·삭제·연결 해제)과 어긋나지 않는지 확인한다.

// 검증이 실제 ~/.config/mermark을 건드리지 않도록 전용 설정 폴더를 쓴다
WorkspaceConfig.directory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("mermark-config-tabs-\(ProcessInfo.processInfo.processIdentifier)")

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
    .appendingPathComponent("mermark-tabs-\(ProcessInfo.processInfo.processIdentifier)")
try? fm.removeItem(at: sandbox)
let 업무 = sandbox.appendingPathComponent("업무")
let 개인 = sandbox.appendingPathComponent("개인")
try! fm.createDirectory(at: 업무, withIntermediateDirectories: true)
try! fm.createDirectory(at: 개인, withIntermediateDirectories: true)

func write(_ text: String, to url: URL) {
    try! text.write(to: url, atomically: true, encoding: .utf8)
    usleep(20_000)
}

let 하나 = 업무.appendingPathComponent("하나.md")
let 둘 = 업무.appendingPathComponent("둘.md")
let 셋 = 업무.appendingPathComponent("셋.md")
let 개인노트 = 개인.appendingPathComponent("개인 노트.md")
write("# 하나\n첫째", to: 하나)
write("# 둘\n둘째", to: 둘)
write("# 셋\n셋째", to: 셋)
write("# 개인 노트\n", to: 개인노트)

WorkspaceConfig.save([업무, 개인])
let store = NoteStore()
pump(0.4)

print("── A. 여는 순서대로 탭이 쌓인다")
for tab in store.openTabs { store.closeTab(tab) }      // 시작할 때 자동으로 열린 탭을 비운다
check("비우면 탭이 없음", store.openTabs.isEmpty && store.selectedNoteURL == nil,
      "\(store.openTabs.map(\.lastPathComponent))")
store.select(하나)
check("연 노트가 탭이 됨", store.openTabs == [하나], "\(store.openTabs.map(\.lastPathComponent))")
store.select(둘)
store.select(셋)
check("연 순서를 지킴", store.openTabs == [하나, 둘, 셋], "\(store.openTabs.map(\.lastPathComponent))")
check("마지막에 연 것이 활성", store.selectedNoteURL == 셋, store.selectedNoteURL?.lastPathComponent ?? "nil")

store.select(하나)
check("이미 열린 탭은 늘어나지 않음", store.openTabs == [하나, 둘, 셋], "\(store.openTabs.map(\.lastPathComponent))")
check("그 탭으로 옮겨 감", store.selectedNoteURL == 하나)
check("본문도 그 노트 것", store.currentText.contains("첫째"), store.currentText)

print("\n── B. 닫기")
check("오른쪽 탭 계산", NoteStore.tabAfterClosing(둘, in: [하나, 둘, 셋]) == 셋)
check("마지막이면 왼쪽", NoteStore.tabAfterClosing(셋, in: [하나, 둘, 셋]) == 둘)
check("하나뿐이면 없음", NoteStore.tabAfterClosing(하나, in: [하나]) == nil)
check("없는 탭이면 없음", NoteStore.tabAfterClosing(개인노트, in: [하나, 둘]) == nil)

store.select(둘)
store.closeTab(둘)
check("닫으면 목록에서 빠짐", store.openTabs == [하나, 셋], "\(store.openTabs.map(\.lastPathComponent))")
check("보던 탭을 닫으면 오른쪽으로", store.selectedNoteURL == 셋, store.selectedNoteURL?.lastPathComponent ?? "nil")
check("파일은 그대로 있음", fm.fileExists(atPath: 둘.path))

store.select(하나)
store.closeTab(셋)
check("보지 않던 탭을 닫아도 선택은 그대로", store.selectedNoteURL == 하나)
check("목록에서만 빠짐", store.openTabs == [하나], "\(store.openTabs.map(\.lastPathComponent))")

store.closeTab(하나)
check("마지막 탭을 닫으면 빈 화면", store.openTabs.isEmpty && store.selectedNoteURL == nil,
      "\(store.openTabs.map(\.lastPathComponent)) / \(store.selectedNoteURL?.lastPathComponent ?? "nil")")
check("본문도 비움", store.currentText.isEmpty, store.currentText)

store.select(하나)
store.select(둘)
store.select(셋)
store.closeOtherTabs(둘)
check("이 탭만 남기기", store.openTabs == [둘], "\(store.openTabs.map(\.lastPathComponent))")
check("남긴 탭이 활성", store.selectedNoteURL == 둘)

print("\n── C. 새 노트")
store.createNote(in: 업무)
let 새노트 = store.selectedNoteURL
check("새 노트가 탭으로 열림", 새노트 != nil && store.openTabs.last == 새노트,
      "\(store.openTabs.map(\.lastPathComponent))")
check("바로 그 탭이 활성", store.openTabs.contains(where: { $0 == 새노트 }))

print("\n── D. 이름이 바뀌어도 자리를 지킨다")
store.select(하나)
store.select(둘)
store.closeOtherTabs(둘)
store.select(하나)      // [둘, 하나]
store.select(둘)
check("준비된 순서", store.openTabs == [둘, 하나], "\(store.openTabs.map(\.lastPathComponent))")

store.textChanged("# 이름 바꾼 둘\n둘째")
store.flushPendingSave()
let 바뀐 = 업무.appendingPathComponent("이름 바꾼 둘.md")
check("파일명이 첫 줄을 따라감", fm.fileExists(atPath: 바뀐.path), "\(store.selectedNoteURL?.lastPathComponent ?? "nil")")
check("탭 자리가 그대로", store.openTabs == [바뀐, 하나], "\(store.openTabs.map(\.lastPathComponent))")
check("탭이 중복되지 않음", store.openTabs.count == 2, "\(store.openTabs.map(\.lastPathComponent))")
check("선택도 새 주소를 가리킴", store.selectedNoteURL == 바뀐)

print("\n── E. 밖에서 지우면 탭도 닫힌다")
store.select(하나)
store.select(바뀐)      // [바뀐, 하나], 활성 = 바뀐
try! fm.removeItem(at: 바뀐)
pump(1.2)              // FSEvents
check("없어진 노트의 탭이 닫힘", !store.openTabs.contains(바뀐), "\(store.openTabs.map(\.lastPathComponent))")
check("남은 탭으로 옮겨 감", store.selectedNoteURL == 하나, store.selectedNoteURL?.lastPathComponent ?? "nil")
check("남은 탭은 그대로", store.openTabs == [하나], "\(store.openTabs.map(\.lastPathComponent))")

print("\n── F. 작업 공간을 끊으면 그 안의 탭이 닫힌다")
store.select(개인노트)
check("두 공간의 탭이 함께 열림", store.openTabs == [하나, 개인노트], "\(store.openTabs.map(\.lastPathComponent))")
if let 개인공간 = store.workspaces.first(where: { $0.url.path == 개인.path }) {
    store.disconnectWorkspace(개인공간)
}
check("끊긴 공간의 탭만 닫힘", store.openTabs == [하나], "\(store.openTabs.map(\.lastPathComponent))")
check("파일은 지우지 않음", fm.fileExists(atPath: 개인노트.path))

print("\n── G. 실제로 그려진다")
// SwiftUI의 Text는 NSTextField가 아니라 직접 그려지므로, 실제로 그린 픽셀로 확인한다
let hosting = NSHostingView(rootView: NoteTabBar(store: store))
hosting.frame = NSRect(x: 0, y: 0, width: 600, height: 30)
let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
window.contentView = hosting
window.orderFront(nil)
pump(0.4)

/// 그려진 내용을 픽셀로 요약한다. 탭이 늘면 칠해진 곳이 늘어난다.
func rendered(_ view: NSView) -> [UInt8] {
    view.layoutSubtreeIfNeeded()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return [] }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else { return [] }
    return [UInt8](data)
}

for tab in store.openTabs { store.closeTab(tab) }
pump(0.4)
let 빈바 = rendered(hosting)
check("빈 탭 바도 그려짐", !빈바.isEmpty)

store.select(하나)
pump(0.4)
let 한개 = rendered(hosting)
check("탭을 열면 그림이 달라짐", 한개 != 빈바 && !한개.isEmpty)

store.select(둘)
pump(0.4)
let 두개 = rendered(hosting)
check("탭이 늘면 또 달라짐", 두개 != 한개)

store.select(하나)
pump(0.4)
check("활성 탭이 바뀌면 표시도 바뀜", rendered(hosting) != 두개)

store.select(둘)
store.closeTab(하나)
pump(0.4)
check("닫으면 탭 하나짜리 폭으로 돌아옴", store.openTabs == [둘], "\(store.openTabs.map(\.lastPathComponent))")
check("빈 바와는 여전히 다름", rendered(hosting) != 빈바)

window.orderOut(nil)
try? fm.removeItem(at: sandbox)
try? fm.removeItem(at: WorkspaceConfig.directory)
print("\n" + (failures.isEmpty ? "ALL PASS (\(total) checks)" : "FAILURES(\(failures.count)/\(total)): \(failures.joined(separator: ", "))"))
exit(failures.isEmpty ? 0 : 1)
