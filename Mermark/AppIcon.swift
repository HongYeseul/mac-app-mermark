import AppKit

/// 앱 아이콘을 코드로 그린다. 테마를 바꾸면 Dock 아이콘도 같은 색으로 다시 그린다.
/// 번들에 넣을 .icns도 이 코드로 만든다 (scripts/make-icon.swift).
enum AppIcon {
    static func image(for theme: Theme, pixels: Int) -> NSImage {
        let rep = bitmap(for: theme, pixels: pixels)
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.addRepresentation(rep)
        return image
    }

    static func bitmap(for theme: Theme, pixels: Int) -> NSBitmapImageRep {
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
        NSBezierPath(roundedRect: plate, xRadius: side * 0.2237, yRadius: side * 0.2237).addClip()
        NSGradient(starting: theme.logoDeep.nsColor, ending: theme.logoLight.nsColor)!
            .draw(in: plate, angle: 90)

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
            // 노드 하나에서 둘로 갈라지는 흐름도
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

            node(centerX: 0.285, centerY: 0.50, width: 0.24, height: 0.20).fill()
            node(centerX: 0.715, centerY: 0.745, width: 0.19, height: 0.175).fill()
            node(centerX: 0.715, centerY: 0.255, width: 0.19, height: 0.175).fill()
        }

        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}
