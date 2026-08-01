import AppKit
import Foundation

// 실제 앱 코드(NoteStore.swift)를 그대로 컴파일해 실파일·실 FSEvents로 검증한다.
// 모킹 없음: 진짜 파일을 만들고, 지우고, 밖에서 고친 뒤 앱 상태가 따라오는지 본다.

let fm = FileManager.default
let rootDir = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("mermark-local-tests-\(ProcessInfo.processInfo.processIdentifier)")

var failures: [String] = []
var total = 0
func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
    total += 1
    print("\(condition ? "PASS" : "FAIL"): \(name)\(condition ? "" : "  → \(detail())")")
    if !condition { failures.append(name) }
}

/// 메인 런루프를 돌려 디바운스 저장·FSEvents 콜백이 실제로 처리되게 한다
func pump(_ seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

func exists(_ name: String) -> Bool { fm.fileExists(atPath: rootDir.appendingPathComponent(name).path) }
func read(_ name: String) -> String? { try? String(contentsOf: rootDir.appendingPathComponent(name), encoding: .utf8) }

// MARK: - A. 첫 줄 → 파일명 규칙 (순수 함수)

print("── A. 첫 줄 → 파일명 규칙")
check("헤딩 기호 제거", NoteStore.fileTitle(from: "# 아키텍처 노트\n본문") == "아키텍처 노트",
      NoteStore.fileTitle(from: "# 아키텍처 노트\n본문"))
check("헤딩 없는 첫 줄 그대로", NoteStore.fileTitle(from: "그냥 메모\n둘째 줄") == "그냥 메모")
check("빈 텍스트 → 기본 이름", NoteStore.fileTitle(from: "") == "새 노트")
check("헤딩 기호만 → 기본 이름", NoteStore.fileTitle(from: "###   \n본문") == "새 노트")
check("금지 문자 / : 치환", NoteStore.fileTitle(from: "# 2026/07/31 회의: 정산") == "2026-07-31 회의- 정산",
      NoteStore.fileTitle(from: "# 2026/07/31 회의: 정산"))
check("앞의 점 제거 (숨김 파일 방지)", NoteStore.fileTitle(from: ".gitignore 설명") == "gitignore 설명",
      NoteStore.fileTitle(from: ".gitignore 설명"))
check("긴 제목 50자 절단", NoteStore.fileTitle(from: String(repeating: "가", count: 80)).count == 50)

// MARK: - 노트 폴더 준비

try? fm.removeItem(at: rootDir)
try! fm.createDirectory(at: rootDir, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: rootDir) }

try! "# 기존 노트\n본문".write(to: rootDir.appendingPathComponent("기존 노트.md"), atomically: true, encoding: .utf8)
try! "not markdown".write(to: rootDir.appendingPathComponent("무시할파일.txt"), atomically: true, encoding: .utf8)
UserDefaults.standard.set([rootDir.path], forKey: "workspacePaths")

let store = NoteStore()
pump(0.5)

// MARK: - B. Cmd+N 새 노트

print("\n── B. Cmd+N 새 노트")
check("초기 목록은 .md 1개 (txt 제외)", store.notes.count == 1, "\(store.notes.map(\.title))")

store.createNote()
check("새 노트 파일 생성", exists("새 노트.md"))
check("새 노트가 선택됨", store.selectedNoteURL?.lastPathComponent == "새 노트.md")
check("본문 비어 있음", store.currentText.isEmpty)
check("에디터 포커스 요청 발생", store.focusRequestID == 1)

store.createNote()
check("연속 생성 시 중복 회피", exists("새 노트 2.md"), "\(store.notes.map(\.title))")

// MARK: - C. 첫 줄 = 파일명 자동 변경

print("\n── C. 첫 줄 = 파일명 자동 변경")
store.select(rootDir.appendingPathComponent("새 노트.md"))
store.textChanged("# 회의록 2026/07/31\n내용")
pump(1.0)
check("첫 줄 기준으로 rename", exists("회의록 2026-07-31.md"), "\(store.notes.map(\.title))")
check("옛 파일명은 사라짐", !exists("새 노트.md"))
check("내용 보존", read("회의록 2026-07-31.md") == "# 회의록 2026/07/31\n내용")
check("선택 상태가 새 파일명을 따라감", store.selectedNoteURL?.lastPathComponent == "회의록 2026-07-31.md")

