import AppKit
import SwiftUI
import Carbon.HIToolbox

@main
struct MermarkApp: App {
    @StateObject private var store = NoteStore()
    @StateObject private var quickCapture = QuickCaptureCoordinator()
    @StateObject private var urlHandler = NoteURLHandler()
    @AppStorage("viewMode") private var mode: ViewMode = .split
    @AppStorage("showsOutline") private var showsOutline = false

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .onAppear {
                    quickCapture.start(store: store)
                    urlHandler.start(store: store)
                }
                .onOpenURL { url in
                    // 앱이 꺼져 있다가 mermark open으로 깨어난 경우.
                    // 이미 떠 있을 때는 NoteURLHandler가 먼저 가로챈다.
                    urlHandler.open(url)
                }
        }

        .commands {
            CommandGroup(replacing: .newItem) {
                Button("새 노트") { store.createNoteChoosingWorkspaceIfNeeded() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("작업 공간 연결…") { store.connectWorkspace() }
                    .keyboardShortcut("o", modifiers: .command)
                Menu("작업 공간을 Finder에서 보기") {
                    ForEach(store.workspaces) { workspace in
                        Button(workspace.name) { store.revealInFinder(workspace.url) }
                    }
                }
                .disabled(store.workspaces.isEmpty)
            }
            CommandGroup(after: .saveItem) {
                Button("모든 다이어그램 내보내기…") { exportAllDiagrams() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(store.selectedNoteURL == nil)
                Button("PDF로 내보내기…") { store.onExportPDF?() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
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

        MenuBarExtra("빠른 메모", systemImage: "square.and.pencil") {
            QuickCaptureView(store: store)
        }
        .menuBarExtraStyle(.window)
    }

    private func exportAllDiagrams() {
        let baseName = store.selectedNoteURL?.deletingPathExtension().lastPathComponent ?? "diagram"
        MermaidExporter.shared.exportAll(
            codes: MermaidBlocks.extract(from: store.currentText),
            baseName: baseName
        )
    }
}

/// `mermark://` 주소를 받는다.
///
/// 앱이 떠 있을 때 SwiftUI에 맡기면(`onOpenURL`이든 `application(_:open:)`이든) 주소가 올 때마다
/// WindowGroup이 창을 새로 연다. 그래서 주소를 실어 나르는 Apple Event를 직접 받아
/// SwiftUI의 창 라우팅을 거치지 않는다.
final class NoteURLHandler: NSObject, ObservableObject {
    private weak var store: NoteStore?

    func start(store: NoteStore) {
        self.store = store
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(event:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func open(_ url: URL) {
        guard let store else { return }
        guard store.openNote(from: url) else {
            // 조용히 넘기면 왜 안 열렸는지 알 수 없다
            NSLog("%@", "열지 않음(연결된 작업 공간 안의 .md만 엽니다): \(url.absoluteString)")
            return
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func handleGetURL(event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: raw) else { return }
        open(url)
    }
}
