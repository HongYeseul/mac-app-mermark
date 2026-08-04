import SwiftUI

/// 사이드바의 작업 공간 이름 줄. 누르면 접히고, + 로 그 안에 노트를 만든다.
struct WorkspaceHeader: View {
    @ObservedObject var store: NoteStore
    let workspace: Workspace

    var body: some View {
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
        // 이게 없으면 Spacer 자리는 히트 테스트에서 빠져서
        // 이름 글자 위에서만 우클릭이 먹는다
        .contentShape(Rectangle())
        .contextMenu {
            Button("Finder에서 보기") { store.revealInFinder(workspace.url) }
            Button("경로 복사") { copyPath(workspace.url) }
            Divider()
            Button {
                store.requestDisconnect(workspace)
            } label: {
                Text("작업 공간 연결 해제")
                Text("파일은 지우지 않습니다")
            }
            Button(role: .destructive) {
                store.requestWorkspaceTrash(workspace)
            } label: {
                Text("폴더째 휴지통으로 이동")
                Text("폴더 안 파일이 모두 함께 갑니다")
            }
        }
    }

    private func copyPath(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
    }
}
