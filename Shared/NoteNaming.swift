import Foundation

/// 노트 파일명 규칙. 앱과 CLI가 같은 규칙을 써야 양쪽에서 만든 노트가 어긋나지 않는다.
enum NoteNaming {
    static let untitled = "새 노트"
    private static let maxTitleLength = 50

    /// 첫 줄에서 파일명을 만든다. 마크다운 헤딩 기호와 파일명에 쓸 수 없는 문자를 제거.
    static func fileTitle(from text: String) -> String {
        var title = String(text.prefix(while: { $0 != "\n" })).trimmingCharacters(in: .whitespaces)
        while title.hasPrefix("#") { title.removeFirst() }
        // "/"는 경로 구분자, ":"는 Finder에서 "/"로 표시되므로 둘 다 치환
        title = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        // 앞의 "."을 남기면 숨김 파일이 되어 목록에서 사라진다
        while title.hasPrefix(".") { title.removeFirst() }
        title = title.trimmingCharacters(in: .whitespaces)
        if title.count > maxTitleLength {
            title = String(title.prefix(maxTitleLength)).trimmingCharacters(in: .whitespaces)
        }
        return title.isEmpty ? untitled : title
    }

    /// 같은 제목이 이미 있으면 "제목 2", "제목 3"으로 비켜 간다. (대소문자 무시 파일시스템 고려)
    static func uniqueURL(for title: String, in folder: URL, excluding current: URL? = nil) -> URL {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent(title + ".md")
        var suffix = 2
        while fm.fileExists(atPath: candidate.path),
              candidate.path.lowercased() != current?.path.lowercased() {
            candidate = folder.appendingPathComponent("\(title) \(suffix).md")
            suffix += 1
        }
        return candidate
    }

    /// "제목" 자체이거나 중복 회피로 "제목 2"처럼 숫자만 덧붙은 형태인지
    static func isDerived(_ name: String, from title: String) -> Bool {
        if name == title { return true }
        guard name.hasPrefix(title + " ") else { return false }
        let suffix = name.dropFirst(title.count + 1)
        return !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
    }
}
