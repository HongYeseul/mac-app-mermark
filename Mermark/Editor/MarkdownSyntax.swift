import Foundation

/// 에디터에 색을 입히기 위해 마크다운 문법 요소의 범위를 찾는다.
/// NSTextStorage에 그대로 쓰도록 범위는 UTF-16 기준(NSRange)이다.
enum MarkdownSyntax {
    struct Token: Equatable {
        enum Kind: Equatable {
            case heading(level: Int)
            case codeBlock
            case inlineCode
            case strong
            case emphasis
            case linkText
            case linkURL
            case blockquote
            case listMarker
            case thematicBreak
            case tag
        }

        let kind: Kind
        let range: NSRange
    }

    // 줄 단위로만 매칭한다. 여러 줄에 걸친 강조는 마크다운에서도 드물고 오탐이 크다.
    private static let inlineCode = try! NSRegularExpression(pattern: "`[^`\\n]+`")
    private static let link = try! NSRegularExpression(pattern: "\\[[^\\]\\n]*\\]\\([^)\\n]*\\)")
    private static let strong = try! NSRegularExpression(pattern: "(\\*\\*[^*\\n]+\\*\\*)|(__[^_\\n]+__)")
    private static let emphasis = try! NSRegularExpression(pattern: "(\\*[^*\\n]+\\*)|(_[^_\\n]+_)")
    private static let heading = try! NSRegularExpression(pattern: "^ {0,3}#{1,6}(\\s|$)")
    private static let blockquote = try! NSRegularExpression(pattern: "^\\s*>")
    private static let listMarker = try! NSRegularExpression(pattern: "^\\s*([-*+]|\\d+[.)])(?=\\s)")
    private static let thematicBreak = try! NSRegularExpression(pattern: "^\\s*([-*_])\\s*(\\1\\s*){2,}$")

    static func tokens(in text: String) -> [Token] {
        let ns = text as NSString
        var tokens: [Token] = []
        var fenceMarker: Character?
        var fenceLength = 0
        var blockStart = 0

        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines]) {
            line, lineRange, _, _ in
            guard let line else { return }
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 코드 펜스 안에서는 인라인 문법을 해석하지 않는다
            if let marker = fenceMarker {
                let run = trimmed.prefix(while: { $0 == marker }).count
                if run >= fenceLength && trimmed.dropFirst(run).isEmpty {
                    fenceMarker = nil
                    tokens.append(Token(
                        kind: .codeBlock,
                        range: NSRange(location: blockStart, length: NSMaxRange(lineRange) - blockStart)
                    ))
                }
                return
            }
            if let marker = trimmed.first, marker == "`" || marker == "~" {
                let run = trimmed.prefix(while: { $0 == marker }).count
                if run >= 3 {
                    fenceMarker = marker
                    fenceLength = run
                    blockStart = lineRange.location
                    return
                }
            }

            appendLineTokens(line: line, lineRange: lineRange, into: &tokens)
        }

        // 닫히지 않은 펜스는 문서 끝까지 코드로 본다
        if fenceMarker != nil, blockStart < ns.length {
            tokens.append(Token(kind: .codeBlock, range: NSRange(location: blockStart, length: ns.length - blockStart)))
        }
        return tokens
    }

    private static func appendLineTokens(line: String, lineRange: NSRange, into tokens: inout [Token]) {
        let lineNS = line as NSString
        let whole = NSRange(location: 0, length: lineNS.length)

        func shift(_ range: NSRange) -> NSRange {
            NSRange(location: lineRange.location + range.location, length: range.length)
        }

        if thematicBreak.firstMatch(in: line, range: whole) != nil {
            tokens.append(Token(kind: .thematicBreak, range: lineRange))
            return
        }
        if heading.firstMatch(in: line, range: whole) != nil {
            tokens.append(Token(kind: .heading(level: headingLevel(line)), range: lineRange))
            return
        }
        if blockquote.firstMatch(in: line, range: whole) != nil {
            tokens.append(Token(kind: .blockquote, range: lineRange))
            return
        }
        if let match = listMarker.firstMatch(in: line, range: whole) {
            // 들여쓰기를 뺀 표시 문자만 (캡처 그룹 1)
            tokens.append(Token(kind: .listMarker, range: shift(match.range(at: 1))))
        }

        // 우선순위: 인라인 코드 > 링크 > 굵게 > 기울임. 이미 잡힌 범위와 겹치면 건너뛴다.
        var claimed: [NSRange] = []
        func claim(_ range: NSRange) -> Bool {
            guard !claimed.contains(where: { NSIntersectionRange($0, range).length > 0 }) else { return false }
            claimed.append(range)
            return true
        }

        for match in inlineCode.matches(in: line, range: whole) where claim(match.range) {
            tokens.append(Token(kind: .inlineCode, range: shift(match.range)))
        }
        for match in link.matches(in: line, range: whole) where claim(match.range) {
            // "[텍스트]"와 "(주소)"를 나눠 색을 달리한다.
            // 오프셋은 NSString 기준으로 구해야 한글·이모지에서 어긋나지 않는다.
            let text = lineNS.substring(with: match.range) as NSString
            let split = text.range(of: "](")
            guard split.location != NSNotFound else { continue }
            let textLength = split.location + 1
            tokens.append(Token(kind: .linkText,
                                range: shift(NSRange(location: match.range.location, length: textLength))))
            tokens.append(Token(kind: .linkURL,
                                range: shift(NSRange(location: match.range.location + textLength,
                                                     length: match.range.length - textLength))))
        }
        for match in strong.matches(in: line, range: whole) where claim(match.range) {
            tokens.append(Token(kind: .strong, range: shift(match.range)))
        }
        for match in emphasis.matches(in: line, range: whole) where claim(match.range) {
            tokens.append(Token(kind: .emphasis, range: shift(match.range)))
        }
        for range in MarkdownTags.ranges(in: line) where claim(range) {
            tokens.append(Token(kind: .tag, range: shift(range)))
        }
    }

    private static func headingLevel(_ line: String) -> Int {
        line.trimmingCharacters(in: .whitespaces).prefix(while: { $0 == "#" }).count
    }
}
