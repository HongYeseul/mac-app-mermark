import AppKit
import Carbon.HIToolbox

// 검증이 실제 ~/.config/mermark을 건드리지 않도록 전용 설정 폴더를 쓴다
WorkspaceConfig.directory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("mermark-config-capture-\(ProcessInfo.processInfo.processIdentifier)")


// 빠른 메모 저장 규칙과 전역 단축키 등록을 확인한다.

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
let folder = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("mermark-capture-\(ProcessInfo.processInfo.processIdentifier)")
try? fm.removeItem(at: folder)
try! fm.createDirectory(at: folder, withIntermediateDirectories: true)

// 기준 시각을 고정해 파일명을 결정적으로 만든다
var components = DateComponents()
components.year = 2026; components.month = 7; components.day = 31
components.hour = 14; components.minute = 32
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone.current
let timestamp = calendar.date(from: components)!

print("── A. 파일명 규칙")
check("시각 기반 이름", NoteStore.captureName(for: timestamp) == "2026-07-31 1432",
      NoteStore.captureName(for: timestamp))
check("지역 설정과 무관하게 같은 형식",
      NoteStore.captureName(for: timestamp).count == 15,
      NoteStore.captureName(for: timestamp))

print("\n── B. 저장")
WorkspaceConfig.save([folder])
let store = NoteStore()
pump(0.4)

let saved = store.quickCapture("회의에서 나온 아이디어\n두 번째 줄", at: timestamp)
check("파일이 생성됨", saved != nil && fm.fileExists(atPath: saved!.path), "\(saved?.path ?? "nil")")
check("시각 기반 파일명", saved?.lastPathComponent == "2026-07-31 1432.md", "\(saved?.lastPathComponent ?? "nil")")
check("본문이 그대로 저장됨",
      (try? String(contentsOf: saved!, encoding: .utf8)) == "회의에서 나온 아이디어\n두 번째 줄",
      "\((try? String(contentsOf: saved!, encoding: .utf8)) ?? "nil")")
check("노트 목록에 즉시 반영", store.notes.contains { $0.url == saved }, "\(store.notes.map(\.title))")

let second = store.quickCapture("같은 분에 또 적음", at: timestamp)
check("같은 시각이면 번호가 붙음", second?.lastPathComponent == "2026-07-31 1432 2.md",
      "\(second?.lastPathComponent ?? "nil")")

check("빈 내용은 저장하지 않음", store.quickCapture("   \n\n  ", at: timestamp) == nil)
check("빈 내용으로 파일이 늘지 않음", store.notes.count == 2, "\(store.notes.count)")

// 앞뒤 공백은 다듬어 저장
let trimmed = store.quickCapture("\n\n  가운데만 남긴다  \n\n", at: timestamp)
check("앞뒤 공백 정리", (try? String(contentsOf: trimmed!, encoding: .utf8)) == "가운데만 남긴다",
      "\((try? String(contentsOf: trimmed!, encoding: .utf8)) ?? "nil")")

// 메인 창의 선택 상태를 건드리지 않아야 한다
store.select(saved)
let selectionBefore = store.selectedNoteURL
_ = store.quickCapture("선택은 그대로", at: timestamp)
check("빠른 메모는 현재 선택을 바꾸지 않음", store.selectedNoteURL == selectionBefore,
      "\(store.selectedNoteURL?.lastPathComponent ?? "nil")")

// 노트 폴더가 없으면 저장하지 않는다
WorkspaceConfig.save([])
let emptyStore = NoteStore()
check("작업 공간이 없으면 저장하지 않음", emptyStore.quickCapture("내용", at: timestamp) == nil)

print("\n── C. 전역 단축키")
var pressed = 0
let hotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey | shiftKey)) { pressed += 1 }
check("단축키 등록 성공", hotKey != nil)

// 같은 조합을 두 번 등록하면 실패해야 한다 (앱이 조용히 어긋나지 않도록)
let duplicate = GlobalHotKey(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey | shiftKey)) { }
check("같은 조합 중복 등록은 거부", duplicate == nil, "중복 등록이 성공해 버림")

// 해제 후에는 같은 조합을 다시 등록할 수 있어야 한다 (해제 누락 확인)
var releasable: GlobalHotKey? = GlobalHotKey(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(cmdKey | shiftKey)) { }
check("다른 조합도 등록 가능", releasable != nil)
releasable = nil
let reRegistered = GlobalHotKey(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(cmdKey | shiftKey)) { }
check("해제 후 같은 조합 재등록 가능", reRegistered != nil, "deinit에서 해제되지 않음")

try? fm.removeItem(at: folder)
print("\n" + (failures.isEmpty ? "ALL PASS (\(total) checks)" : "FAILURES(\(failures.count)/\(total)): \(failures.joined(separator: ", "))"))
exit(failures.isEmpty ? 0 : 1)
