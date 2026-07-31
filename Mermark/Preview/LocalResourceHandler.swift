import Foundation
import WebKit
import UniformTypeIdentifiers

/// 프리뷰 HTML은 앱 번들에서 로드되기 때문에 `![](./img.png)` 같은 노트 기준 상대경로가
/// 그대로는 열리지 않는다. 전용 URL 스킴을 만들어 노트 폴더 안의 파일을 직접 서빙한다.
final class LocalResourceHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "mermark-local"
    /// 노트가 든 폴더 기준 상대경로
    static let noteHost = "note"
    /// 노트 폴더 최상위 기준 경로 (마크다운에서 "/"로 시작하는 경우)
    static let folderHost = "folder"

    var noteDirectory: URL?
    var rootDirectory: URL?

    /// 노트 폴더 밖으로 벗어나는 경로는 돌려주지 않는다. `../`로 상위 폴더를 읽는 것을 막는다.
    static func resolve(_ url: URL, noteDirectory: URL?, rootDirectory: URL?) -> URL? {
        guard let rootDirectory else { return nil }

        let base: URL
        switch url.host {
        case folderHost: base = rootDirectory
        case noteHost: base = noteDirectory ?? rootDirectory
        default: return nil
        }

        let relative = String(url.path.drop(while: { $0 == "/" }))
        guard !relative.isEmpty else { return nil }

        // isDirectory: true를 빼면 base의 마지막 경로 요소가 상대경로에 덮여 사라진다
        let baseDirectory = URL(fileURLWithPath: base.path, isDirectory: true)
        let candidate = URL(fileURLWithPath: relative, relativeTo: baseDirectory).standardizedFileURL
        let root = URL(fileURLWithPath: rootDirectory.path, isDirectory: true).standardizedFileURL

        guard isInside(candidate, root) else { return nil }
        // 노트 폴더 안에 있는 심볼릭 링크가 밖을 가리키는 경우까지 막는다.
        // 없는 파일은 심볼릭 링크가 풀리지 않으므로 경로 비교만으로 판단한다.
        let resolved = candidate.resolvingSymlinksInPath()
        guard resolved.path == candidate.path || isInside(resolved, root.resolvingSymlinksInPath()) else {
            return nil
        }
        return candidate
    }

    private static func isInside(_ url: URL, _ root: URL) -> Bool {
        let rootPath = root.path.hasSuffix("/") ? String(root.path.dropLast()) : root.path
        return url.path == rootPath || url.path.hasPrefix(rootPath + "/")
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let fileURL = Self.resolve(url, noteDirectory: noteDirectory, rootDirectory: rootDirectory),
              let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        // 파일이 바뀌었을 때 옛 이미지가 남지 않도록 캐시를 막는다
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mimeType,
                "Content-Length": String(data.count),
                "Cache-Control": "no-store",
            ]
        )!

        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
