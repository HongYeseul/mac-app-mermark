#!/usr/bin/env swift
import AppKit
import WebKit

// 문서용 이미지를 HTML에서 만든다. 이미지 편집기 없이 다시 만들 수 있도록 코드로 둔다.
//
//   swift scripts/render-html.swift <입력.html> <출력.png> [폭] [배율]
//
// 앱의 Mermaid 내보내기와 같은 방식(오프스크린 WKWebView + takeSnapshot)을 쓴다.

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("사용법: render-html.swift <입력.html> <출력.png> [폭=900] [배율=2]")
    exit(2)
}
let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
let width = arguments.count > 3 ? Double(arguments[3])! : 900
let scale = arguments.count > 4 ? Double(arguments[4])! : 2

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let frame = NSRect(x: 0, y: 0, width: width, height: 1400)
let webView = WKWebView(frame: frame)
let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
window.contentView = webView

final class Renderer: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 레이아웃이 끝난 뒤 실제 내용 높이를 재서 그만큼만 찍는다
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            webView.evaluateJavaScript("document.body.scrollHeight") { value, _ in
                let height = (value as? NSNumber)?.doubleValue ?? 1000
                window.setContentSize(NSSize(width: width, height: height))

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    let config = WKSnapshotConfiguration()
                    config.rect = NSRect(x: 0, y: 0, width: width, height: height)
                    let backing = window.backingScaleFactor > 0 ? window.backingScaleFactor : 1
                    config.snapshotWidth = NSNumber(value: width * scale / backing)

                    webView.takeSnapshot(with: config) { image, error in
                        guard let image,
                              let tiff = image.tiffRepresentation,
                              let rep = NSBitmapImageRep(data: tiff),
                              let png = rep.representation(using: .png, properties: [:]) else {
                            print("실패: \(error?.localizedDescription ?? "스냅샷 없음")")
                            exit(1)
                        }
                        try! png.write(to: outputURL)
                        print("\(outputURL.lastPathComponent) — \(rep.pixelsWide)x\(rep.pixelsHigh)px")
                        exit(0)
                    }
                }
            }
        }
    }
}

let renderer = Renderer()
webView.navigationDelegate = renderer
webView.loadFileURL(inputURL, allowingReadAccessTo: inputURL.deletingLastPathComponent())

DispatchQueue.main.asyncAfter(deadline: .now() + 40) {
    print("실패: 시간 초과")
    exit(2)
}
app.run()
