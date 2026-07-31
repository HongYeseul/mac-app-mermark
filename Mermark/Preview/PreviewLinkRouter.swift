import Foundation

/// 프리뷰에서 링크를 눌렀을 때 무엇을 할지 정한다.
/// WKNavigationAction과 분리해 두어 규칙만 따로 검증할 수 있다.
enum PreviewLinkRouter {
    enum Action: Equatable {
        /// 노트 폴더 안의 다른 노트 열기 (앵커가 있으면 그 위치로)
        case openNote(URL, anchor: String?)
        /// 기본 앱/브라우저에 넘기기
        case openExternally(URL)
        /// 같은 문서 안의 앵커 이동이므로 웹뷰에 맡긴다
        case allowInPage
        /// 그 밖의 이동은 막는다 (프리뷰 페이지가 다른 문서로 바뀌면 안 된다)
        case block
    }

    static func action(for url: URL, currentPage: URL?, noteDirectory: URL?, rootDirectory: URL?) -> Action {
        switch url.scheme {
        case LocalResourceHandler.scheme:
            guard let target = LocalResourceHandler.resolve(
                url, noteDirectory: noteDirectory, rootDirectory: rootDirectory
            ) else { return .block }

            if target.pathExtension.lowercased() == "md" {
                // fragment는 기본적으로 퍼센트 인코딩된 값이라 getElementById와 맞지 않는다
                return .openNote(target, anchor: url.fragment(percentEncoded: false))
            }
            // 노트 폴더 안의 PDF·이미지 등은 기본 앱에 넘긴다
            return .openExternally(target)

        case "http", "https", "mailto":
            return .openExternally(url)

        default:
            return isSameDocumentAnchor(url, currentPage: currentPage) ? .allowInPage : .block
        }
    }

    private static func isSameDocumentAnchor(_ url: URL, currentPage: URL?) -> Bool {
        guard url.fragment != nil, let currentPage else { return false }
        func withoutFragment(_ url: URL) -> String {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.fragment = nil
            return components?.string ?? url.absoluteString
        }
        return withoutFragment(url) == withoutFragment(currentPage)
    }
}
