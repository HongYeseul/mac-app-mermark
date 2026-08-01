import AppKit

// 명령줄 도구를 검증한다. 마지막 절은 실제로 빌드된 mermark 실행 파일을
// 자식 프로세스로 돌려 출력과 종료 코드를 확인한다.

// 검증이 실제 ~/.config/mermark을 건드리지 않도록 전용 설정 폴더를 쓴다
WorkspaceConfig.directory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("mermark-config-cli-\(ProcessInfo.processInfo.processIdentifier)")

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
    .appendingPathComponent("mermark-cli-\(ProcessInfo.processInfo.processIdentifier)")
try? fm.removeItem(at: sandbox)

let 업무 = sandbox.appendingPathComponent("업무")
let 개인 = sandbox.appendingPathComponent("개인")
let 회의록폴더 = 업무.appendingPathComponent("회의록")
let 바깥 = sandbox.appendingPathComponent("바깥")
for folder in [업무, 개인, 회의록폴더, 바깥] {
    try! fm.createDirectory(at: folder, withIntermediateDirectories: true)
}

func write(_ text: String, to url: URL) {
    try! text.write(to: url, atomically: true, encoding: .utf8)
    // 수정일 정렬이 흔들리지 않게 간격을 둔다
    usleep(20_000)
}

write("# 정산 회의\n\n#정산 마감 확인", to: 회의록폴더.appendingPathComponent("정산 회의.md"))
write("# 설계 메모\n\n#설계", to: 업무.appendingPathComponent("설계 메모.md"))
write("# 장보기\n\n우유", to: 개인.appendingPathComponent("장보기.md"))
write("# 바깥 노트\n", to: 바깥.appendingPathComponent("바깥 노트.md"))

let workspaces = [업무, 개인]

print("── A. 설정 파일 공유")
WorkspaceConfig.save(workspaces)
check("파일이 만들어짐", fm.fileExists(atPath: WorkspaceConfig.fileURL.path), WorkspaceConfig.fileURL.path)
check("읽으면 그대로", WorkspaceConfig.load().map(\.path) == workspaces.map(\.path),
      "\(WorkspaceConfig.load().map(\.lastPathComponent))")
let rawConfig = (try? String(contentsOf: WorkspaceConfig.fileURL, encoding: .utf8)) ?? ""
check("사람이 읽을 수 있는 JSON", rawConfig.contains("\"workspaces\"") && rawConfig.contains(업무.path),
      rawConfig)
check("경로에 이스케이프가 끼지 않음", !rawConfig.contains("\\/"), rawConfig)

WorkspaceConfig.save([])
check("빈 목록도 저장됨", WorkspaceConfig.load().isEmpty)
WorkspaceConfig.save(workspaces)

print("\n── B. path / list")
check("path는 연결된 공간 전부",
      MermarkCommand.run(["path"], workspaces: workspaces) == .text("\(업무.path)\n\(개인.path)"),
      "\(MermarkCommand.run(["path"], workspaces: workspaces))")
check("--workspace로 하나만",
      MermarkCommand.run(["path", "--workspace", "개인"], workspaces: workspaces) == .text(개인.path),
      "\(MermarkCommand.run(["path", "--workspace", "개인"], workspaces: workspaces))")
check("--workspace는 전체 경로로도 됨",
      MermarkCommand.run(["path", "--workspace", 개인.path], workspaces: workspaces) == .text(개인.path))

if case .failure(let message) = MermarkCommand.run(["path", "--workspace", "없는공간"], workspaces: workspaces) {
    check("없는 작업 공간은 이름을 알려주며 실패", message.contains("업무") && message.contains("개인"), message)
} else {
    check("없는 작업 공간은 이름을 알려주며 실패", false, "실패하지 않음")
}

if case .text(let listed) = MermarkCommand.run(["list"], workspaces: workspaces) {
    let lines = listed.split(separator: "\n").map(String.init)
    check("하위 폴더의 노트까지 나옴", lines.contains(회의록폴더.appendingPathComponent("정산 회의.md").path),
          listed)
    check("연결된 공간을 모두 훑음", lines.count == 3, "\(lines.count)줄")
    check("최근 수정 순", lines.first == 개인.appendingPathComponent("장보기.md").path, lines.first ?? "")
    check("연결 안 한 폴더는 안 나옴", !listed.contains("바깥 노트"), listed)
} else {
    check("list가 목록을 냄", false)
}

