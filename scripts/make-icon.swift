#!/usr/bin/env swift
import AppKit

// Mermark 앱 아이콘을 그린다. 이미지 편집기 없이 다시 만들 수 있도록 코드로 둔다.
//
//   swift scripts/make-icon.swift <출력 폴더>
//
// macOS 아이콘 규격에 맞춰 여백을 두고 둥근 사각형 안에 마크를 그린다.
// 마크는 노드 하나에서 둘로 갈라지는 흐름도 — 이 앱이 다루는 것이 다이어그램이라는 표시.

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath)

/// 브랜드 민트. 위에서 아래로 옅은 쪽 → 진한 쪽
let gradientTop = NSColor(srgbRed: 0.353, green: 0.835, blue: 0.761, alpha: 1)     // #5AD5C2
let gradientBottom = NSColor(srgbRed: 0.184, green: 0.647, blue: 0.576, alpha: 1)  // #2FA593

func makeIcon(pixels: Int) -> NSBitmapImageRep {
    let size = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.shouldAntialias = true

    // macOS 아이콘은 캔버스 가장자리에 여백을 두고 둥근 사각형을 그린다
    let margin = size * 0.0977
    let side = size - margin * 2
    let plate = NSRect(x: margin, y: margin, width: side, height: side)
    let plateShape = NSBezierPath(roundedRect: plate, xRadius: side * 0.2237, yRadius: side * 0.2237)

    plateShape.addClip()
    NSGradient(starting: gradientBottom, ending: gradientTop)!
        .draw(in: plate, angle: 90)

    // 마크는 판 안쪽 좌표계로 그린다
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: plate.minX + side * x, y: plate.minY + side * y)
    }
    func node(centerX: CGFloat, centerY: CGFloat, width: CGFloat, height: CGFloat) -> NSBezierPath {
        let rect = NSRect(
            x: plate.minX + side * (centerX - width / 2),
            y: plate.minY + side * (centerY - height / 2),
            width: side * width,
            height: side * height
        )
        return NSBezierPath(roundedRect: rect, xRadius: side * 0.045, yRadius: side * 0.045)
    }

    NSColor.white.setStroke()
    NSColor.white.setFill()

    let line = NSBezierPath()
    line.lineCapStyle = .round
    line.lineJoinStyle = .round

    if pixels <= 32 {
        // 작은 크기에서는 갈래가 뭉개진다. 노드 둘과 이음선 하나로 줄인다.
        // 노드를 세로로 세워야 이음선과 합쳐져 한 덩어리 막대로 보이지 않는다.
        line.lineWidth = side * 0.085
        line.move(to: point(0.385, 0.50))
        line.line(to: point(0.615, 0.50))
        line.stroke()

        node(centerX: 0.265, centerY: 0.50, width: 0.24, height: 0.40).fill()
        node(centerX: 0.735, centerY: 0.50, width: 0.24, height: 0.40).fill()
    } else {
        // 이어지는 선: 왼쪽 노드 → 가운데에서 갈라짐 → 오른쪽 두 노드
        line.lineWidth = side * 0.055
        line.move(to: point(0.40, 0.50))
        line.line(to: point(0.545, 0.50))
        line.move(to: point(0.545, 0.255))
        line.line(to: point(0.545, 0.745))
        line.move(to: point(0.545, 0.745))
        line.line(to: point(0.625, 0.745))
        line.move(to: point(0.545, 0.255))
        line.line(to: point(0.625, 0.255))
        line.stroke()

        // 왼쪽은 문서처럼 조금 넓게, 오른쪽 둘은 같은 크기로
        node(centerX: 0.285, centerY: 0.50, width: 0.24, height: 0.20).fill()
        node(centerX: 0.715, centerY: 0.745, width: 0.19, height: 0.175).fill()
        node(centerX: 0.715, centerY: 0.255, width: 0.19, height: 0.175).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

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
    let data = makeIcon(pixels: entry.pixels).representation(using: .png, properties: [:])!
    try! data.write(to: outputDirectory.appendingPathComponent(entry.name + ".png"))
}
print("아이콘 \(entries.count)개를 \(outputDirectory.path)에 만들었습니다")
