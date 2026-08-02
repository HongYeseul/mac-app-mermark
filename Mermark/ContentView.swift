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
    /// 접어둔 작업 공간
    @State private var collapsedWorkspaces: Set<URL> = []

    private var headings: [Heading] {
        MarkdownOutline.headings(in: store.currentText)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selectionBinding) {
                ForEach(store.workspaces) { workspace in
                    Section(isExpanded: expansionBinding(for: workspace)) {
                        ForEach(store.notes(in: workspace)) { note in
                            noteRow(note)
                        }
                    } header: {
                        workspaceHeader(workspace)
                    }
                }
            }
            .searchable(text: $store.searchQuery, placement: .sidebar, prompt: "제목·본문 검색")
            .safeAreaInset(edge: .top, spacing: 0) { workspaceBar }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            detail
                // 툴바를 detail에 붙여야 항목이 사이드바 쪽으로 몰려 잘리지 않는다.
                // 새 노트와 작업 공간 연결은 탭 줄의 +, 작업 공간 헤더의 +,
                // 사이드바 "작업 공간 추가"에 이미 있어 여기 두지 않는다.
                .toolbar {
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
        .navigationTitle(store.workspaces.count == 1 ? store.workspaces[0].name : "Mermark")
        // 작업 폴더를 바꿀 수 있으니 지금 어디를 쓰는지 항상 보이게 한다
        .navigationSubtitle(store.workspaces.count == 1 ? store.workspaces[0].displayPath : "")
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

    private func expansionBinding(for workspace: Workspace) -> Binding<Bool> {
        Binding(
            get: { !collapsedWorkspaces.contains(workspace.url) },
            set: { expanded in
                if expanded { collapsedWorkspaces.remove(workspace.url) }
                else { collapsedWorkspaces.insert(workspace.url) }
            }
        )
    }

    /// 작업 공간 이름 줄. 누르면 접히고, + 로 그 안에 노트를 만든다.
    private func workspaceHeader(_ workspace: Workspace) -> some View {
        HStack(spacing: 4) {
            Text(workspace.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Button {
                store.createNote(in: workspace.url)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("\(workspace.name)에 새 노트")
        }
        .contextMenu {
            Button("Finder에서 보기") { store.revealInFinder(workspace.url) }
            Button("경로 복사") { copyPath(workspace.url) }
            Divider()
            Button("작업 공간 연결 해제") { store.disconnectWorkspace(workspace) }
        }
    }

    private func noteRow(_ note: Note) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(note.title)
                    .lineLimit(1)
                // 하위 폴더에 있는 노트는 어디 있는지 보여준다
                if let subfolder = note.subfolder {
                    Text(subfolder)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
        } icon: {
            Image(systemName: "doc.text")
        }
        .tag(note.url)
        .contextMenu {
            Button("Finder에서 보기") { store.revealInFinder(note.url) }
            Button("경로 복사") { copyPath(note.url) }
        }
    }

    /// 검색창 아래에서 작업 공간을 더하거나 최근 폴더를 연결한다
    private var workspaceBar: some View {
        HStack(spacing: 6) {
            Menu {
                let connected = Set(store.workspaces.map(\.url))
                let others = store.recentFolders.filter { !connected.contains($0) }
                if !others.isEmpty {
                    Section("최근 폴더") {
                        ForEach(others, id: \.self) { folder in
                            Button {
                                store.addWorkspace(folder)
                            } label: {
                                Text(folder.lastPathComponent)
                                Text((folder.path as NSString).abbreviatingWithTildeInPath)
                            }
                        }
                    }
                }
                Button("폴더 고르기…") { store.connectWorkspace() }
            } label: {
                Label("작업 공간 추가", systemImage: "plus.rectangle.on.folder")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer(minLength: 0)

            if store.workspaces.count > 1 {
                Text("\(store.workspaces.count)개 연결됨")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
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
                Text("폴더가 옮겨졌거나 지워졌습니다. 다시 연결해 주세요.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("작업 공간 연결…") { store.connectWorkspace() }
                    .padding(.top, 4)
            }
            .padding(40)
        } else if store.workspaces.isEmpty {
            VStack(spacing: 12) {
                Text("노트를 모아둘 폴더를 작업 공간으로 연결하세요")
                    .foregroundStyle(.secondary)
                Text("하위 폴더까지 함께 읽고, 여러 개를 연결할 수 있습니다")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                Button("작업 공간 연결…") { store.connectWorkspace() }
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
                        rootURL: store.workspaceURL(for: store.selectedNoteURL)
                    )
                    .frame(minWidth: 300)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { NoteTabBar(store: store) }
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
