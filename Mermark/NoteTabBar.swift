import SwiftUI

/// 열어 둔 노트들을 상단에 탭으로 늘어놓는다.
struct NoteTabBar: View {
    @ObservedObject var store: NoteStore

    private let height: CGFloat = 30

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(store.openTabs, id: \.self) { url in
                        tab(url)
                            .id(url)
                        Divider().frame(height: 14)
                    }
                    newNoteButton
                    Spacer(minLength: 0)
                }
            }
            .onChange(of: store.selectedNoteURL) { _, selected in
                // 탭이 많아 화면 밖에 있으면 보이는 데까지 끌어온다
                guard let selected else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(selected, anchor: .center)
                }
            }
        }
        .frame(height: height)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func tab(_ url: URL) -> some View {
        let isActive = url == store.selectedNoteURL
        return HStack(spacing: 6) {
            Text(url.deletingPathExtension().lastPathComponent)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isActive ? .primary : .secondary)

            Button {
                store.closeTab(url)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("탭 닫기")
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: 200)
        .frame(height: height)
        .background(isActive ? Color(nsColor: .textBackgroundColor) : .clear)
        .overlay(alignment: .top) {
            // 지금 보고 있는 탭을 메인 색상으로 표시한다
            if isActive { Brand.accent.frame(height: 2) }
        }
        .contentShape(Rectangle())
        .onTapGesture { store.select(url) }
        .contextMenu {
            Button("탭 닫기") { store.closeTab(url) }
            Button("이 탭만 남기기") { store.closeOtherTabs(url) }
            Divider()
            Button("Finder에서 보기") { store.revealInFinder(url) }
            Button("휴지통으로 이동") { store.moveToTrash(url) }
        }
    }

    private var newNoteButton: some View {
        Button {
            store.createNoteChoosingWorkspaceIfNeeded()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 28, height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("새 노트 (⌘N)")
    }
}
