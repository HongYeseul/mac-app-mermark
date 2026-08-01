import AppKit

// 번들에 넣을 .icns용 PNG를 만든다. 그리는 코드는 앱과 공유한다(Mermark/AppIcon.swift).
//
//   swiftc -o /tmp/make-icon Mermark/Theme.swift Mermark/AppIcon.swift scripts/make-icon.swift
//   /tmp/make-icon <출력 폴더> [테마이름]
//   iconutil -c icns <출력 폴더> -o Mermark/Resources/Mermark.icns

let arguments = CommandLine.arguments
let outputDirectory = URL(fileURLWithPath: arguments.count > 1
    ? arguments[1]
    : FileManager.default.currentDirectoryPath)
let theme = (arguments.count > 2 ? Theme(rawValue: arguments[2]) : nil) ?? .mint

// .icns로 묶으려면 iconset이 요구하는 이름과 크기를 맞춰야 한다
let entries: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
for entry in entries {
    let data = AppIcon.bitmap(for: theme, pixels: entry.pixels)
        .representation(using: .png, properties: [:])!
    try! data.write(to: outputDirectory.appendingPathComponent(entry.name + ".png"))
}
print("\(theme.label) 아이콘 \(entries.count)개를 \(outputDirectory.path)에 만들었습니다")
