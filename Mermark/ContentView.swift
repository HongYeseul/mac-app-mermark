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
                    }
                }
            }
            .searchable(text: $store.searchQuery, placement: .sidebar, prompt: "제목·본문 검색")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
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
        .inspector(isPresented: $showsOutline) {
            outline
                .inspectorColumnWidth(min: 180, ideal: 240, max: 360)
        }
        .onAppear(perform: connectScrollSync)
    }

    /// 누르면 그 태그만 보고, 다시 누르면 전체로 돌아간다
    private func tagRow(_ tag: (name: String, count: Int)) -> some View {
        let isSelected = store.selectedTag?.caseInsensitiveCompare(tag.name) == .orderedSame
        return Button {
            store.toggleTag(tag.name)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "tag.fill" : "tag")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(tag.name)
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
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
        if store.folderURL == nil {
            VStack(spacing: 12) {
                Text("마크다운 노트 노트 폴더를 선택하세요")
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
