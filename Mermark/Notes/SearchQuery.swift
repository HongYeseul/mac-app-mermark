import Foundation

/// 검색창 한 줄에서 태그 조건과 글자 검색을 갈라낸다.
///
/// `#정산 회의` 처럼 섞어 쓸 수 있다. 태그를 사이드바에 따로 늘어놓지 않고
/// 검색창 하나로 모으기 위한 규칙이다.
struct SearchQuery: Equatable {
    /// `#`을 뗀 태그 이름들. 모두 만족해야 한다(AND).
    let tags: [String]
    /// 태그를 뺀 나머지 글자
    let text: String

    var isEmpty: Bool { tags.isEmpty && text.isEmpty }

    static func parse(_ raw: String) -> SearchQuery {
        var tags: [String] = []
        var words: [String] = []

        for token in raw.split(whereSeparator: \.isWhitespace) {
            if token.hasPrefix("#"), token.count > 1 {
                let name = String(token.dropFirst())
                // 대소문자만 다른 중복은 한 번만
                if !tags.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                    tags.append(name)
                }
            } else {
                words.append(String(token))
            }
        }
        return SearchQuery(tags: tags, text: words.joined(separator: " "))
    }

    /// 태그를 검색어에 넣거나 빼서 만든 새 검색어. 프리뷰나 목록에서 태그를 누를 때 쓴다.
    static func toggling(_ tag: String, in raw: String) -> String {
        let query = parse(raw)
        let already = query.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }

        var tokens = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        tokens.removeAll { $0.hasPrefix("#") && $0.dropFirst().caseInsensitiveCompare(tag) == .orderedSame }
        if !already { tokens.insert("#" + tag, at: 0) }
        return tokens.joined(separator: " ")
    }
}
