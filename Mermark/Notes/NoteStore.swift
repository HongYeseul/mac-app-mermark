import AppKit
import Foundation

/// 연결해 둔 작업 공간(폴더). 하위 폴더를 가질 수 있다.
struct Workspace: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    var name: String { url.lastPathComponent }
    var displayPath: String { (url.path as NSString).abbreviatingWithTildeInPath }
}

struct Note: Identifiable, Hashable {
    let url: URL
    /// 어느 작업 공간에 속한 노트인지
    let workspaceURL: URL
    let modifiedAt: Date

    var id: URL { url }
    var title: String { url.deletingPathExtension().lastPathComponent }

    /// 작업 공간 기준 하위 폴더 (최상위면 nil)
    var subfolder: String? {
        let base = workspaceURL.standardizedFileURL.path
        let full = url.standardizedFileURL.deletingLastPathComponent().path
        guard full.hasPrefix(base) else { return nil }
        let relative = String(full.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? nil : relative
    }
}

/// 노트 폴더 상태: 폴더 선택, 노트 목록, 선택된 노트 로드/자동 저장,
/// 첫 줄 기준 파일명 동기화, FSEvents 외부 변경 감지
final class NoteStore: ObservableObject {
    /// 연결해 둔 작업 공간들. 여러 개를 동시에 열어 둘 수 있다.
    @Published private(set) var workspaces: [Workspace] = []
    @Published var notes: [Note] = []
    @Published var selectedNoteURL: URL?
    @Published var currentText: String = ""
    /// Cmd+N 직후 에디터로 포커스를 넘기기 위한 신호 (값이 바뀌면 에디터가 first responder가 됨)
    @Published private(set) var focusRequestID = 0
    @Published var searchQuery = ""
    /// 저장된 노트 폴더를 쓸 수 없을 때. 화면에 사정을 알리고 다시 고르게 하려고 둔다.
    @Published private(set) var unavailableFolderPath: String?
    /// 메뉴에서 PDF 내보내기를 고르면 프리뷰 쪽에서 처리하도록 ContentView가 연결한다
    var onExportPDF: (() -> Void)?

    static let untitledName = "새 노트"
    private static let maxTitleLength = 50

    private var saveWorkItem: DispatchWorkItem?
    private var eventStream: FSEventStreamRef?
    private let workspacePathsKey = "workspacePaths"
    /// 파일명이 첫 줄과 이미 일치하는 노트만 이름을 따라가게 한다.
    /// 다른 앱에서 만든 "파일명 ≠ 제목" 노트를 앱이 멋대로 개명하지 않기 위한 안전장치.
    private var tracksFilename = false
    /// 본문 검색용 캐시. 수정일이 그대로면 파일을 다시 읽지 않는다.
    private var contentCache: [URL: (modifiedAt: Date, text: String)] = [:]
    /// 태그도 같은 기준으로 캐시한다. 목록을 그릴 때마다 모든 노트를 다시 파싱하지 않기 위함.
    private var tagCache: [URL: (modifiedAt: Date, tags: [String])] = [:]

    init() {
        loadRecentFolders()

        let saved = UserDefaults.standard.stringArray(forKey: workspacePathsKey) ?? []
        let usable = saved.filter { isUsableFolder($0) }
        // 옮겨지거나 지워진 작업 공간이 있으면 알린다. 빈 화면만 두면 무엇이 잘못됐는지 알 수 없다.
        if let missing = saved.first(where: { !isUsableFolder($0) }) {
            unavailableFolderPath = missing
        }
        workspaces = usable.map { Workspace(url: URL(fileURLWithPath: $0).standardizedFileURL) }
        if !workspaces.isEmpty {
            persistWorkspaces()
            reloadNotes()
            select(notes.first?.url)
            startWatching()
        }

        // 앱 비활성화/종료 시 대기 중인 자동 저장을 즉시 반영 (PLAN.md 4: 포커스 아웃 시 저장)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.flushPendingSave() }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.flushPendingSave() }
    }

    deinit {
        stopWatching()
    }

    // MARK: - 작업 공간

    /// 작업 공간을 하나 더 연결한다. 이미 있는 폴더면 아무 일도 하지 않는다.
    func connectWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "작업 공간으로 연결"
        panel.message = "노트를 모아둘 폴더를 고르세요. 하위 폴더도 함께 읽습니다."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { addWorkspace(url) }
    }

    @discardableResult
    func addWorkspace(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        guard isUsableFolder(standardized.path) else {
            unavailableFolderPath = standardized.path
            return false
        }
        guard !workspaces.contains(where: { $0.url == standardized }) else { return false }

        unavailableFolderPath = nil
        workspaces.append(Workspace(url: standardized))
        rememberRecentFolder(standardized)
        persistWorkspaces()
        reloadNotes()
        if selectedNoteURL == nil { select(notes.first?.url) }
        startWatching()
        return true
    }

