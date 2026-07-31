import Foundation

enum ExportTheme: String, CaseIterable, Identifiable {
    case light, dark, system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: "라이트"
        case .dark: "다크"
        case .system: "시스템 설정 따름"
        }
    }

    /// mermaid에 넘길 테마 이름
    func mermaidTheme(systemIsDark: Bool) -> String {
        switch self {
        case .light: "default"
        case .dark: "dark"
        case .system: systemIsDark ? "dark" : "default"
        }
    }
}

enum ExportBackground: String, CaseIterable, Identifiable {
    case transparent, white, theme

    var id: String { rawValue }

    var label: String {
        switch self {
        case .transparent: "투명"
        case .white: "흰색"
        case .theme: "테마에 맞춤"
        }
    }

    /// 내보내기 페이지에 적용할 CSS 배경값
    func cssValue(isDarkTheme: Bool) -> String {
        switch self {
        case .transparent: "transparent"
        case .white: "#ffffff"
        case .theme: isDarkTheme ? "#1e1e1e" : "#ffffff"
        }
    }
}

/// 설정 창에서 고른 내보내기 옵션. 저장은 UserDefaults(@AppStorage와 같은 키)를 쓴다.
struct ExportOptions {
    var scale: Int
    var theme: ExportTheme
    var background: ExportBackground

    static let scaleKey = "exportScale"
    static let themeKey = "exportTheme"
    static let backgroundKey = "exportBackground"

    static var current: ExportOptions {
        let defaults = UserDefaults.standard
        let scale = defaults.object(forKey: scaleKey) as? Int ?? 2
        let theme = (defaults.string(forKey: themeKey)).flatMap(ExportTheme.init(rawValue:)) ?? .light
        let background = (defaults.string(forKey: backgroundKey)).flatMap(ExportBackground.init(rawValue:)) ?? .transparent
        return ExportOptions(scale: min(max(scale, 1), 3), theme: theme, background: background)
    }
}
