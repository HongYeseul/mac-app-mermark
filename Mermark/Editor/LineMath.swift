import Foundation

/// 문자 인덱스 ↔ 줄 번호(0-based) 변환. 에디터 ↔ 프리뷰 스크롤 동기화의 공통 단위가 "줄"이다.
enum LineMath {
    static func lineNumber(atCharacterIndex index: Int, in text: String) -> Int {
        let ns = text as NSString
        let end = min(max(index, 0), ns.length)
        var line = 0
        var cursor = 0
        while cursor < end {
            let found = ns.range(of: "\n", options: [], range: NSRange(location: cursor, length: end - cursor))
            if found.location == NSNotFound { break }
            line += 1
            cursor = found.location + 1
        }
        return line
    }

    /// 해당 줄의 첫 문자 인덱스. 마지막 줄을 넘어서면 마지막 줄의 시작을 돌려준다.
    static func characterIndex(ofLine line: Int, in text: String) -> Int {
        let ns = text as NSString
        guard line > 0 else { return 0 }
        var current = 0
        var cursor = 0
        while current < line {
            let found = ns.range(of: "\n", options: [], range: NSRange(location: cursor, length: ns.length - cursor))
            if found.location == NSNotFound { return cursor }
            cursor = found.location + 1
            current += 1
        }
        return cursor
    }
}
