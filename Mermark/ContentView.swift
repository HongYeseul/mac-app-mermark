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

    /// 지금 보고 있는 노트가 속한 작업 공간. 보던 노트가 없으면 하나만 연결됐을 때만 그것.
    private var currentWorkspace: Workspace? {
        if let owner = store.workspaceURL(for: store.selectedNoteURL) {
            return store.workspaces.first { $0.url == owner }
        }
        return store.workspaces.count == 1 ? store.workspaces[0] : nil
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
                        WorkspaceHeader(store: store, workspace: workspace)
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
        // 앱 이름은 어차피 Dock과 메뉴 막대에 있다. 제목 자리에는
        // 지금 보고 있는 노트가 어느 작업 공간 것인지만 둔다.
        .navigationTitle(currentWorkspace?.name ?? "")
        .navigationSubtitle(currentWorkspace?.displayPath ?? "")
        // 선택 강조·세그먼트 등 시스템 컨트롤까지 메인 색상을 따르게 한다
        .tint(Brand.accent)
        .alert("폴더째 휴지통으로 옮길까요?", isPresented: workspaceTrashConfirmation) {
            Button("휴지통으로 이동", role: .destructive) { store.confirmWorkspaceTrash() }
            Button("취소", role: .cancel) { store.cancelWorkspaceTrash() }
        } message: {
            if let workspace = store.workspaceAwaitingTrash {
                Text("\(workspace.name)\n\(workspace.displayPath)\n\n노트 \(store.noteCount(in: workspace))개를 포함해 폴더 안의 모든 파일이 함께 갑니다. Finder 휴지통에서 되돌릴 수 있습니다.")
            }
        }
        .alert("작업 공간 연결을 해제할까요?", isPresented: disconnectConfirmation) {
            Button("연결 해제", role: .destructive) { store.confirmDisconnect() }
            Button("취소", role: .cancel) { store.cancelDisconnect() }
        } message: {
            if let workspace = store.workspaceAwaitingDisconnect {
                Text("\(workspace.name)\n\(workspace.displayPath)\n\n목록에서만 빠지고 폴더와 파일은 그대로 남습니다.")
            }
        }
        .alert("휴지통으로 옮길까요?", isPresented: trashConfirmation) {
            Button("휴지통으로 이동", role: .destructive) { store.confirmTrash() }
            Button("취소", role: .cancel) { store.cancelTrash() }
        } message: {
            if let url = store.noteAwaitingTrash {
                Text("노트: \(url.deletingPathExtension().lastPathComponent)\nFinder 휴지통에서 되돌릴 수 있습니다.")
            }
        }
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
            Divider()
            Button("휴지통으로 이동") { store.requestTrash(note.url) }
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
        if store.workspaces.isEmpty, !store.missingWorkspacePaths.isEmpty {
            // 쓸 수 있는 작업 공간이 하나도 없을 때만 화면을 차지한다.
            // 다른 공간이 멀쩡한데도 가로막으면 멀쩡한 노트까지 못 본다.
            VStack(spacing: 10) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text("작업 공간을 찾을 수 없습니다")
                    .font(.headline)
                ForEach(store.missingWorkspacePaths, id: \.self) { path in
                    Text((path as NSString).abbreviatingWithTildeInPath)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .frame(maxWidth: 420)
                }
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
            // safeAreaInset이 아니라 VStack이어야 한다. safeAreaInset은 자식의 프레임을
            // 줄이지 않고 안전 영역만 알려주는데, NSViewRepresentable로 감싼 NSScrollView와
            // WKWebView는 그걸 무시하고 프레임 전체를 써서 본문이 탭 줄 밑으로 들어간다.
            VStack(spacing: 0) {
                missingWorkspaceNotice
                NoteTabBar(store: store)
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
            }
        }
    }

    /// 못 읽는 작업 공간이 있어도 나머지는 그대로 쓸 수 있어야 한다.
    /// 화면을 가로막지 않고 위에 한 줄로만 알린다.
    @ViewBuilder
    private var missingWorkspaceNotice: some View {
        ForEach(store.missingWorkspacePaths, id: \.self) { path in
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("작업 공간을 찾을 수 없습니다: \((path as NSString).abbreviatingWithTildeInPath)")
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Button("다시 연결…") { store.connectWorkspace() }
                Button("목록에서 지우기") { store.forgetMissingWorkspace(path) }
            }
            .buttonStyle(.link)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.yellow.opacity(0.12))
            .overlay(alignment: .bottom) { Divider() }
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

    private var workspaceTrashConfirmation: Binding<Bool> {
        Binding(
            get: { store.workspaceAwaitingTrash != nil },
            set: { shown in if !shown { store.cancelWorkspaceTrash() } }
        )
    }

    private var disconnectConfirmation: Binding<Bool> {
        Binding(
            get: { store.workspaceAwaitingDisconnect != nil },
            set: { shown in if !shown { store.cancelDisconnect() } }
        )
    }

    private var trashConfirmation: Binding<Bool> {
        Binding(
            get: { store.noteAwaitingTrash != nil },
            set: { shown in if !shown { store.cancelTrash() } }
        )
    }

    private var selectionBinding: Binding<URL?> {
        Binding(
            get: { store.selectedNoteURL },
            set: { store.select($0) }
        )
    }
}
