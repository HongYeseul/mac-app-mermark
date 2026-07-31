import SwiftUI

@main
struct MermarkApp: App {
    @StateObject private var store = NoteStore()
    @AppStorage("viewMode") private var mode: ViewMode = .split

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
            CommandMenu("보기") {
                Button("뷰어") { mode = .viewer }
                    .keyboardShortcut("1", modifiers: .command)
                Button("에디터") { mode = .editor }
                    .keyboardShortcut("2", modifiers: .command)
                Button("분할") { mode = .split }
                    .keyboardShortcut("3", modifiers: .command)
            }
        }
    }
}
