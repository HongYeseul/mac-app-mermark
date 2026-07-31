import AppKit
import WebKit

/// 프리뷰 웹뷰가 보여주는 문서를 PDF로 저장한다.
///
/// `WKWebView.printOperation`은 쪽을 나눠 주지만 `run()`이 반환되지 않아 앱이 멈춘다
/// (창을 앞으로 내보내 활성화한 상태에서도 재현). 그래서 `createPDF`를 쓴다.
/// 대신 결과는 쪽을 나누지 않은, 문서 길이만큼 긴 한 장이 된다.
enum PDFExporter {
    static func export(_ webView: WKWebView, to url: URL, completion: @escaping (Error?) -> Void) {
        webView.createPDF(configuration: WKPDFConfiguration()) { result in
            switch result {
            case .success(let data):
                do {
                    try data.write(to: url)
                    completion(nil)
                } catch {
                    completion(error)
                }
            case .failure(let error):
                completion(error)
            }
        }
    }
}
