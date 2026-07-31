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

    var body: some View {
        NavigationSplitView {
            List(selection: selectionBinding) {
                ForEach(store.notes) { note in
                    Label(note.title, systemImage: "doc.text")
                        .tag(note.url)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            detail
        }
        .navigationTitle(store.folderURL?.lastPathComponent ?? "Mermark")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.createNote()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .help("새 노트 (⌘N)")
                .disabled(store.folderURL == nil)

                Button {
                    store.chooseFolder()
                } label: {
                    Image(systemName: "folder")
                }
                .help("노트 폴더 선택 (⌘O)")

                Picker("보기 모드", selection: $mode) {
                    ForEach(ViewMode.allCases) { mode in
                        Image(systemName: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("뷰어 / 에디터 / 분할")
            }
        }
        .onAppear(perform: connectScrollSync)
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
                    MarkdownPreview(controller: preview, markdown: store.currentText)
                        .frame(minWidth: 300)
                }
            }
        }
    }

    /// 한쪽이 스크롤하면 반대쪽만 따라간다. 되돌아오는 것은 각 컨트롤러의 억제 구간이 막는다.
    private func connectScrollSync() {
        editor.onTextChange = { store.textChanged($0) }
        editor.onScrollToLine = { preview.scroll(toLine: $0) }
        preview.onScrollToLine = { editor.scroll(toLine: $0) }
    }

    private var selectionBinding: Binding<URL?> {
        Binding(
            get: { store.selectedNoteURL },
            set: { store.select($0) }
        )
    }
}