store.select(rootDir.appendingPathComponent("새 노트 2.md"))
store.textChanged("# 기존 노트\n다른 내용")
pump(1.0)
check("중복 제목은 suffix 부여", exists("기존 노트 2.md"), "\(store.notes.map(\.title))")
check("원래 동명 노트는 그대로", read("기존 노트.md") == "# 기존 노트\n본문")

// 대소문자 무시 파일시스템에서의 rename
store.select(rootDir.appendingPathComponent("기존 노트 2.md"))
store.textChanged("# abc\n내용")
pump(1.0)
check("소문자 제목 rename", exists("abc.md"), "\(store.notes.map(\.title))")
store.textChanged("# ABC\n내용")
pump(1.0)
check("대소문자만 바꾼 rename 성공", exists("ABC.md") && read("ABC.md") == "# ABC\n내용",
      "\(store.notes.map(\.title))")

// 다른 앱에서 만든 "파일명 ≠ 첫 줄" 노트를 앱이 개명하면 안 된다
try! "# 완전히 다른 제목\n본문".write(to: rootDir.appendingPathComponent("보존할 파일명.md"), atomically: true, encoding: .utf8)
pump(1.0)
store.select(rootDir.appendingPathComponent("보존할 파일명.md"))
store.textChanged("# 완전히 다른 제목\n본문 수정")
pump(1.0)
check("파일명≠제목 노트는 개명하지 않음", exists("보존할 파일명.md") && !exists("완전히 다른 제목.md"),
      "\(store.notes.map(\.title))")
check("개명 안 해도 내용은 저장됨", read("보존할 파일명.md") == "# 완전히 다른 제목\n본문 수정",
      read("보존할 파일명.md") ?? "nil")

// MARK: - D. FSEvents 외부 변경 감지

print("\n── D. FSEvents 외부 변경 감지")
try! "# 외부에서 만든 노트\n본문".write(to: rootDir.appendingPathComponent("외부 노트.md"), atomically: true, encoding: .utf8)
pump(1.5)
check("외부 생성 파일이 목록에 등장", store.notes.contains { $0.title == "외부 노트" }, "\(store.notes.map(\.title))")

store.select(rootDir.appendingPathComponent("외부 노트.md"))
check("외부 노트 선택됨", store.currentText == "# 외부에서 만든 노트\n본문")
try! "# 외부에서 만든 노트\n외부에서 수정함".write(to: rootDir.appendingPathComponent("외부 노트.md"), atomically: true, encoding: .utf8)
pump(1.5)
check("외부 수정이 에디터에 자동 반영", store.currentText == "# 외부에서 만든 노트\n외부에서 수정함",
      store.currentText)

store.textChanged("# 외부에서 만든 노트\n앱에서 입력한 최신 내용")
pump(2.0)
check("앱 저장 내용이 디스크에 반영", read("외부 노트.md") == "# 외부에서 만든 노트\n앱에서 입력한 최신 내용",
      read("외부 노트.md") ?? "nil")
check("외부 노트 파일명 보존", exists("외부 노트.md") && !exists("외부에서 만든 노트.md"))
check("자기 저장 이벤트로 되돌아가지 않음", store.currentText == "# 외부에서 만든 노트\n앱에서 입력한 최신 내용",
      store.currentText)

let deletedName = store.selectedNoteURL!.lastPathComponent
try! fm.removeItem(at: store.selectedNoteURL!)
pump(1.5)
check("삭제된 노트에서 다른 노트로 전환", store.selectedNoteURL?.lastPathComponent != deletedName,
      store.selectedNoteURL?.lastPathComponent ?? "nil")
pump(1.0)
check("대기 중 저장이 삭제된 파일을 되살리지 않음", !exists(deletedName))
check("전환된 노트 내용이 로드됨", store.selectedNoteURL == nil || !store.currentText.isEmpty)

// MARK: - E. 전문 검색

