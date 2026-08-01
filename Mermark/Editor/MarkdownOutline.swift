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
    private static let listMarker = try! NSRegularExpression(pattern: "^([-*+]|\\d+[.)])\\s")

    static func headings(in text: String) -> [Heading] {
        var headings: [Heading] = []
        var fenceMarker: Character?
        let lines = text.components(separatedBy: "\n")

        /// 바로 윗줄이 밑줄(setext) 제목의 본문이 될 수 있는 줄이면 담아둔다
        var underlineCandidate: (text: String, line: Int)?

        for index in frontmatterEnd(lines)..<lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)

            if let marker = fenceMarker {
                if line.hasPrefix(String(repeating: marker, count: 3)) { fenceMarker = nil }
                underlineCandidate = nil
                continue
            }
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                fenceMarker = line.first
                underlineCandidate = nil
                continue
            }

            let hashes = line.prefix(while: { $0 == "#" })
            if (1...6).contains(hashes.count) {
                let rest = line.dropFirst(hashes.count)
                // CommonMark: "#" 뒤에는 공백이 와야 헤딩이다 ("#태그"는 헤딩이 아님)
                if rest.isEmpty || rest.hasPrefix(" ") {
                    let title = stripClosingHashes(rest.trimmingCharacters(in: .whitespaces))
                    if !title.isEmpty {
                        headings.append(Heading(level: hashes.count, text: title, line: index))
                    }
                    underlineCandidate = nil
                    continue
                }
            }

            // 밑줄 방식: 윗줄이 본문이고 이 줄이 === 또는 --- 이면 제목이다.
            // 줄 번호는 밑줄이 아니라 글자가 있는 윗줄을 가리켜야 눌렀을 때 제자리로 간다.
            if let candidate = underlineCandidate, let marker = underlineMarker(line) {
                headings.append(Heading(
                    level: marker == "=" ? 1 : 2,
                    text: candidate.text,
                    line: candidate.line
                ))
                underlineCandidate = nil
                continue
            }

            underlineCandidate = canPrecedeUnderline(line) ? (line, index) : nil
        }
        return headings
    }

    /// 문서 맨 앞의 `---` 블록(프론트매터) 다음 줄. 안쪽 내용이 밑줄 제목으로 잡히면 안 된다.
    private static func frontmatterEnd(_ lines: [String]) -> Int {
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return 0 }
        for index in 1..<lines.count where lines[index].trimmingCharacters(in: .whitespaces) == "---" {
            return index + 1
        }
        return 0
    }

    /// `===` 또는 `---`처럼 한 종류로만 이뤄진 줄이면 그 문자를 돌려준다
    private static func underlineMarker(_ line: String) -> Character? {
        guard let first = line.first, first == "=" || first == "-" else { return nil }
        return line.allSatisfy { $0 == first } ? first : nil
    }

    /// 밑줄 위에 올 수 있는 보통 본문 줄인지. 목록·인용·표·빈 줄은 제외한다.
    private static func canPrecedeUnderline(_ line: String) -> Bool {
        guard !line.isEmpty, !line.hasPrefix(">"), !line.hasPrefix("|") else { return false }
        guard underlineMarker(line) == nil else { return false }
        let range = NSRange(location: 0, length: (line as NSString).length)
        return listMarker.firstMatch(in: line, range: range) == nil
    }

    /// "## 제목 ##"의 닫는 기호만 제거한다. 앞에 공백이 있을 때만 닫는 기호로 본다("C#"은 보존).
    private static func stripClosingHashes(_ title: String) -> String {
        let withoutTrailing = String(title.reversed().drop(while: { $0 == "#" }).reversed())
        guard withoutTrailing.count != title.count else { return title }
        guard withoutTrailing.hasSuffix(" ") else { return title }
        return withoutTrailing.trimmingCharacters(in: .whitespaces)
    }
}
