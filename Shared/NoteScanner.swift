import Foundation

/// 작업 공간 하나를 하위 폴더까지 훑어 `.md`를 모은다.
/// 앱과 CLI가 같은 목록을 봐야 하므로 한 자리에 둔다.
enum NoteScanner {
    struct Found {
        let url: URL
        let modifiedAt: Date
    }

    static func scan(_ workspace: URL) -> [Found] {
        guard let walker = FileManager.default.enumerator(
            at: workspace,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var found: [Found] = []
        for case let url as URL in walker where url.pathExtension.lowercased() == "md" {
            let standardized = url.standardizedFileURL
            let modifiedAt = (try? standardized.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            found.append(Found(url: standardized, modifiedAt: modifiedAt))
        }
        return found
    }
}
