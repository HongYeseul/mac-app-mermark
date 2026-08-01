import Foundation

/// 노트에서 태그를 모은다. 본문의 `#태그`와 프론트매터의 `tags:` 항목 둘 다 인식한다.
enum MarkdownTags {
    /// 앞이 줄머리나 공백이어야 한다. 주소의 `#섹션`이나 헤딩의 `# 제목`을 태그로 잡지 않기 위함.
    private static let inlineTag = try! NSRegularExpression(
        pattern: "(^|\\s)#([\\p{L}\\p{N}_][\\p{L}\\p{N}_/-]*)"
    )
    private static let inlineCode = try! NSRegularExpression(pattern: "`[^`\\n]+`")

    static func tags(in text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        var found: [String] = []
        var seen = Set<String>()

        func add(_ raw: String) {
            let tag = raw
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !tag.isEmpty, seen.insert(tag.lowercased()).inserted else { return }
            found.append(tag)
        }

        var bodyStart = 0
        if let closing = frontmatterClosingLine(lines) {
            collectFrontmatterTags(lines[1..<closing], add: add)
            bodyStart = closing + 1
        }
        collectInlineTags(lines[bodyStart...], add: add)
        return found
    }

    /// 문서 맨 앞의 `---` 블록이 닫히는 줄
    private static func frontmatterClosingLine(_ lines: [String]) -> Int? {
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        for index in 1..<lines.count where lines[index].trimmingCharacters(in: .whitespaces) == "---" {
            return index
        }
        return nil
    }

    private static func collectFrontmatterTags(_ lines: ArraySlice<String>, add: (String) -> Void) {
        var insideTagList = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if insideTagList, trimmed.hasPrefix("-") {
                add(String(trimmed.dropFirst()))
                continue
            }
            insideTagList = false

            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = trimmed[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard key == "tags" || key == "tag" else { continue }

            let value = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.isEmpty {
                insideTagList = true       // 다음 줄부터 "- 항목" 목록
                continue
            }
            for part in value.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).split(separator: ",") {
                add(String(part))
            }
        }
    }

    private static func collectInlineTags(_ lines: ArraySlice<String>, add: (String) -> Void) {
        var fenceMarker: Character?
        var fenceLength = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = fenceMarker {
                let run = trimmed.prefix(while: { $0 == marker }).count
                if run >= fenceLength, trimmed.dropFirst(run).isEmpty { fenceMarker = nil }
                continue
            }
            if let marker = trimmed.first, marker == "`" || marker == "~" {
                let run = trimmed.prefix(while: { $0 == marker }).count
                if run >= 3 {
                    fenceMarker = marker
                    fenceLength = run
                    continue
                }
            }
            for name in names(in: line) { add(name) }
        }
    }

    /// 한 줄에서 태그 이름만 뽑는다. 인라인 코드 안은 건너뛴다.
    static func names(in line: String) -> [String] {
        let ns = line as NSString
        let whole = NSRange(location: 0, length: ns.length)
        let codeRanges = inlineCode.matches(in: line, range: whole).map(\.range)

        return inlineTag.matches(in: line, range: whole).compactMap { match in
            let nameRange = match.range(at: 2)
            guard !codeRanges.contains(where: { NSIntersectionRange($0, nameRange).length > 0 }) else { return nil }
            return ns.substring(with: nameRange)
        }
    }

    /// 에디터 강조용: `#`을 포함한 전체 범위
    static func ranges(in line: String) -> [NSRange] {
        let ns = line as NSString
        let whole = NSRange(location: 0, length: ns.length)
        let codeRanges = inlineCode.matches(in: line, range: whole).map(\.range)

        return inlineTag.matches(in: line, range: whole).compactMap { match in
            let nameRange = match.range(at: 2)
            guard !codeRanges.contains(where: { NSIntersectionRange($0, nameRange).length > 0 }) else { return nil }
            // 앞의 "#"까지 포함
            return NSRange(location: nameRange.location - 1, length: nameRange.length + 1)
        }
    }
}
