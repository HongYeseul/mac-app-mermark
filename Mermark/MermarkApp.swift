import SwiftUI

@main
struct MermarkApp: App {
    @StateObject private var store = NoteStore()
    @AppStorage("viewMode") private var mode: ViewMode = .split
    @AppStorage("showsOutline") private var showsOutline = false

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("새 노트") { store.createNote() }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(store.folderURL == nil)
                Button("노트 폴더 열기…") { store.chooseFolder() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .saveItem) {
                Button("모든 다이어그램 내보내기…") { exportAllDiagrams() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(store.selectedNoteURL == nil)
            }
            CommandMenu("보기") {
                Button("뷰어") { mode = .viewer }
                    .keyboardShortcut("1", modifiers: .command)
                Button("에디터") { mode = .editor }
                    .keyboardShortcut("2", modifiers: .command)
                Button("분할") { mode = .split }
                    .keyboardShortcut("3", modifiers: .command)
                Divider()
                Button(showsOutline ? "목차 숨기기" : "목차 보기") { showsOutline.toggle() }
                    .keyboardShortcut("t", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView()
        }
    }

    private func exportAllDiagrams() {
        let baseName = store.selectedNoteURL?.deletingPathExtension().lastPathComponent ?? "diagram"
        MermaidExporter.shared.exportAll(
            codes: MermaidBlocks.extract(from: store.currentText),
            baseName: baseName
        )
    }
}
