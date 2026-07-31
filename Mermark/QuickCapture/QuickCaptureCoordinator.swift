import AppKit
import Carbon.HIToolbox

/// 전역 단축키(⌘⇧N)를 등록하고 빠른 메모 패널을 띄운다.
@MainActor
final class QuickCaptureCoordinator: ObservableObject {
    /// 단축키를 등록하지 못하면(다른 앱이 이미 쓰는 조합) false로 남는다
    @Published private(set) var isHotKeyRegistered = false

    private var hotKey: GlobalHotKey?
    private var panel: QuickCapturePanel?

    func start(store: NoteStore) {
        guard hotKey == nil else { return }
        let panel = QuickCapturePanel(store: store)
        self.panel = panel

        hotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_N),
            modifiers: UInt32(cmdKey | shiftKey)
        ) { [weak panel] in
            Task { @MainActor in panel?.toggle() }
        }
        isHotKeyRegistered = hotKey != nil
        if !isHotKeyRegistered {
            NSLog("전역 단축키(⌘⇧N) 등록 실패 — 다른 앱이 쓰고 있을 수 있습니다")
        }
    }
}