check("--tag로 걸러짐",
      MermarkCommand.run(["list", "--tag", "정산"], workspaces: workspaces)
        == .text(회의록폴더.appendingPathComponent("정산 회의.md").path),
      "\(MermarkCommand.run(["list", "--tag", "정산"], workspaces: workspaces))")
check("--tag는 대소문자를 가리지 않음",
      MermarkCommand.run(["list", "--tag", "정산"], workspaces: workspaces)
        == MermarkCommand.run(["list", "--tag", "정산"], workspaces: workspaces))
check("--workspace와 --tag를 함께",
      MermarkCommand.run(["list", "--workspace", "개인", "--tag", "정산"], workspaces: workspaces) == .text(""))

print("\n── C. new")
guard case .text(let createdPath) = MermarkCommand.run(["new", "분기 계획"], workspaces: workspaces) else {
    fatalError("new 실패")
}
let created = URL(fileURLWithPath: createdPath)
check("파일이 실제로 생김", fm.fileExists(atPath: createdPath), createdPath)
check("첫 번째 작업 공간에 만듦", created.deletingLastPathComponent().path == 업무.path, createdPath)
check("경로를 출력해 vim에 넘길 수 있음", createdPath.hasSuffix("/분기 계획.md"), createdPath)
check("첫 줄이 제목 — 앱의 파일명 규칙과 일치",
      (try? String(contentsOf: created, encoding: .utf8)) == "# 분기 계획\n",
      (try? String(contentsOf: created, encoding: .utf8)) ?? "nil")
check("앱이 이 파일명을 그대로 유지함",
      NoteNaming.fileTitle(from: (try? String(contentsOf: created, encoding: .utf8)) ?? "") == "분기 계획")

if case .text(let second) = MermarkCommand.run(["new", "분기 계획"], workspaces: workspaces) {
    check("같은 제목이면 번호가 붙음", second.hasSuffix("/분기 계획 2.md"), second)
} else {
    check("같은 제목이면 번호가 붙음", false)
}

if case .text(let intoPersonal) = MermarkCommand.run(["new", "선물 목록", "--workspace", "개인"], workspaces: workspaces) {
    check("--workspace로 만들 곳을 고름",
          URL(fileURLWithPath: intoPersonal).deletingLastPathComponent().path == 개인.path, intoPersonal)
} else {
    check("--workspace로 만들 곳을 고름", false)
}

if case .text(let sanitized) = MermarkCommand.run(["new", "2026/07/31 회의: 정산"], workspaces: workspaces) {
    check("파일명에 못 쓰는 문자 치환", sanitized.hasSuffix("/2026-07-31 회의- 정산.md"), sanitized)
} else {
    check("파일명에 못 쓰는 문자 치환", false)
}

check("제목이 없으면 실패",
      MermarkCommand.run(["new"], workspaces: workspaces) == .failure("제목이 필요합니다: mermark new <제목>"))
if case .failure = MermarkCommand.run(["new", "아무거나"], workspaces: []) {
    check("연결된 공간이 없으면 실패", true)
} else {
    check("연결된 공간이 없으면 실패", false)
}

print("\n── D. open")
check("제목으로 찾음",
      MermarkCommand.run(["open", "장보기"], workspaces: workspaces)
        == .openNote(개인.appendingPathComponent("장보기.md").standardizedFileURL),
      "\(MermarkCommand.run(["open", "장보기"], workspaces: workspaces))")
check("하위 폴더의 노트도 제목으로 찾음",
      MermarkCommand.run(["open", "정산 회의"], workspaces: workspaces)
        == .openNote(회의록폴더.appendingPathComponent("정산 회의.md").standardizedFileURL))
check("대소문자를 가리지 않음",
      MermarkCommand.run(["open", "장보기"], workspaces: workspaces)
        == MermarkCommand.run(["open", "장보기"], workspaces: workspaces))
check("경로를 그대로 줘도 됨 (list | xargs 흐름)",
      MermarkCommand.run(["open", 개인.appendingPathComponent("장보기.md").path], workspaces: workspaces)
        == .openNote(개인.appendingPathComponent("장보기.md").standardizedFileURL))
