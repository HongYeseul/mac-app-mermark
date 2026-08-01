import SwiftUI
import AppKit

/// 앱의 메인 색상(민트). 로고와 같은 색조를 UI 전반에서 쓴다.
///
/// 한 가지 색을 그대로 쓰지 않고 단계를 나눈다. 파스텔 톤은 넓은 면적(로고)에서 좋지만
/// 흰 배경 위의 글자로 쓰면 대비가 모자라기 때문이다.
/// - 로고·큰 면적: `logoHex`
/// - 글자·아이콘: `accent` (라이트에서 진하게, 다크에서 밝게)
/// - 태그 배경 같은 옅은 면: `tintHex`
///
/// 프리뷰(`Resources/preview.html`)의 CSS도 같은 값을 쓰므로 함께 고쳐야 한다.
enum Brand {
    static let logoHex = "#45C7B6"
    static let tintHex = "#E4F6F2"

    /// 글자·아이콘용. 라이트 #17786B, 다크 #7EDCCC
    static let accentNSColor = NSColor(name: "MermarkAccent") { appearance in
        isDark(appearance)
            ? NSColor(srgbRed: 0.494, green: 0.863, blue: 0.800, alpha: 1)
            : NSColor(srgbRed: 0.090, green: 0.471, blue: 0.420, alpha: 1)
    }

    /// 코드용. 메인 색과 같은 청록 계열이면 헷갈리므로 차분한 슬레이트로 둔다.
    /// 라이트 #6B7A8F, 다크 #9BB0C7
    static let codeNSColor = NSColor(name: "MermarkCode") { appearance in
        isDark(appearance)
            ? NSColor(srgbRed: 0.608, green: 0.690, blue: 0.780, alpha: 1)
            : NSColor(srgbRed: 0.420, green: 0.478, blue: 0.561, alpha: 1)
    }

    static var accent: Color { Color(nsColor: accentNSColor) }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
