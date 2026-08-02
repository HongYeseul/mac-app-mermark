import AppKit

// 노트를 휴지통으로 옮기는 동작을 실제 파일로 확인한다.
// 검증이 남긴 파일은 끝에서 휴지통에서도 지운다.

// 검증이 실제 ~/.config/mermark을 건드리지 않도록 전용 설정 폴더를 쓴다
WorkspaceConfig.directory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("mermark-config-trash-\(ProcessInfo.processInfo.processIdentifier)")

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
    .appendingPathComponent("mermark-trash-\(ProcessInfo.processInfo.processIdentifier)")
try? fm.removeItem(at: sandbox)
try! fm.createDirectory(at: sandbox, withIntermediateDirectories: true)

/// 검증이 휴지통에 남긴 것들. 끝에서 치운다.
var leftInTrash: [URL] = []

func write(_ text: String, to url: URL) {
    try! text.write(to: url, atomically: true, encoding: .utf8)
    usleep(20_000)
}

let 하나 = sandbox.appendingPathComponent("하나.md")
let 둘 = sandbox.appendingPathComponent("둘.md")
let 셋 = sandbox.appendingPathComponent("셋.md")
write("# 하나\n첫째", to: 하나)
write("# 둘\n둘째", to: 둘)
write("# 셋\n셋째", to: 셋)

WorkspaceConfig.save([sandbox])
let store = NoteStore()
pump(0.4)
for tab in store.openTabs { store.closeTab(tab) }

print("── A. 지우지 않고 휴지통으로 옮긴다")
store.select(하나)
store.select(둘)
store.select(셋)
let trashed = store.moveToTrash(둘)
if let trashed { leftInTrash.append(trashed) }

check("원래 자리에서 사라짐", !fm.fileExists(atPath: 둘.path))
check("휴지통에 들어감", trashed != nil && fm.fileExists(atPath: trashed!.path),
      trashed?.path ?? "nil")
check("내용도 그대로 남아 있음",
      trashed.flatMap { try? String(contentsOf: $0, encoding: .utf8) } == "# 둘\n둘째",
      trashed.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "nil")
check("목록에서 빠짐", !store.notes.contains { $0.url == 둘 }, "\(store.notes.map(\.title))")
check("탭도 닫힘", !store.openTabs.contains(둘), "\(store.openTabs.map(\.lastPathComponent))")
check("보지 않던 노트라 선택은 그대로", store.selectedNoteURL == 셋,
      store.selectedNoteURL?.lastPathComponent ?? "nil")

print("\n── B. 보고 있던 노트를 지우면 옆으로 옮겨 간다")
store.select(하나)
store.select(셋)     // 탭: [하나, 셋], 활성 = 셋
let trashedSet = store.moveToTrash(셋)
if let trashedSet { leftInTrash.append(trashedSet) }
check("탭이 닫힘", store.openTabs == [하나], "\(store.openTabs.map(\.lastPathComponent))")
check("옆 탭으로 옮겨 감", store.selectedNoteURL == 하나, store.selectedNoteURL?.lastPathComponent ?? "nil")
check("본문도 옆 노트 것", store.currentText.contains("첫째"), store.currentText)

print("\n── C. 대기 중인 저장이 되살리지 않는다")
// 타이핑 직후 지우면, 예약된 자동 저장이 방금 지운 파일을 다시 만들 수 있다
let 임시 = sandbox.appendingPathComponent("임시.md")
write("# 임시\n", to: 임시)
pump(0.8)
store.select(임시)
store.textChanged("# 임시\n타이핑 중")      // 0.5초 뒤 저장 예약
let trashedTemp = store.moveToTrash(임시)
if let trashedTemp { leftInTrash.append(trashedTemp) }
pump(1.5)                                   // 예약된 저장 시각을 지나 보낸다
check("지운 파일이 되살아나지 않음", !fm.fileExists(atPath: 임시.path))
check("목록에도 없음", !store.notes.contains { $0.url == 임시 }, "\(store.notes.map(\.title))")

print("\n── D. 마지막 노트를 지우면 빈 화면")
let trashedOne = store.moveToTrash(하나)
if let trashedOne { leftInTrash.append(trashedOne) }
check("탭이 모두 닫힘", store.openTabs.isEmpty, "\(store.openTabs.map(\.lastPathComponent))")
check("선택이 비워짐", store.selectedNoteURL == nil, store.selectedNoteURL?.lastPathComponent ?? "nil")
check("본문도 비워짐", store.currentText.isEmpty, store.currentText)

print("\n── E. 없는 파일")
check("이미 없는 노트는 조용히 실패", store.moveToTrash(하나) == nil)

// 검증이 휴지통에 남긴 것들을 치운다
for url in leftInTrash { try? fm.removeItem(at: url) }
check("검증이 휴지통에 남긴 것 정리", leftInTrash.allSatisfy { !fm.fileExists(atPath: $0.path) },
      "\(leftInTrash.map(\.lastPathComponent))")

try? fm.removeItem(at: sandbox)
try? fm.removeItem(at: WorkspaceConfig.directory)
print("\n" + (failures.isEmpty ? "ALL PASS (\(total) checks)" : "FAILURES(\(failures.count)/\(total)): \(failures.joined(separator: ", "))"))
exit(failures.isEmpty ? 0 : 1)