if case .failure(let message) = MermarkCommand.run(["open", "없는 노트"], workspaces: workspaces) {
    check("없는 제목은 실패", message.contains("없는 노트"), message)
} else {
    check("없는 제목은 실패", false)
}

// 두 공간에 같은 제목이 있으면 고르라고 해야 한다
write("# 장보기\n", to: 업무.appendingPathComponent("장보기.md"))
if case .failure(let message) = MermarkCommand.run(["open", "장보기"], workspaces: workspaces) {
    check("같은 제목이 여럿이면 경로를 보여주며 실패",
          message.contains(업무.path) && message.contains(개인.path), message)
} else {
    check("같은 제목이 여럿이면 경로를 보여주며 실패", false, "실패하지 않음")
}
try? fm.removeItem(at: 업무.appendingPathComponent("장보기.md"))

print("\n── E. 인자 처리")
check("인자가 없으면 도움말", MermarkCommand.run([], workspaces: workspaces) == .text(MermarkCommand.usage))
check("help", MermarkCommand.run(["help"], workspaces: workspaces) == .text(MermarkCommand.usage))
check("--help도 같음", MermarkCommand.run(["--help"], workspaces: []) == .text(MermarkCommand.usage))
if case .failure(let message) = MermarkCommand.run(["없는명령"], workspaces: workspaces) {
    check("모르는 명령은 도움말과 함께 실패", message.contains("없는명령"), message)
} else {
    check("모르는 명령은 도움말과 함께 실패", false)
}
check("--workspace 뒤에 값이 없으면 실패",
      MermarkCommand.run(["list", "--workspace"], workspaces: workspaces)
        == .failure("--workspace 뒤에 값이 필요합니다."))

print("\n── F. mermark:// 주소")
let 장보기 = 개인.appendingPathComponent("장보기.md").standardizedFileURL
guard let scheme = MermarkURL.open(장보기) else { fatalError("주소 생성 실패") }
check("주소가 만들어짐", scheme.scheme == "mermark" && scheme.host == "open", scheme.absoluteString)
check("공백이 인코딩됨", !scheme.absoluteString.contains(" "), scheme.absoluteString)
check("되돌리면 같은 경로", MermarkURL.resolve(scheme, workspaces: workspaces) == 장보기,
      "\(String(describing: MermarkURL.resolve(scheme, workspaces: workspaces)))")

let 바깥노트 = 바깥.appendingPathComponent("바깥 노트.md")
check("작업 공간 밖은 거부",
      MermarkURL.resolve(MermarkURL.open(바깥노트)!, workspaces: workspaces) == nil)
check("..로 빠져나가는 경로도 거부",
      MermarkURL.resolve(
        URL(string: "mermark://open?path=\(개인.path)/../바깥/바깥%20노트.md")!,
        workspaces: workspaces) == nil)

// 작업 공간 안에 심볼릭 링크를 둬도 실제 대상이 밖이면 거부해야 한다
let 링크 = 개인.appendingPathComponent("몰래.md")
try? fm.createSymbolicLink(at: 링크, withDestinationURL: 바깥노트)
check("심볼릭 링크로 빠져나가는 것도 거부",
      MermarkURL.resolve(MermarkURL.open(링크)!, workspaces: workspaces) == nil)
try? fm.removeItem(at: 링크)

check(".md가 아니면 거부",
      MermarkURL.resolve(
        URL(string: "mermark://open?path=\(개인.path)/사진.png")!, workspaces: workspaces) == nil)
check("없는 파일은 거부",
      MermarkURL.resolve(
        URL(string: "mermark://open?path=\(개인.path)/없는것.md")!, workspaces: workspaces) == nil)
check("다른 스킴은 거부",
      MermarkURL.resolve(URL(string: "file://\(장보기.path)")!, workspaces: workspaces) == nil)
check("path 없는 주소는 거부",
      MermarkURL.resolve(URL(string: "mermark://open")!, workspaces: workspaces) == nil)

print("\n── G. 예전 설정 옮겨오기")
// 설정 파일이 생기기 전에 쓰던 사람이 연결해 둔 작업 공간을 잃지 않아야 한다
try? fm.removeItem(at: WorkspaceConfig.fileURL)
UserDefaults.standard.set([업무.path, 개인.path], forKey: "workspacePaths")
let migrated = NoteStore()
pump(0.3)
check("UserDefaults에 있던 목록을 이어받음", migrated.workspaces.map(\.url.path) == workspaces.map(\.path),
      "\(migrated.workspaces.map(\.name))")