print("\n── E. 전문 검색 (제목 + 본문)")
for name in try! fm.contentsOfDirectory(atPath: rootDir.path) {
    try? fm.removeItem(at: rootDir.appendingPathComponent(name))
}
try! "# 배포 체크리스트\n서명과 공증 절차".write(to: rootDir.appendingPathComponent("배포 체크리스트.md"), atomically: true, encoding: .utf8)
try! "# 회의록\n배포 일정 논의함".write(to: rootDir.appendingPathComponent("회의록.md"), atomically: true, encoding: .utf8)
try! "# 잡담\n점심 메뉴".write(to: rootDir.appendingPathComponent("잡담.md"), atomically: true, encoding: .utf8)
try! "# Release Notes\nMermaid EXPORT 기능".write(to: rootDir.appendingPathComponent("Release Notes.md"), atomically: true, encoding: .utf8)
pump(1.5)

let searchStore = NoteStore()
pump(0.5)
check("검색 전에는 전체 노트", searchStore.filteredNotes.count == 4, "\(searchStore.filteredNotes.map(\.title))")

searchStore.searchQuery = "배포"
let hits = searchStore.filteredNotes.map(\.title)
check("제목·본문 모두에서 검색됨", Set(hits) == ["배포 체크리스트", "회의록"], "\(hits)")
check("제목 일치가 본문 일치보다 앞", hits.first == "배포 체크리스트", "\(hits)")

searchStore.searchQuery = "export"
check("대소문자 무시 본문 검색", searchStore.filteredNotes.map(\.title) == ["Release Notes"],
      "\(searchStore.filteredNotes.map(\.title))")

searchStore.searchQuery = "  배포  "
check("앞뒤 공백은 무시", searchStore.filteredNotes.count == 2, "\(searchStore.filteredNotes.map(\.title))")

searchStore.searchQuery = "존재하지않는단어"
check("결과 없으면 빈 목록", searchStore.filteredNotes.isEmpty, "\(searchStore.filteredNotes.map(\.title))")

searchStore.searchQuery = ""
check("검색어를 지우면 전체 복귀", searchStore.filteredNotes.count == 4)

// 캐시가 오래된 내용을 붙들고 있지 않은지
try! "# 잡담\n이제 배포 이야기".write(to: rootDir.appendingPathComponent("잡담.md"), atomically: true, encoding: .utf8)
pump(1.5)
searchStore.searchQuery = "배포"
check("외부 수정 후 검색 결과 갱신", searchStore.filteredNotes.contains { $0.title == "잡담" },
      "\(searchStore.filteredNotes.map(\.title))")

// MARK: - F. 노트 폴더가 없을 때

print("\n── F. 노트 폴더가 없을 때")
UserDefaults.standard.removeObject(forKey: "workspacePaths")
let emptyStore = NoteStore()
pump(0.3)
check("폴더가 없으면 목록도 비어 있음", emptyStore.notes.isEmpty && emptyStore.workspaces.isEmpty,
      "\(emptyStore.notes.count)개")
emptyStore.createNote()
check("폴더가 없으면 새 노트를 만들지 않고 조용히 넘어감",
      emptyStore.notes.isEmpty && emptyStore.selectedNoteURL == nil,
      "\(emptyStore.selectedNoteURL?.lastPathComponent ?? "nil")")

// 폴더가 생기면 곧바로 만들 수 있어야 한다
UserDefaults.standard.set([rootDir.path], forKey: "workspacePaths")
let readyStore = NoteStore()
pump(0.3)
let beforeCount = readyStore.notes.count
readyStore.createNote()
check("폴더가 있으면 새 노트가 만들어짐", readyStore.notes.count == beforeCount + 1,
      "\(beforeCount) → \(readyStore.notes.count)")
check("만든 노트가 선택됨", readyStore.selectedNoteURL?.lastPathComponent.hasPrefix("새 노트") == true,
      "\(readyStore.selectedNoteURL?.lastPathComponent ?? "nil")")

// MARK: - G. 노트 폴더를 쓸 수 없을 때 (이슈 #1)

print("\n── G. 노트 폴더를 쓸 수 없을 때")
let goneDir = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("mermark-사라질폴더-\(ProcessInfo.processInfo.processIdentifier)")
try! fm.createDirectory(at: goneDir, withIntermediateDirectories: true)
try! "# 노트".write(to: goneDir.appendingPathComponent("노트.md"), atomically: true, encoding: .utf8)

// 1) 시작할 때 저장된 경로가 없으면 사정을 알린다
UserDefaults.standard.set([goneDir.path + "-없는경로"], forKey: "workspacePaths")
let missingStore = NoteStore()
pump(0.3)
check("없는 경로면 폴더를 열지 않음", missingStore.workspaces.isEmpty)
check("없는 경로를 알려줌", missingStore.unavailableFolderPath == goneDir.path + "-없는경로",
      missingStore.unavailableFolderPath ?? "nil")