    func disconnectWorkspace(_ workspace: Workspace) {
        workspaces.removeAll { $0.url == workspace.url }
        persistWorkspaces()

        // 지금 보던 노트가 끊긴 작업 공간 것이면 선택을 비운다
        if let selected = selectedNoteURL, isInside(selected, workspace.url) {
            flushPendingSave()
            selectedNoteURL = nil
            currentText = ""
        }
        reloadNotes()
        startWatching()
    }

    private func persistWorkspaces() {
        UserDefaults.standard.set(workspaces.map(\.url.path), forKey: workspacePathsKey)
    }

    private func isInside(_ url: URL, _ folder: URL) -> Bool {
        let base = folder.standardizedFileURL.path
        return url.standardizedFileURL.path.hasPrefix(base + "/")
    }

    /// 그 노트가 속한 작업 공간. 프리뷰가 "/"로 시작하는 이미지 경로를 풀 때 기준이 된다.
    func workspaceURL(for noteURL: URL?) -> URL? {
        guard let noteURL else { return nil }
        return workspaces.first { isInside(noteURL, $0.url) }?.url
    }

    /// 새 노트·빠른 메모가 기본으로 들어갈 작업 공간
    var defaultWorkspace: Workspace? {
        if let selected = selectedNoteURL,
           let owner = workspaces.first(where: { isInside(selected, $0.url) }) {
            return owner        // 지금 보던 노트와 같은 곳에 만드는 게 자연스럽다
        }
        return workspaces.first
    }

    /// 최근에 연 폴더. 최근 것이 앞.
    @Published private(set) var recentFolders: [URL] = []

    private let recentFoldersKey = "recentFolderPaths"
    private static let maxRecentFolders = 8

    private func loadRecentFolders() {
        let paths = UserDefaults.standard.stringArray(forKey: recentFoldersKey) ?? []
        recentFolders = paths.filter { isUsableFolder($0) }.map { URL(fileURLWithPath: $0) }
    }

