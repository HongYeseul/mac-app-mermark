import Foundation

/// 프리뷰에서 체크박스를 눌렀을 때 원본 마크다운의 `- [ ]` ↔ `- [x]`를 뒤집는다.
enum MarkdownTaskList {
    /// 목록 표시 뒤에 오는 대괄호만 인정한다. 본문 중간의 "[x]"는 건드리지 않는다.
    private static let taskMarker = try! NSRegularExpression(
        pattern: "^(\\s*(?:[-*+]|\\d+[.)])\\s+\\[)([ xX])(\\])"
    )

    /// 해당 줄이 할 일 항목이면 뒤집은 전체 텍스트를, 아니면 nil을 돌려준다.
    static func toggle(in text: String, line: Int) -> String? {
        var lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(line) else { return nil }

        let original = lines[line]
        let range = NSRange(location: 0, length: (original as NSString).length)
        guard let match = taskMarker.firstMatch(in: original, range: range) else { return nil }

        let ns = original as NSString
        let current = ns.substring(with: match.range(at: 2))
        let flipped = current == " " ? "x" : " "
        lines[line] = ns.replacingCharacters(in: match.range(at: 2), with: flipped)
        return lines.joined(separator: "\n")
    }

    /// 해당 줄이 할 일 항목인지
    static func isTask(_ line: String) -> Bool {
        taskMarker.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }
}
