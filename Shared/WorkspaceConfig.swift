import Foundation

/// 앱과 CLI가 함께 읽고 쓰는 작업 공간 목록.
///
/// 앱의 `UserDefaults`에만 두면 별개 프로세스인 CLI가 `defaults read`에 기대야 해서
/// 캐시 시점에 따라 어긋난다. 사람이 열어봐도 알 수 있는 JSON 파일 하나를 진실의 원천으로 둔다.
enum WorkspaceConfig {
    /// 기본 위치는 `~/.config/mermark`. 검증에서 실제 설정을 건드리지 않도록 바꿔 끼울 수 있다.
    static var directory: URL = {
        if let override = ProcessInfo.processInfo.environment["MERMARK_CONFIG_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mermark", isDirectory: true)
    }()

    static var fileURL: URL { directory.appendingPathComponent("config.json") }

    private struct Stored: Codable {
        var workspaces: [String]
    }

    /// 같은 폴더인데도 값이 달라지지 않게 한 가지 모양으로 맞춘다.
    ///
    /// `URL(fileURLWithPath:)`는 대상이 폴더면 끝에 "/"를 붙이는데
    /// `appendingPathComponent`로 만든 URL에는 그게 없다. `URL`은 문자열로 비교하므로
    /// 같은 폴더가 다른 값이 되어 목록 대조가 조용히 어긋난다.
    static func normalize(_ url: URL) -> URL {
        URL(fileURLWithPath: url.standardizedFileURL.path, isDirectory: false)
    }

    static func load() -> [URL] {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return [] }
        return stored.workspaces.map { normalize(URL(fileURLWithPath: $0)) }
    }

    static func save(_ urls: [URL]) {
        let stored = Stored(workspaces: urls.map(\.standardizedFileURL.path))
        let encoder = JSONEncoder()
        // 손으로 열어 고칠 수 있는 파일이므로 읽기 좋게 쓴다
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(stored) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
