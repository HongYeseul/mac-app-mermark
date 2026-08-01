import Foundation

/// CLI가 앱에 "이 노트를 열어라"라고 말할 때 쓰는 `mermark://` 주소.
///
/// 앱이 꺼져 있어도 LaunchServices가 대신 띄워 주므로 켜져 있을 때만 되는 IPC보다 낫다.
/// 다만 이 주소는 웹 페이지를 포함해 아무나 던질 수 있으므로, 받는 쪽에서 반드시
/// `resolve(_:workspaces:)`로 연결된 작업 공간 안의 `.md`인지 확인하고 연다.
enum MermarkURL {
    static let scheme = "mermark"

    /// `mermark://open?path=...`
    static func open(_ noteURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: noteURL.standardizedFileURL.path)]
        return components.url
    }

    /// 받은 주소를 실제로 열어도 되는 노트 경로로 바꾼다. 열면 안 되는 것이면 nil.
    static func resolve(_ url: URL, workspaces: [URL]) -> URL? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == "open",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let raw = components.queryItems?.first(where: { $0.name == "path" })?.value,
              !raw.isEmpty
        else { return nil }

        let noteURL = URL(fileURLWithPath: raw).standardizedFileURL
        guard noteURL.pathExtension.lowercased() == "md" else { return nil }
        // 심볼릭 링크로 작업 공간 밖을 가리키는 경로까지 막는다
        let real = noteURL.resolvingSymlinksInPath().path
        let inside = workspaces.contains { workspace in
            real.hasPrefix(workspace.resolvingSymlinksInPath().path + "/")
        }
        guard inside, FileManager.default.fileExists(atPath: noteURL.path) else { return nil }
        return noteURL
    }
}