    private func rememberRecentFolder(_ url: URL) {
        let path = url.standardizedFileURL.path
        var paths = (UserDefaults.standard.stringArray(forKey: recentFoldersKey) ?? [])
            .filter { $0 != path }
        paths.insert(path, at: 0)
        paths = Array(paths.prefix(Self.maxRecentFolders))
        UserDefaults.standard.set(paths, forKey: recentFoldersKey)
        loadRecentFolders()
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func isUsableFolder(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// 작업 공간마다 하위 폴더까지 훑어 .md를 모은다
    private func reloadNotes() {
        var collected: [Note] = []
        for workspace in workspaces {
            collected.append(contentsOf: scanNotes(in: workspace))
        }
        notes = collected.sorted { $0.modifiedAt > $1.modifiedAt }

        let alive = Set(notes.map(\.url))
        contentCache = contentCache.filter { alive.contains($0.key) }
        tagCache = tagCache.filter { alive.contains($0.key) }
    }

    private func scanNotes(in workspace: Workspace) -> [Note] {
        let manager = FileManager.default
        guard let walker = manager.enumerator(
            at: workspace.url,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var found: [Note] = []
        for case let url as URL in walker where url.pathExtension.lowercased() == "md" {
            let standardized = url.standardizedFileURL
            let modifiedAt = (try? standardized.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            found.append(Note(url: standardized, workspaceURL: workspace.url, modifiedAt: modifiedAt))
        }
        return found
    }

    /// 사이드바에서 작업 공간별로 묶어 보여주기 위한 목록
    func notes(in workspace: Workspace) -> [Note] {
        filteredNotes.filter { $0.workspaceURL == workspace.url }
    }

    /// 노트 폴더 전체의 태그를 많이 쓰인 순으로
    var allTags: [(name: String, count: Int)] {
        var counts: [String: (name: String, count: Int)] = [:]
        for note in notes {
            for tag in tags(of: note) {
                counts[tag.lowercased(), default: (tag, 0)].count += 1
            }
        }
        return counts.values.sorted {
            $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name
        }
    }

    /// 프리뷰의 체크박스를 눌렀을 때 원본을 고친다
    func toggleTask(atLine line: Int) {
        guard let updated = MarkdownTaskList.toggle(in: currentText, line: line) else { return }
        textChanged(updated)
    }

    /// 태그를 검색창에 넣거나 뺀다. 프리뷰에서 태그를 누를 때 쓴다.
    func toggleTag(_ tag: String) {
        searchQuery = SearchQuery.toggling(tag, in: searchQuery)
    }

    private func tags(of note: Note) -> [String] {
        if let cached = tagCache[note.url], cached.modifiedAt == note.modifiedAt {
            return cached.tags
        }
        let parsed = MarkdownTags.tags(in: content(of: note))
        tagCache[note.url] = (note.modifiedAt, parsed)
        return parsed
    }

    /// 검색창 하나로 태그와 글자를 함께 거른다.
    /// `#정산 회의` = 정산 태그가 붙은 노트 중 "회의"가 든 것. 제목이 걸린 노트를 앞에 둔다.
    var filteredNotes: [Note] {
        let query = SearchQuery.parse(searchQuery)
        guard !query.isEmpty else { return notes }

        var candidates = notes
        for tag in query.tags {
            candidates = candidates.filter { note in
                tags(of: note).contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
            }
        }
        guard !query.text.isEmpty else { return candidates }

        var titleMatches: [Note] = []
        var bodyMatches: [Note] = []
        for note in candidates {
            if note.title.localizedStandardContains(query.text) {
                titleMatches.append(note)
            } else if content(of: note).localizedStandardContains(query.text) {
                bodyMatches.append(note)
            }
        }
        return titleMatches + bodyMatches
    }

    /// 지금 검색창에 걸려 있는 태그들
    var activeTags: [String] { SearchQuery.parse(searchQuery).tags }

    private func content(of note: Note) -> String {
        if let cached = contentCache[note.url], cached.modifiedAt == note.modifiedAt {
            return cached.text
        }
        let text = (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
        contentCache[note.url] = (note.modifiedAt, text)
        return text
    }

    // MARK: - 노트 선택 / 생성

    func select(_ url: URL?) {
        flushPendingSave()
        selectedNoteURL = url
        guard let url else {
            currentText = ""
            tracksFilename = false
            return
        }
        currentText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        updateFilenameTracking(for: url)
    }

    private func updateFilenameTracking(for url: URL) {
        let name = url.deletingPathExtension().lastPathComponent
        // 첫 줄에서 파생된 이름(또는 아직 이름을 정하지 않은 "새 노트")일 때만 계속 따라간다
        tracksFilename = Self.isDerived(name, from: Self.fileTitle(from: currentText))
            || Self.isDerived(name, from: Self.untitledName)
    }

    /// "제목" 자체이거나 중복 회피로 "제목 2"처럼 숫자만 덧붙은 형태인지
    private static func isDerived(_ name: String, from title: String) -> Bool {
        if name == title { return true }
        guard name.hasPrefix(title + " ") else { return false }
        let suffix = name.dropFirst(title.count + 1)
        return !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
    }

    /// Cmd+N: 제목 입력 없이 빈 노트를 만들고 바로 타이핑할 수 있게 선택 + 포커스 (PLAN.md 4)
    /// 메뉴·툴바에서 부르는 새 노트. 연결된 작업 공간이 없으면 먼저 고르게 한다.
    /// 아무 반응이 없으면 기능이 막힌 것처럼 보인다.
    func createNoteChoosingWorkspaceIfNeeded() {
        if workspaces.isEmpty { connectWorkspace() }
        createNote()
    }

    /// 어디에 만들지 지정하지 않으면 기본 작업 공간에 만든다
    func createNote(in folder: URL? = nil) {
        let target = folder ?? defaultWorkspace?.url
        guard let target, let url = uniqueURL(for: Self.untitledName, in: target, excluding: nil) else { return }
        flushPendingSave()
        do {
            try "".write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSLog("노트 생성 실패: \(error.localizedDescription)")
            return
        }
        reloadNotes()
        selectedNoteURL = url
        currentText = ""
        tracksFilename = true
        focusRequestID += 1
    }

    /// 메뉴바·전역 단축키에서 부르는 빠른 메모. 제목을 묻지 않고 시각으로 파일명을 만든다.
    /// 메인 창의 선택 상태는 건드리지 않는다.
    @discardableResult
    func quickCapture(_ text: String, at timestamp: Date = Date()) -> URL? {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, let target = defaultWorkspace?.url,
              let url = uniqueURL(for: Self.captureName(for: timestamp), in: target, excluding: nil) else { return nil }
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSLog("빠른 메모 저장 실패: \(error.localizedDescription)")
            return nil
        }
        reloadNotes()
        return url
    }

    static func captureName(for timestamp: Date) -> String {
        let formatter = DateFormatter()
        // 사용자 지역 설정에 따라 형식이 흔들리지 않도록 고정한다
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return formatter.string(from: timestamp)
    }

    // MARK: - 자동 저장

    func textChanged(_ text: String) {
        currentText = text
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveWorkItem = nil
            self?.saveNow()
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    func flushPendingSave() {
        guard saveWorkItem != nil else { return }
        saveWorkItem?.cancel()
        saveWorkItem = nil
        saveNow()
    }

    private func saveNow() {
        guard let url = selectedNoteURL else { return }
        do {
            try currentText.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSLog("자동 저장 실패: \(error.localizedDescription)")
            return
        }
        syncFilename(of: url)
    }

    // MARK: - 첫 줄 = 파일명

    /// 첫 줄에서 파일명을 만든다. 마크다운 헤딩 기호와 파일명에 쓸 수 없는 문자를 제거. (PLAN.md 8)
    static func fileTitle(from text: String) -> String {
        var title = String(text.prefix(while: { $0 != "\n" })).trimmingCharacters(in: .whitespaces)
        while title.hasPrefix("#") { title.removeFirst() }
        // "/"는 경로 구분자, ":"는 Finder에서 "/"로 표시되므로 둘 다 치환
        title = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        // 앞의 "."을 남기면 숨김 파일이 되어 목록에서 사라진다
        while title.hasPrefix(".") { title.removeFirst() }
        title = title.trimmingCharacters(in: .whitespaces)
        if title.count > maxTitleLength {
            title = String(title.prefix(maxTitleLength)).trimmingCharacters(in: .whitespaces)
        }
        return title.isEmpty ? untitledName : title
    }

    private func syncFilename(of url: URL) {
        guard tracksFilename else { return }
        let desired = Self.fileTitle(from: currentText)
        guard desired != url.deletingPathExtension().lastPathComponent,
              let target = uniqueURL(for: desired, in: url.deletingLastPathComponent(), excluding: url),
              target != url else { return }
        do {
            try FileManager.default.moveItem(at: url, to: target)
            selectedNoteURL = target
            reloadNotes()
        } catch {
            NSLog("파일명 변경 실패: \(error.localizedDescription)")
        }
    }

    /// 같은 제목이 이미 있으면 "제목 2", "제목 3"으로 비켜 간다. (대소문자 무시 파일시스템 고려)
    private func uniqueURL(for title: String, in folder: URL, excluding current: URL?) -> URL? {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent(title + ".md")
        var suffix = 2
        while fm.fileExists(atPath: candidate.path),
              candidate.path.lowercased() != current?.path.lowercased() {
            candidate = folder.appendingPathComponent("\(title) \(suffix).md")
            suffix += 1
        }
        return candidate
    }

    // MARK: - FSEvents 외부 변경 감지

    private func startWatching() {
        stopWatching()
        guard !workspaces.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<NoteStore>.fromOpaque(info).takeUnretainedValue().handleExternalChange()
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            workspaces.map(\.url.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        eventStream = stream
    }

    private func markWorkspaceUnavailable(_ missing: URL) {
        // 대기 중인 저장이 사라진 폴더에 파일을 되살리지 않도록 먼저 취소한다
        saveWorkItem?.cancel()
        saveWorkItem = nil

        unavailableFolderPath = missing.path
        workspaces.removeAll { $0.url == missing }
        persistWorkspaces()
        reloadNotes()

        if let selected = selectedNoteURL, !FileManager.default.fileExists(atPath: selected.path) {
            selectedNoteURL = nil
            currentText = ""
        }
        // FSEvents 콜백 안에서 스트림을 갈아끼우지 않도록 한 번 미룬다
        DispatchQueue.main.async { [weak self] in self?.startWatching() }
    }

    private func stopWatching() {
        guard let eventStream else { return }
        FSEventStreamStop(eventStream)
        FSEventStreamInvalidate(eventStream)
        FSEventStreamRelease(eventStream)
        self.eventStream = nil
    }

    /// 우리 저장도 이벤트를 만들기 때문에, 디스크 내용이 실제로 다를 때만 반영해 되돌림 루프를 막는다.
    private func handleExternalChange() {
        // 노트 폴더 자체가 없어졌으면 목록만 비우지 말고 사정을 알린다
        if let missing = workspaces.first(where: { !isUsableFolder($0.url.path) }) {
            markWorkspaceUnavailable(missing.url)
            return
        }

        reloadNotes()
        guard let url = selectedNoteURL else { return }

        guard FileManager.default.fileExists(atPath: url.path) else {
            // 외부에서 삭제됨 — 대기 중인 저장이 파일을 되살리지 않도록 먼저 취소
            saveWorkItem?.cancel()
            saveWorkItem = nil
            select(notes.first?.url)
            return
        }

        guard saveWorkItem == nil,  // 타이핑 중이면 편집 중인 내용을 우선한다
              let diskText = try? String(contentsOf: url, encoding: .utf8),
              diskText != currentText else { return }
        currentText = diskText
        updateFilenameTracking(for: url)
    }
}
