import AppKit
import WebKit
import PDFKit

/// 프리뷰 웹뷰가 보여주는 문서를 쪽 단위로 나눈 PDF로 저장한다.
///
/// `WKWebView.printOperation`은 쪽을 나눠 주지만 `run()`이 반환되지 않아 앱이 멈춘다
/// (오프스크린 창, 앞으로 내보낸 키 창 모두에서 재현). 그래서 `createPDF`를 쓰되,
/// 한 장짜리 긴 페이지가 되지 않도록 직접 나눈다.
///
/// 1. 본문 블록들의 위쪽 좌표를 받아 "끊어도 되는 지점" 목록을 만든다
/// 2. 한 쪽 높이를 넘지 않는 마지막 블록 경계에서 끊는다 — 글줄이 중간에서 잘리지 않게
/// 3. 조각마다 `createPDF`를 부르고, 고정 크기 쪽 위쪽에 얹어 쪽 높이를 맞춘다
enum PDFExporter {
    /// A4 (72dpi)
    static let paperSize = CGSize(width: 595, height: 842)
    static let margin: CGFloat = 36

    static var contentSize: CGSize {
        CGSize(width: paperSize.width - margin * 2, height: paperSize.height - margin * 2)
    }

    /// 끊을 지점을 고른다. 한 블록이 한 쪽보다 길면 어쩔 수 없이 중간에서 자른다.
    static func pageBreaks(blockTops: [Double], totalHeight: Double, pageHeight: Double) -> [Double] {
        guard totalHeight > 0, pageHeight > 0 else { return [0, max(totalHeight, 1)] }

        var breaks: [Double] = [0]
        var current: Double = 0
        while current + pageHeight < totalHeight {
            let limit = current + pageHeight
            let boundary = blockTops.last { $0 > current + 1 && $0 <= limit }
            current = boundary ?? limit
            breaks.append(current)
        }
        breaks.append(totalHeight)
        return breaks
    }

    static func export(_ webView: WKWebView, to url: URL, completion: @escaping (Error?) -> Void) {
        let measure = """
        const content = document.getElementById("content");
        const tops = content
          ? [...content.children].map(el => el.getBoundingClientRect().top + window.scrollY)
          : [];
        return JSON.stringify({
          tops,
          total: document.body.scrollHeight,
          width: document.documentElement.clientWidth
        });
        """
        webView.callAsyncJavaScript(measure, in: nil, in: .page) { result in
            guard case .success(let value) = result,
                  let json = value as? String,
                  let data = json.data(using: .utf8),
                  let measured = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let blockTops = measured["tops"] as? [Double],
                  let totalHeight = measured["total"] as? Double,
                  let webWidth = measured["width"] as? Double, webWidth > 0 else {
                completion(CocoaError(.fileWriteUnknown))
                return
            }

            // 화면 폭 그대로 잘라낸 뒤 종이 폭에 맞춰 줄인다.
            // 웹뷰를 잠깐 좁혔다 되돌리면 화면이 깜빡이므로 그렇게 하지 않는다.
            let shrink = Double(contentSize.width) / webWidth
            let breaks = pageBreaks(
                blockTops: blockTops,
                totalHeight: totalHeight,
                pageHeight: Double(contentSize.height) / shrink
            )
            renderSlices(webView, breaks: breaks, width: webWidth, index: 0, pages: []) { pages in
                guard !pages.isEmpty else {
                    completion(CocoaError(.fileWriteUnknown))
                    return
                }
                completion(write(pages: pages, scale: shrink, to: url))
            }
        }
    }

    private static func renderSlices(
        _ webView: WKWebView,
        breaks: [Double],
        width: Double,
        index: Int,
        pages: [PDFPage],
        completion: @escaping ([PDFPage]) -> Void
    ) {
        guard index < breaks.count - 1 else {
            completion(pages)
            return
        }
        let configuration = WKPDFConfiguration()
        configuration.rect = CGRect(
            x: 0,
            y: breaks[index],
            width: width,
            height: breaks[index + 1] - breaks[index]
        )
        webView.createPDF(configuration: configuration) { result in
            var collected = pages
            if case .success(let data) = result, let page = PDFDocument(data: data)?.page(at: 0) {
                collected.append(page)
            }
            renderSlices(webView, breaks: breaks, width: width,
                         index: index + 1, pages: collected, completion: completion)
        }
    }

    /// 잘라낸 조각들을 종이 폭에 맞춰 줄여 고정 크기 쪽 위쪽에 얹는다
    private static func write(pages: [PDFPage], scale: Double, to url: URL) -> Error? {
        let output = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: paperSize)
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return CocoaError(.fileWriteUnknown)
        }

        for page in pages {
            guard let pageRef = page.pageRef else { continue }
            let drawnHeight = page.bounds(for: .mediaBox).height * scale
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: margin, y: paperSize.height - margin - drawnHeight)
            context.scaleBy(x: scale, y: scale)
            context.drawPDFPage(pageRef)
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()

        do {
            try output.write(to: url, options: .atomic)
            return nil
        } catch {
            return error
        }
    }
}
