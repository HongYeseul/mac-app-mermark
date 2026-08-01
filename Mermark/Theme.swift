import SwiftUI
import AppKit

/// 앱의 메인 색상. 로고와 UI 강조색을 같은 색조로 묶는다.
///
/// 한 값을 그대로 쓰지 않고 단계를 나눈다. 파스텔 톤은 넓은 면적(로고)에서 좋지만
/// 흰 배경 위의 글자로 쓰면 대비가 모자라기 때문이다.
enum Theme: String, CaseIterable, Identifiable {
    case mint, sage, jade, copper, plum

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mint: "민트"
        case .sage: "세이지"
        case .jade: "제이드"
        case .copper: "코퍼"
        case .plum: "플럼"
        }
    }

    /// 로고·큰 면적
    var logo: RGB {
        switch self {
        case .mint: RGB(0x45C7B6)
        case .sage: RGB(0x7CC49B)
        case .jade: RGB(0x57BFA2)
        case .copper: RGB(0xC98B4B)
        case .plum: RGB(0xC46A97)
        }
    }

    /// 아이콘 그러데이션의 위쪽(밝은 쪽)
    var logoLight: RGB {
        switch self {
        case .mint: RGB(0x5AD5C2)
        case .sage: RGB(0x95D4B0)
        case .jade: RGB(0x6FD0B6)
        case .copper: RGB(0xDCA269)
        case .plum: RGB(0xD787AF)
        }
    }

    /// 아이콘 그러데이션의 아래쪽(진한 쪽)
    var logoDeep: RGB {
        switch self {
        case .mint: RGB(0x2FA593)
        case .sage: RGB(0x5AA87E)
        case .jade: RGB(0x3EA085)
        case .copper: RGB(0xA96E33)
        case .plum: RGB(0xA24E79)
        }
    }

    /// 글자·아이콘 (라이트에서 진하게)
    var accentLight: RGB {
        switch self {
        case .mint: RGB(0x17786B)
        case .sage: RGB(0x2F7D5A)
        case .jade: RGB(0x1E7A62)
        case .copper: RGB(0x8A5320)
        case .plum: RGB(0x8E3A66)
        }
    }

    /// 글자·아이콘 (다크에서 밝게)
    var accentDark: RGB {
        switch self {
        case .mint: RGB(0x7EDCCC)
        case .sage: RGB(0x8FD9B4)
        case .jade: RGB(0x84D9BE)
        case .copper: RGB(0xE7B47F)
        case .plum: RGB(0xE79FC2)
        }
    }

    static let storageKey = "themeName"

    static var current: Theme {
        UserDefaults.standard.string(forKey: storageKey)
            .flatMap(Theme.init(rawValue:)) ?? .mint
    }
}

/// 16진수 색을 다루기 쉽게 담아두는 그릇
struct RGB {
    let red: Double
    let green: Double
    let blue: Double

    init(_ hex: Int) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

    var cssHex: String {
        String(format: "#%02x%02x%02x", Int(red * 255), Int(green * 255), Int(blue * 255))
    }

    func cssRGBA(alpha: Double) -> String {
        String(format: "rgba(%d, %d, %d, %.2f)", Int(red * 255), Int(green * 255), Int(blue * 255), alpha)
    }
}