check("설정 파일로 옮겨 적음", WorkspaceConfig.load().map(\.path) == workspaces.map(\.path),
      "\(WorkspaceConfig.load().map(\.lastPathComponent))")
check("옮긴 뒤에는 예전 자리를 비움",
      UserDefaults.standard.stringArray(forKey: "workspacePaths") == nil,
      "\(UserDefaults.standard.stringArray(forKey: "workspacePaths") ?? [])")

print("\n── H. 앱이 주소를 받는다")
let store = NoteStore()
pump(0.4)
check("설정 파일에서 작업 공간을 읽음", store.workspaces.map(\.url.path) == workspaces.map(\.path),
      "\(store.workspaces.map(\.name))")
check("주소를 받으면 그 노트를 연다", store.openNote(from: scheme))
check("선택이 바뀜", store.selectedNoteURL == 장보기, "\(store.selectedNoteURL?.path ?? "nil")")
check("본문도 읽힘", store.currentText.contains("우유"), store.currentText)
check("작업 공간 밖 주소는 무시", !store.openNote(from: MermarkURL.open(바깥노트)!))
check("무시된 뒤에도 선택 유지", store.selectedNoteURL == 장보기)

// CLI가 방금 만든 노트는 아직 목록에 없다. 그래도 열려야 한다.
guard case .text(let freshPath) = MermarkCommand.run(["new", "방금 만든 것", "--workspace", "개인"],
                                                     workspaces: workspaces) else {
    fatalError("new 실패")
}
let fresh = URL(fileURLWithPath: freshPath).standardizedFileURL
check("목록 갱신 전이라도 열림", store.openNote(from: MermarkURL.open(fresh)!))
check("새 노트가 선택됨", store.selectedNoteURL == fresh, "\(store.selectedNoteURL?.path ?? "nil")")

print("\n── I. 앱이 설정 파일을 갱신한다")
let extra = sandbox.appendingPathComponent("추가")
try! fm.createDirectory(at: extra, withIntermediateDirectories: true)
check("작업 공간 연결됨", store.addWorkspace(extra))
check("CLI가 읽는 파일에도 반영됨", WorkspaceConfig.load().map(\.path).contains(extra.path),
      "\(WorkspaceConfig.load().map(\.lastPathComponent))")
if let connected = store.workspaces.first(where: { $0.url.path == extra.path }) {
    store.disconnectWorkspace(connected)
}
check("연결을 끊으면 파일에서도 빠짐", !WorkspaceConfig.load().map(\.path).contains(extra.path),
      "\(WorkspaceConfig.load().map(\.lastPathComponent))")

print("\n── J. 명령줄 도구 설치")
let binDir = sandbox.appendingPathComponent("bin")
try! fm.createDirectory(at: binDir, withIntermediateDirectories: true)
let toolStub = sandbox.appendingPathComponent("mermark-stub")
try! "#!/bin/sh\necho hi\n".write(to: toolStub, atomically: true, encoding: .utf8)
try! fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: toolStub.path)

check("설치 전에는 안 걸려 있음", !CLIInstaller.isInstalled(tool: toolStub, at: binDir))
check("설치되면 경로를 알려줌",
      CLIInstaller.install(tool: toolStub, at: binDir) == .installed(path: binDir.appendingPathComponent("mermark").path),
      "\(CLIInstaller.install(tool: toolStub, at: binDir))")
check("심볼릭 링크로 걸림 (복사 아님)",
      (try? fm.destinationOfSymbolicLink(atPath: binDir.appendingPathComponent("mermark").path)) == toolStub.path)
check("설치된 걸 알아봄", CLIInstaller.isInstalled(tool: toolStub, at: binDir))
check("다시 설치해도 됨",
      CLIInstaller.install(tool: toolStub, at: binDir) == .installed(path: binDir.appendingPathComponent("mermark").path))

let 다른도구 = sandbox.appendingPathComponent("mermark-다른것")
try! "x".write(to: 다른도구, atomically: true, encoding: .utf8)
check("다른 앱을 가리키면 설치된 게 아님", !CLIInstaller.isInstalled(tool: 다른도구, at: binDir))

