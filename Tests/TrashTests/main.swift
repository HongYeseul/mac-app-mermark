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

print("\n── E. 확인 창")
let 확인용 = sandbox.appendingPathComponent("확인용.md")
write("# 확인용\n", to: 확인용)
pump(0.8)

check("처음에는 창이 없음", store.noteAwaitingTrash == nil)
store.requestTrash(확인용)
check("우클릭하면 창을 띄울 준비만 함", store.noteAwaitingTrash == 확인용,
      store.noteAwaitingTrash?.lastPathComponent ?? "nil")
check("아직 파일은 그대로", fm.fileExists(atPath: 확인용.path))

store.cancelTrash()
check("취소하면 창이 닫힘", store.noteAwaitingTrash == nil)
check("취소하면 파일도 그대로", fm.fileExists(atPath: 확인용.path))
check("목록에도 남아 있음", store.notes.contains { $0.url == 확인용 }, "\(store.notes.map(\.title))")

store.requestTrash(확인용)
let confirmed = store.confirmTrash()
if let confirmed { leftInTrash.append(confirmed) }
check("확인하면 옮겨짐", !fm.fileExists(atPath: 확인용.path))
check("확인하면 휴지통에 있음", confirmed != nil && fm.fileExists(atPath: confirmed!.path),
      confirmed?.path ?? "nil")
check("확인 뒤 창이 닫힘", store.noteAwaitingTrash == nil)
check("잡아 둔 노트가 없으면 아무 일도 없음", store.confirmTrash() == nil)

print("\n── F. 없는 파일")
check("이미 없는 노트는 조용히 실패", store.moveToTrash(하나) == nil)

print("\n── G. 작업 공간을 폴더째 휴지통으로")
let 지울공간 = sandbox.appendingPathComponent("지울-공간")
let 남길공간 = sandbox.appendingPathComponent("남길-공간")
let 지울하위 = 지울공간.appendingPathComponent("하위")
try! fm.createDirectory(at: 지울하위, withIntermediateDirectories: true)
try! fm.createDirectory(at: 남길공간, withIntermediateDirectories: true)
write("# 첫 노트\n", to: 지울공간.appendingPathComponent("첫 노트.md"))
write("# 둘째 노트\n", to: 지울공간.appendingPathComponent("둘째 노트.md"))
write("# 하위 노트\n", to: 지울하위.appendingPathComponent("하위 노트.md"))
// .md가 아닌 파일도 함께 가야 한다
try! Data([0x89, 0x50, 0x4E, 0x47]).write(to: 지울공간.appendingPathComponent("그림.png"))
write("# 남는 노트\n", to: 남길공간.appendingPathComponent("남는 노트.md"))

WorkspaceConfig.save([지울공간, 남길공간])
let wsStore = NoteStore()
pump(0.5)
for tab in wsStore.openTabs { wsStore.closeTab(tab) }

guard let 지울 = wsStore.workspaces.first(where: { $0.url.path == 지울공간.path }),
      let 남길 = wsStore.workspaces.first(where: { $0.url.path == 남길공간.path }) else {
    fatalError("작업 공간 준비 실패")
}
wsStore.select(남길공간.appendingPathComponent("남는 노트.md"))
wsStore.select(지울공간.appendingPathComponent("첫 노트.md"))
wsStore.select(지울하위.appendingPathComponent("하위 노트.md"))

check("하위 폴더까지 세어 알려줌", wsStore.noteCount(in: 지울) == 3, "\(wsStore.noteCount(in: 지울))개")
check("다른 공간은 따로 셈", wsStore.noteCount(in: 남길) == 1, "\(wsStore.noteCount(in: 남길))개")

check("처음에는 창이 없음", wsStore.workspaceAwaitingTrash == nil)
wsStore.requestWorkspaceTrash(지울)
check("우클릭하면 창을 띄울 준비만 함", wsStore.workspaceAwaitingTrash == 지울,
      wsStore.workspaceAwaitingTrash?.name ?? "nil")
check("아직 폴더는 그대로", fm.fileExists(atPath: 지울공간.path))

wsStore.cancelWorkspaceTrash()
check("취소하면 창이 닫힘", wsStore.workspaceAwaitingTrash == nil)
check("취소하면 폴더도 그대로", fm.fileExists(atPath: 지울공간.path))
check("취소하면 연결도 그대로", wsStore.workspaces.contains(지울), "\(wsStore.workspaces.map(\.name))")

wsStore.requestWorkspaceTrash(지울)
let 지운공간 = wsStore.confirmWorkspaceTrash()
if let 지운공간 { leftInTrash.append(지운공간) }
pump(0.5)

check("폴더가 원래 자리에서 사라짐", !fm.fileExists(atPath: 지울공간.path))
check("휴지통에 폴더가 들어감", 지운공간 != nil && fm.fileExists(atPath: 지운공간!.path),
      지운공간?.path ?? "nil")
check("안의 노트도 함께 감",
      지운공간.map { fm.fileExists(atPath: $0.appendingPathComponent("첫 노트.md").path) } == true)
check("하위 폴더도 함께 감",
      지운공간.map { fm.fileExists(atPath: $0.appendingPathComponent("하위/하위 노트.md").path) } == true)
check(".md가 아닌 파일도 함께 감",
      지운공간.map { fm.fileExists(atPath: $0.appendingPathComponent("그림.png").path) } == true)

check("목록에서 빠짐", !wsStore.workspaces.contains(지울), "\(wsStore.workspaces.map(\.name))")
check("설정 파일에서도 빠짐", !WorkspaceConfig.load().map(\.path).contains(지울공간.path),
      "\(WorkspaceConfig.load().map(\.path))")
check("그 공간의 탭이 모두 닫힘",
      !wsStore.openTabs.contains { $0.path.hasPrefix(지울공간.path + "/") },
      "\(wsStore.openTabs.map(\.lastPathComponent))")
check("다른 공간의 탭은 남음",
      wsStore.openTabs == [남길공간.appendingPathComponent("남는 노트.md")],
      "\(wsStore.openTabs.map(\.lastPathComponent))")
check("사라진 공간으로 잘못 표시하지 않음", wsStore.missingWorkspacePaths.isEmpty,
      "\(wsStore.missingWorkspacePaths)")

check("남길 공간은 그대로", fm.fileExists(atPath: 남길공간.appendingPathComponent("남는 노트.md").path))
check("남길 공간 노트도 목록에 있음", wsStore.notes.contains { $0.title == "남는 노트" },
      "\(wsStore.notes.map(\.title))")

check("잡아 둔 공간이 없으면 아무 일도 없음", wsStore.confirmWorkspaceTrash() == nil)
check("이미 없는 폴더는 조용히 실패", wsStore.moveWorkspaceToTrash(지울) == nil)

// 검증이 휴지통에 남긴 것들을 치운다
for url in leftInTrash { try? fm.removeItem(at: url) }
check("검증이 휴지통에 남긴 것 정리", leftInTrash.allSatisfy { !fm.fileExists(atPath: $0.path) },
      "\(leftInTrash.map(\.lastPathComponent))")

try? fm.removeItem(at: sandbox)
try? fm.removeItem(at: WorkspaceConfig.directory)
print("\n" + (failures.isEmpty ? "ALL PASS (\(total) checks)" : "FAILURES(\(failures.count)/\(total)): \(failures.joined(separator: ", "))"))
exit(failures.isEmpty ? 0 : 1)