// 2) 폴더가 아니라 파일을 가리켜도 마찬가지
let filePath = goneDir.appendingPathComponent("노트.md").path
UserDefaults.standard.set([filePath], forKey: "workspacePaths")
let filePointingStore = NoteStore()
pump(0.3)
check("폴더가 아닌 경로도 걸러냄", filePointingStore.workspaces.isEmpty
      && filePointingStore.unavailableFolderPath == filePath,
      filePointingStore.unavailableFolderPath ?? "nil")

// 3) 정상 폴더면 안내를 띄우지 않는다
UserDefaults.standard.set([goneDir.path], forKey: "workspacePaths")
let liveStore = NoteStore()
pump(0.4)
check("정상 폴더면 안내 없음", !liveStore.workspaces.isEmpty && liveStore.unavailableFolderPath == nil,
      liveStore.unavailableFolderPath ?? "nil")
check("노트도 정상적으로 읽힘", liveStore.notes.count == 1, "\(liveStore.notes.count)")

// 4) 쓰던 중에 폴더가 사라지면 알아채고 정리한다
liveStore.textChanged("# 노트\n저장 대기 중인 내용")
try! fm.removeItem(at: goneDir)
pump(2.0)
check("사용 중 폴더가 사라지면 알아챔", liveStore.unavailableFolderPath == goneDir.path,
      liveStore.unavailableFolderPath ?? "nil")
check("목록과 선택을 비움",
      liveStore.notes.isEmpty && liveStore.selectedNoteURL == nil && liveStore.workspaces.isEmpty,
      "노트 \(liveStore.notes.count)개")
pump(1.0)
check("대기 중이던 저장이 폴더를 되살리지 않음", !fm.fileExists(atPath: goneDir.path))

// MARK: - H. 작업 폴더 위치 보여주기

print("\n── H. 작업 폴더 위치")
UserDefaults.standard.set([rootDir.path], forKey: "workspacePaths")
let pathStore = NoteStore()
pump(0.3)
check("작업 공간 경로를 알려줌", pathStore.workspaces.first?.displayPath != nil)
check("경로가 실제 폴더를 가리킴",
      pathStore.workspaces.first?.displayPath.hasSuffix(rootDir.lastPathComponent) == true,
      pathStore.workspaces.first?.displayPath ?? "nil")

// 홈 아래 경로는 ~ 로 줄여 창 부제가 길어지지 않게 한다
let home = FileManager.default.homeDirectoryForCurrentUser
let underHome = home.appendingPathComponent("mermark-경로표시-\(ProcessInfo.processInfo.processIdentifier)")
try! fm.createDirectory(at: underHome, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: underHome) }
UserDefaults.standard.set([underHome.path], forKey: "workspacePaths")
let homeStore = NoteStore()
pump(0.3)
check("홈 아래 경로는 ~ 로 줄임", homeStore.workspaces.first?.displayPath.hasPrefix("~/") == true,
      homeStore.workspaces.first?.displayPath ?? "nil")
check("줄인 경로에도 폴더 이름이 남음",
      homeStore.workspaces.first?.displayPath.contains("mermark-경로표시") == true,
      homeStore.workspaces.first?.displayPath ?? "nil")

UserDefaults.standard.removeObject(forKey: "workspacePaths")
let noFolderStore = NoteStore()
pump(0.2)
check("작업 공간이 없으면 경로도 없음", noFolderStore.workspaces.isEmpty,
      "\(noFolderStore.workspaces.count)")

// MARK: - I. 여러 작업 공간

print("\n── I. 여러 작업 공간")
UserDefaults.standard.removeObject(forKey: "recentFolderPaths")
UserDefaults.standard.removeObject(forKey: "workspacePaths")

let spaceA = rootDir.appendingPathComponent("작업공간A")
let spaceB = rootDir.appendingPathComponent("작업공간B")
let nested = spaceA.appendingPathComponent("하위/더깊은")
try! fm.createDirectory(at: nested, withIntermediateDirectories: true)
try! fm.createDirectory(at: spaceB, withIntermediateDirectories: true)
try! "# A 최상위".write(to: spaceA.appendingPathComponent("A최상위.md"), atomically: true, encoding: .utf8)
try! "# A 하위".write(to: nested.appendingPathComponent("A하위.md"), atomically: true, encoding: .utf8)
try! "# B 노트".write(to: spaceB.appendingPathComponent("B노트.md"), atomically: true, encoding: .utf8)

