import SwiftUI

/// 메뉴바 팝오버와 전역 단축키 패널이 함께 쓰는 입력 화면
struct QuickCaptureView: View {
    @ObservedObject var store: NoteStore
    /// 저장했거나 취소했을 때 (패널을 닫는 데 쓴다)
    var onFinish: () -> Void = {}

    @State private var text = ""
    @State private var savedName: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("빠른 메모")
                .font(.headline)

            TextEditor(text: $text)
                .font(.body)
                .frame(width: 320, height: 120)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("여기에 바로 입력하세요")
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 5)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
                .focused($isFocused)

            if let savedName {
                Text("\(savedName) 으로 저장했습니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if store.workspaces.isEmpty {
                Text("먼저 작업 공간을 연결하세요")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Text("⌘⏎ 저장 · esc 닫기")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("저장") { save() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || store.workspaces.isEmpty)
            }
        }
        .padding(12)
        .onAppear { isFocused = true }
        .onExitCommand { onFinish() }
    }

    private func save() {
        guard let url = store.quickCapture(text) else { return }
        savedName = url.lastPathComponent
        text = ""
        onFinish()
    }
}