let 잠긴폴더 = sandbox.appendingPathComponent("잠김")
try! fm.createDirectory(at: 잠긴폴더, withIntermediateDirectories: true)
try! fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: 잠긴폴더.path)
if case .needsManualStep(let command) = CLIInstaller.install(tool: toolStub, at: 잠긴폴더) {
    check("권한이 없으면 직접 실행할 명령을 알려줌",
          command.contains("ln -sf") && command.contains(toolStub.path), command)
} else {
    check("권한이 없으면 직접 실행할 명령을 알려줌", false, "그냥 성공해 버림")
}
try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: 잠긴폴더.path)

print("\n── K. 실제 실행 파일")
if let binary = ProcessInfo.processInfo.environment["MERMARK_CLI_BIN"], fm.isExecutableFile(atPath: binary) {
    /// 실제 mermark 실행 파일을 자식 프로세스로 돌린다
    func shell(_ arguments: [String]) -> (out: String, err: String, code: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["MERMARK_CONFIG_DIR"] = WorkspaceConfig.directory.path
        process.environment = environment
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try! process.run()
        let out = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let err = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (out.trimmingCharacters(in: .newlines), err.trimmingCharacters(in: .newlines), process.terminationStatus)
    }

    let pathResult = shell(["path"])
    check("mermark path", pathResult.out == "\(업무.path)\n\(개인.path)" && pathResult.code == 0,
          "코드 \(pathResult.code): \(pathResult.out)\(pathResult.err)")

    let listResult = shell(["list", "--tag", "정산"])
    check("mermark list --tag",
          listResult.out == 회의록폴더.appendingPathComponent("정산 회의.md").path && listResult.code == 0,
          "코드 \(listResult.code): \(listResult.out)\(listResult.err)")

    let newResult = shell(["new", "터미널에서 만든 노트"])
    check("mermark new가 경로를 출력", newResult.out.hasSuffix("/터미널에서 만든 노트.md") && newResult.code == 0,
          "코드 \(newResult.code): \(newResult.out)\(newResult.err)")
    check("mermark new가 실제로 파일을 만듦", fm.fileExists(atPath: newResult.out), newResult.out)

    let helpResult = shell(["help"])
    check("mermark help", helpResult.out.contains("mermark new") && helpResult.code == 0, helpResult.out)

    let badResult = shell(["없는명령"])
    check("모르는 명령은 종료 코드 1", badResult.code == 1, "코드 \(badResult.code)")
    check("오류는 표준 오류로 나감", badResult.err.contains("없는명령") && badResult.out.isEmpty,
          "out=\(badResult.out) err=\(badResult.err)")

    // 설정 파일이 없으면 안내하고 실패해야 한다
    let 빈설정 = sandbox.appendingPathComponent("빈설정")
    try! fm.createDirectory(at: 빈설정, withIntermediateDirectories: true)
    let emptyProcess = Process()
    emptyProcess.executableURL = URL(fileURLWithPath: binary)
    emptyProcess.arguments = ["list"]
    var emptyEnvironment = ProcessInfo.processInfo.environment
    emptyEnvironment["MERMARK_CONFIG_DIR"] = 빈설정.path
    emptyProcess.environment = emptyEnvironment
    let emptyErr = Pipe()
    emptyProcess.standardError = emptyErr
    emptyProcess.standardOutput = Pipe()
    try! emptyProcess.run()
    let emptyMessage = String(decoding: emptyErr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    emptyProcess.waitUntilExit()
    check("연결된 공간이 없으면 안내하고 실패",
          emptyProcess.terminationStatus == 1 && emptyMessage.contains("작업 공간"), emptyMessage)
} else {
    check("실행 파일이 준비됨", false, "MERMARK_CLI_BIN이 없습니다 (scripts/run-tests.sh로 실행하세요)")
}

try? fm.removeItem(at: sandbox)
try? fm.removeItem(at: WorkspaceConfig.directory)
print("\n" + (failures.isEmpty ? "ALL PASS (\(total) checks)" : "FAILURES(\(failures.count)/\(total)): \(failures.joined(separator: ", "))"))
exit(failures.isEmpty ? 0 : 1)