let spaces = NoteStore()
pump(0.3)
check("처음엔 연결된 작업 공간 없음", spaces.workspaces.isEmpty)

spaces.addWorkspace(spaceA)
pump(0.4)
check("작업 공간 하나 연결", spaces.workspaces.count == 1, "\(spaces.workspaces.count)")
check("하위 폴더의 노트까지 읽음", spaces.notes.count == 2, "\(spaces.notes.map(\.title))")
let deepNote = spaces.notes.first { $0.title == "A하위" }
check("하위 경로를 알려줌", deepNote?.subfolder == "하위/더깊은", deepNote?.subfolder ?? "nil")
check("최상위 노트는 하위 경로 없음",
      spaces.notes.first { $0.title == "A최상위" }?.subfolder == nil)

spaces.addWorkspace(spaceB)
pump(0.4)
check("작업 공간 둘 연결", spaces.workspaces.count == 2, "\(spaces.workspaces.map(\.name))")
check("두 공간의 노트가 모두 보임", spaces.notes.count == 3, "\(spaces.notes.map(\.title))")
check("공간별로 나눠 볼 수 있음",
      spaces.notes(in: spaces.workspaces[1]).map(\.title) == ["B노트"],
      "\(spaces.notes(in: spaces.workspaces[1]).map(\.title))")

spaces.addWorkspace(spaceA)
check("같은 폴더를 두 번 연결하지 않음", spaces.workspaces.count == 2, "\(spaces.workspaces.count)")

// 검색은 연결된 공간 전체를 훑는다
spaces.searchQuery = "노트"
check("검색이 여러 공간에 걸침", spaces.filteredNotes.contains { $0.title == "B노트" },
      "\(spaces.filteredNotes.map(\.title))")
spaces.searchQuery = ""

// 지정한 공간에 새 노트를 만든다
spaces.createNote(in: spaceB)
pump(0.3)
check("고른 공간에 새 노트가 생김",
      fm.fileExists(atPath: spaceB.appendingPathComponent("새 노트.md").path))
check("새 노트가 그 공간 소속으로 잡힘",
      spaces.notes(in: spaces.workspaces[1]).contains { $0.title == "새 노트" },
      "\(spaces.notes(in: spaces.workspaces[1]).map(\.title))")

// 기본 공간은 지금 보고 있는 노트를 따라간다
spaces.select(spaceB.appendingPathComponent("B노트.md"))
check("보던 노트의 공간이 기본이 됨", spaces.defaultWorkspace?.url == spaceB.standardizedFileURL,
      spaces.defaultWorkspace?.name ?? "nil")

spaces.disconnectWorkspace(spaces.workspaces[1])
pump(0.4)
check("연결 해제하면 목록에서 빠짐", spaces.workspaces.count == 1, "\(spaces.workspaces.map(\.name))")
check("해제한 공간의 노트도 사라짐", !spaces.notes.contains { $0.title == "B노트" },
      "\(spaces.notes.map(\.title))")
check("해제한 공간의 노트를 보고 있었으면 선택이 풀림", spaces.selectedNoteURL == nil,
      spaces.selectedNoteURL?.lastPathComponent ?? "nil")
check("파일 자체는 지우지 않음",
      fm.fileExists(atPath: spaceB.appendingPathComponent("B노트.md").path))

// 하위 폴더에서 외부로 파일을 추가해도 잡아낸다
try! "# 나중에 추가".write(to: nested.appendingPathComponent("나중.md"), atomically: true, encoding: .utf8)
pump(1.5)
check("하위 폴더의 외부 추가도 감지", spaces.notes.contains { $0.title == "나중" },
      "\(spaces.notes.map(\.title))")

print("\n" + (failures.isEmpty ? "ALL PASS (\(total) checks)" : "FAILURES(\(failures.count)/\(total)): \(failures.joined(separator: ", "))"))
try? fm.removeItem(at: rootDir)
try? fm.removeItem(at: goneDir)
try? fm.removeItem(at: underHome)
exit(failures.isEmpty ? 0 : 1)
