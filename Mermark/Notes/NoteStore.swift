import AppKit
import Foundation

struct Note: Identifiable, Hashable {
    let url: URL
    let modifiedAt: Date

    var id: URL { url }
    var title: String { url.deletingPathExtension().lastPathComponent }
}

/// 노트 폴더 상태: 폴더 선택, 노트 목록, 선택된 노트 로드/자동 저장,
/// 첫 줄 기준 파일명 동기화, FSEvents 외부 변경 감지
final class NoteStore: ObservableObject {
    @Published var folderURL: URL?
    @Published var notes: [Note] = []
    @Published var selectedNoteURL: URL?
    @Published var currentText: String = ""
    /// Cmd+N 직후 에디터로 포커스를 넘기기 위한 신호 (값이 바뀌면 에디터가 first responder가 됨)
    @Published private(set) var focusRequestID = 0
    @Published var searchQuery = ""
    @Published var selectedTag: String?
    /// 저장된 노트 폴더를 쓸 수 없을 때. 화면에 사정을 알리고 다시 고르게 하려고 둔다.
    @Published private(set) var unavailableFolderPath: String?
    /// 메뉴에서 PDF 내보내기를 고르면 프리뷰 쪽에서 처리하도록 ContentView가 연결한다
    var onExportPDF: (() -> Void)?

    static let untitledName = "새 노트"
    private static let maxTitleLength = 50

    private var saveWorkItem: DispatchWorkItem?
    private var eventStream: FSEventStreamRef?
    private let folderPathKey = "notesFolderPath"
    /// 파일명이 첫 줄과 이미 일치하는 노트만 이름을 따라가게 한다.
    /// 다른 앱에서 만든 "파일명 ≠ 제목" 노트를 앱이 멋대로 개명하지 않기 위한 안전장치.
    private var tracksFilename = false
    /// 본문 검색용 캐시. 수정일이 그대로면 파일을 다시 읽지 않는다.
    private var contentCache: [URL: (modifiedAt: Date, text: String)] = [:]
    /// 태그도 같은 기준으로 캐시한다. 목록을 그릴 때마다 모든 노트를 다시 파싱하지 않기 위함.
    private var tagCache: [URL: (modifiedAt: Date, tags: [String])] = [:]

    init() {
        if let path = UserDefaults.standard.string(forKey: folderPathKey) {
            if isUsableFolder(path) {
                openFolder(URL(fileURLWithPath: path))
            } else {
                // 폴더가 옮겨지거나 지워진 경우. 빈 화면만 두면 무엇이 잘못됐는지 알 수 없다.
                unavailableFolderPath = path
            }
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

    // MARK: - 노트 폴더

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "이 폴더 사용"
        panel.message = "노트를 모아둘 폴더를 선택하세요"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: folderPathKey)
        selectedNoteURL = nil
        unavailableFolderPath = nil
        openFolder(url)
    }

    /// 창 부제로 보여줄 노트 폴더 경로. 홈 아래면 `~`로 줄인다.
    var folderDisplayPath: String? {
        guard let folderURL else { return nil }
        return (folderURL.path as NSString).abbreviatingWithTildeInPath
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// 노트 폴더 자체를 Finder에서 연다
    func revealFolderInFinder() {
        guard let folderURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folderURL])
    }

    private func isUsableFolder(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func openFolder(_ url: URL) {
        unavailableFolderPath = nil
        folderURL = url.standardizedFileURL
        reloadNotes()
        if selectedNoteURL == nil {
            select(notes.first?.url)
        }
        startWatching(url)
    }

    private func reloadNotes() {
        guard let folderURL else {
            notes = []
            return
        }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        notes = urls
            .filter { $0.pathExtension.lowercased() == "md" }
            // 목록은 /private/var, 직접 만든 URL은 /var 형태로 나와 == 비교가 어긋난다.
            // 표기를 맞춰야 이름 변경 후에도 사이드바 선택이 유지된다.
            .map { $0.standardizedFileURL }
            .map { url in
                let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return Note(url: url, modifiedAt: modifiedAt)
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }

        let alive = Set(notes.map(\.url))
        contentCache = contentCache.filter { alive.contains($0.key) }
        tagCache = tagCache.filter { alive.contains($0.key) }
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

    func toggleTag(_ tag: String) {
        selectedTag = (selectedTag?.caseInsensitiveCompare(tag) == .orderedSame) ? nil : tag
    }

    private func tags(of note: Note) -> [String] {
        if let cached = tagCache[note.url], cached.modifiedAt == note.modifiedAt {
            return cached.tags
        }
        let parsed = MarkdownTags.tags(in: content(of: note))
        tagCache[note.url] = (note.modifiedAt, parsed)
        return parsed
    }

    /// 태그를 고르면 먼저 걸러내고, 검색어는 제목이 걸린 노트를 앞에 둔다. 대소문자와 자모 차이는 무시.
    var filteredNotes: [Note] {
        var candidates = notes
        if let selectedTag {
            candidates = candidates.filter { note in
                tags(of: note).contains { $0.caseInsensitiveCompare(selectedTag) == .orderedSame }
            }
        }

        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return candidates }

        var titleMatches: [Note] = []
        var bodyMatches: [Note] = []
        for note in candidates {
            if note.title.localizedStandardContains(query) {
                titleMatches.append(note)
            } else if content(of: note).localizedStandardContains(query) {
                bodyMatches.append(note)
            }
        }
        return titleMatches + bodyMatches
    }

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
    /// 메뉴·툴바에서 부르는 새 노트. 노트 폴더가 없으면 먼저 고르게 한다.
    /// 폴더가 없다고 아무 반응이 없으면 기능이 막힌 것처럼 보인다.
    func createNoteChoosingFolderIfNeeded() {
        if folderURL == nil { chooseFolder() }
        createNote()
    }

    func createNote() {
        guard folderURL != nil, let url = uniqueURL(for: Self.untitledName, excluding: nil) else { return }
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
        guard !body.isEmpty, folderURL != nil,
              let url = uniqueURL(for: Self.captureName(for: timestamp), excluding: nil) else { return nil }
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
              let target = uniqueURL(for: desired, excluding: url),
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
    private func uniqueURL(for title: String, excluding current: URL?) -> URL? {
        guard let folderURL else { return nil }
        let fm = FileManager.default
        var candidate = folderURL.appendingPathComponent(title + ".md")
        var suffix = 2
        while fm.fileExists(atPath: candidate.path),
              candidate.path.lowercased() != current?.path.lowercased() {
            candidate = folderURL.appendingPathComponent("\(title) \(suffix).md")
            suffix += 1
        }
        return candidate
    }

    // MARK: - FSEvents 외부 변경 감지

    private func startWatching(_ url: URL) {
        stopWatching()
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
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        eventStream = stream
    }

    private func markFolderUnavailable() {
        // 대기 중인 저장이 사라진 폴더에 파일을 되살리지 않도록 먼저 취소한다
        saveWorkItem?.cancel()
        saveWorkItem = nil

        unavailableFolderPath = folderURL?.path
        folderURL = nil
        notes = []
        selectedNoteURL = nil
        currentText = ""
        selectedTag = nil
        contentCache = [:]
        tagCache = [:]

        // FSEvents 콜백 안에서 스트림을 정리하지 않도록 한 번 미룬다
        DispatchQueue.main.async { [weak self] in self?.stopWatching() }
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
        if let folderURL, !isUsableFolder(folderURL.path) {
            markFolderUnavailable()
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
