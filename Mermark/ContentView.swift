import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case viewer, editor, split

    var id: String { rawValue }

    var label: String {
        switch self {
        case .viewer: "뷰어"
        case .editor: "에디터"
        case .split: "분할"
        }
    }

    var symbol: String {
        switch self {
        case .viewer: "doc.richtext"
        case .editor: "square.and.pencil"
        case .split: "rectangle.split.2x1"
        }
    }
}

struct ContentView: View {
    @ObservedObject var store: NoteStore
    @StateObject private var editor = EditorController()
    @StateObject private var preview = PreviewController()
    @AppStorage("viewMode") private var mode: ViewMode = .split
    @AppStorage("showsOutline") private var showsOutline = false
    /// 테마가 바뀔 때 화면을 다시 그리기 위한 값
    @State private var themeRevision = 0

    private var headings: [Heading] {
        MarkdownOutline.headings(in: store.currentText)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selectionBinding) {
                if !store.allTags.isEmpty {
                    Section("태그") {
                        ForEach(store.allTags, id: \.name) { tag in
                            tagRow(tag)
                        }
                    }
                }
                Section("노트") {
                    ForEach(store.filteredNotes) { note in
                        Label(note.title, systemImage: "doc.text")
                            .tag(note.url)
                            .contextMenu {
                                Button("Finder에서 보기") { store.revealInFinder(note.url) }
                                Button("경로 복사") { copyPath(note.url) }
                                Divider()
                                Button("노트 폴더를 Finder에서 보기") { store.revealFolderInFinder() }
                            }
                    }
                }
            }
            .searchable(text: $store.searchQuery, placement: .sidebar, prompt: "제목·본문 검색")
            .safeAreaInset(edge: .top, spacing: 0) { folderSwitcher }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            detail
                // 툴바를 detail에 붙여야 항목이 사이드바 쪽으로 몰려 잘리지 않는다
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        Button {
                            store.createNoteChoosingFolderIfNeeded()
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .help("새 노트 (⌘N)")

                        Button {
                            store.chooseFolder()
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help("노트 폴더 선택 (⌘O)")
                    }

                    ToolbarItemGroup(placement: .primaryAction) {
                        Picker("보기 모드", selection: $mode) {
                            ForEach(ViewMode.allCases) { mode in
                                Image(systemName: mode.symbol).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .help("뷰어 / 에디터 / 분할")

                        Button {
                            showsOutline.toggle()
                        } label: {
                            Image(systemName: showsOutline ? "sidebar.trailing" : "list.bullet.indent")
                        }
                        .help(showsOutline ? "목차 닫기 (⌘⌥T)" : "목차 열기 (⌘⌥T)")
                    }
                }
        }
        .navigationTitle(store.folderURL?.lastPathComponent ?? "Mermark")
        // 작업 폴더를 바꿀 수 있으니 지금 어디를 쓰는지 항상 보이게 한다
        .navigationSubtitle(store.folderDisplayPath ?? "")
        // 선택 강조·세그먼트 등 시스템 컨트롤까지 메인 색상을 따르게 한다
        .tint(Brand.accent)
        .inspector(isPresented: $showsOutline) {
            outline
                .inspectorColumnWidth(min: 180, ideal: 240, max: 360)
        }
        .onAppear {
            connectScrollSync()
            Brand.applyDockIcon()
        }
        .onReceive(NotificationCenter.default.publisher(for: Brand.didChange)) { _ in
            preview.applyBrandColors()
            themeRevision += 1        // 사이드바 색을 다시 그리게 한다
        }
    }

    private func copyPath(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
    }

