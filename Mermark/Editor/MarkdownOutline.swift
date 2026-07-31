import Foundation

struct Heading: Identifiable, Hashable {
    let level: Int
    let text: String
    /// 원본 문서에서의 줄 번호(0-based). 스크롤 이동에 그대로 쓰인다.
    let line: Int

    var id: Int { line }
}

/// 마크다운 본문에서 목차(ATX 헤딩)를 뽑는다.
/// 코드 펜스 안의 `#`은 제목이 아니므로 제외한다. setext 헤딩(밑줄 방식)은 지원하지 않는다.
enum MarkdownOutline {
    static func headings(in text: String) -> [Heading] {
        var headings: [Heading] = []
        var fenceMarker: Character?

        for (index, rawLine) in text.components(separatedBy: "\n").enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if let marker = fenceMarker {
                if line.hasPrefix(String(repeating: marker, count: 3)) { fenceMarker = nil }
                continue
            }
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                fenceMarker = line.first
                continue
            }

            let hashes = line.prefix(while: { $0 == "#" })
            guard (1...6).contains(hashes.count) else { continue }

            let rest = line.dropFirst(hashes.count)
            // CommonMark: "#" 뒤에는 공백이 와야 헤딩이다 ("#태그"는 헤딩이 아님)
            guard rest.isEmpty || rest.hasPrefix(" ") else { continue }

            let title = stripClosingHashes(rest.trimmingCharacters(in: .whitespaces))
            guard !title.isEmpty else { continue }
            headings.append(Heading(level: hashes.count, text: title, line: index))
        }
        return headings
    }

    /// "## 제목 ##"의 닫는 기호만 제거한다. 앞에 공백이 있을 때만 닫는 기호로 본다("C#"은 보존).
    private static func stripClosingHashes(_ title: String) -> String {
        let withoutTrailing = String(title.reversed().drop(while: { $0 == "#" }).reversed())
        guard withoutTrailing.count != title.count else { return title }
        guard withoutTrailing.hasSuffix(" ") else { return title }
        return withoutTrailing.trimmingCharacters(in: .whitespaces)
    }
}
