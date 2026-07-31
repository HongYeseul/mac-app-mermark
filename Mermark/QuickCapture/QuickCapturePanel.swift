import AppKit
import SwiftUI

/// 전역 단축키로 띄우는 떠 있는 입력 패널.
/// 메뉴바 팝오버와 같은 화면을 쓰되, 메인 창을 열지 않고 어디서나 뜬다.
@MainActor
final class QuickCapturePanel {
    private var panel: NSPanel?
    private let store: NoteStore

    init(store: NoteStore) {
        self.store = store
    }

    func toggle() {
        if let panel, panel.isVisible {
            close()
        } else {
            show()
        }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 344, height: 220),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "빠른 메모"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(
            rootView: QuickCaptureView(store: store) { [weak self] in self?.close() }
        )
        return panel
    }
}