    /// 검색창 바로 아래에서 지금 폴더를 보여주고, 눌러서 최근 폴더로 바로 옮겨간다
    private var folderSwitcher: some View {
        Menu {
            let others = store.recentFolders.filter { $0 != store.folderURL }
            if !others.isEmpty {
                Section("최근 폴더") {
                    ForEach(others, id: \.self) { folder in
                        Button {
                            store.openRecentFolder(folder)
                        } label: {
                            Text(folder.lastPathComponent)
                            Text((folder.path as NSString).abbreviatingWithTildeInPath)
                        }
                    }
                }
            }
            Button("다른 폴더 열기…") { store.chooseFolder() }
            if store.folderURL != nil {
                Button("Finder에서 보기") { store.revealFolderInFinder() }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder")
                    .foregroundStyle(Brand.accent)
                Text(store.folderURL?.lastPathComponent ?? "노트 폴더 선택")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    /// 누르면 그 태그만 보고, 다시 누르면 전체로 돌아간다
    private func tagRow(_ tag: (name: String, count: Int)) -> some View {
        let isSelected = store.selectedTag?.caseInsensitiveCompare(tag.name) == .orderedSame
        return Button {
            store.toggleTag(tag.name)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "tag.fill" : "tag")
                    .foregroundStyle(isSelected ? Brand.accent : .secondary)
                Text(tag.name)
                    .foregroundStyle(isSelected ? Brand.accent : .primary)
                Spacer()
                Text("\(tag.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detail: some View {
        if let missingPath = store.unavailableFolderPath {
            VStack(spacing: 10) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text("노트 폴더를 찾을 수 없습니다")
                    .font(.headline)
                Text(missingPath)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .frame(maxWidth: 420)
                Text("폴더가 옮겨졌거나 지워졌습니다. 다시 선택해 주세요.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("노트 폴더 선택…") { store.chooseFolder() }
                    .padding(.top, 4)
            }
            .padding(40)
        } else if store.folderURL == nil {
            VStack(spacing: 12) {
                Text("노트를 모아둘 폴더를 선택하세요")
                    .foregroundStyle(.secondary)
                Button("노트 폴더 열기") { store.chooseFolder() }
            }
        } else if store.selectedNoteURL == nil {
            Text("노트를 선택하세요")
                .foregroundStyle(.secondary)
        } else {
            HSplitView {
                if mode != .viewer {
                    MarkdownEditor(controller: editor, text: store.currentText, focusRequestID: store.focusRequestID)
                        .frame(minWidth: 300)
                }
                if mode != .editor {
                    MarkdownPreview(
                        controller: preview,
                        markdown: store.currentText,
                        noteURL: store.selectedNoteURL,
                        folderURL: store.folderURL
                    )
                    .frame(minWidth: 300)
                }
            }
        }
    }

    @ViewBuilder
    private var outline: some View {
        if headings.isEmpty {
            Text("헤딩이 없습니다")
                .foregroundStyle(.secondary)
        } else {
            List(headings) { heading in
                Button {
                    jump(to: heading)
                } label: {
                    Text(heading.text)
                        .font(heading.level <= 2 ? .body : .callout)
                        .foregroundStyle(heading.level == 1 ? .primary : .secondary)
                        .padding(.leading, CGFloat(heading.level - 1) * 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 목차 항목은 양쪽 창을 모두 직접 옮긴다 (한쪽만 옮기면 숨겨진 창이 뒤처진다)
    private func jump(to heading: Heading) {
        editor.scroll(toLine: heading.line)
        preview.scroll(toLine: heading.line)
    }

    /// 한쪽이 스크롤하면 반대쪽만 따라간다. 되돌아오는 것은 각 컨트롤러의 억제 구간이 막는다.
    private func connectScrollSync() {
        editor.onTextChange = { store.textChanged($0) }
        editor.onScrollToLine = { preview.scroll(toLine: $0) }
        preview.onScrollToLine = { editor.scroll(toLine: $0) }
        store.onExportPDF = {
            let name = store.selectedNoteURL?.deletingPathExtension().lastPathComponent ?? "document"
            preview.exportPDF(defaultName: name)
        }
        preview.onToggleTask = { store.toggleTask(atLine: $0) }
        preview.onSelectTag = { store.toggleTag($0) }
        preview.onOpenNote = { noteURL, anchor in
            store.select(noteURL)
            if let anchor { preview.scroll(toAnchor: anchor) }
        }
    }

    private var selectionBinding: Binding<URL?> {
        Binding(
            get: { store.selectedNoteURL },
            set: { store.select($0) }
        )
    }
}
