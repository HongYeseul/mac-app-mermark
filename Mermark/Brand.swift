import SwiftUI
import AppKit

/// 지금 고른 테마의 색을 앱 곳곳에 나눠주는 곳.
///
/// 색 값 자체는 `Theme`에, 프리뷰(웹뷰)로 넘길 CSS는 `previewCSS`에 있다.
/// 프리뷰 CSS를 여기서 만들어 주입하므로 Swift와 HTML에 같은 값이 두 벌 생기지 않는다.
enum Brand {
    /// 테마가 바뀌면 올라간다. 화면들이 이 값을 보고 다시 그린다.
    static let didChange = Notification.Name("MermarkBrandDidChange")

    static var theme: Theme { Theme.current }

    static func select(_ theme: Theme) {
        UserDefaults.standard.set(theme.rawValue, forKey: Theme.storageKey)
        applyDockIcon()
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// 글자·아이콘용. 라이트에서 진하게, 다크에서 밝게.
    static var accentNSColor: NSColor {
        let theme = self.theme
        return NSColor(name: nil) { appearance in
            isDark(appearance) ? theme.accentDark.nsColor : theme.accentLight.nsColor
        }
    }

    /// 코드용. 메인 색과 같은 계열이면 헷갈리므로 차분한 슬레이트로 둔다.
    static let codeNSColor = NSColor(name: "MermarkCode") { appearance in
        isDark(appearance)
            ? NSColor(srgbRed: 0.608, green: 0.690, blue: 0.780, alpha: 1)
            : NSColor(srgbRed: 0.420, green: 0.478, blue: 0.561, alpha: 1)
    }

    static var accent: Color { Color(nsColor: accentNSColor) }

    /// 실행 중에 Dock 아이콘을 다시 그린다.
    /// 번들 안의 .icns(= Finder에 보이는 아이콘)는 그대로다.
    static func applyDockIcon() {
        NSApp?.applicationIconImage = AppIcon.image(for: theme, pixels: 512)
    }

    /// 프리뷰에 넣을 CSS 변수. 웹뷰는 Swift 상수를 못 쓰므로 값을 만들어 넘긴다.
    static func previewCSS(for theme: Theme = Theme.current) -> String {
        """
        :root {
          --brand-logo: \(theme.logo.cssHex);
          --brand-accent: \(theme.accentLight.cssHex);
          --brand-tint: \(theme.logo.cssRGBA(alpha: 0.16));
          --brand-tint-strong: \(theme.logo.cssRGBA(alpha: 0.30));
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --brand-accent: \(theme.accentDark.cssHex);
            --brand-tint: \(theme.accentDark.cssRGBA(alpha: 0.22));
            --brand-tint-strong: \(theme.accentDark.cssRGBA(alpha: 0.34));
          }
        }
        """
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
