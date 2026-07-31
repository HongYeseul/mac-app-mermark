import Foundation

/// 마크다운 본문에서 ```mermaid 코드 펜스의 내용만 순서대로 뽑는다. 일괄 내보내기에 쓴다.
enum MermaidBlocks {
    static func extract(from text: String) -> [String] {
        var blocks: [String] = []
        var openingFence: (marker: Character, length: Int)?
        var isMermaid = false
        var current: [String] = []

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if let fence = openingFence {
                // 닫는 펜스는 여는 펜스와 같은 문자로, 그만큼 이상 길어야 한다
                let run = line.prefix(while: { $0 == fence.marker }).count
                let isClosing = run >= fence.length && line.dropFirst(run).isEmpty
                if isClosing {
                    if isMermaid { blocks.append(current.joined(separator: "\n")) }
                    openingFence = nil
                    isMermaid = false
                    current = []
                } else if isMermaid {
                    current.append(rawLine)
                }
                continue
            }

            guard let marker = line.first, marker == "`" || marker == "~" else { continue }
            let run = line.prefix(while: { $0 == marker }).count
            guard run >= 3 else { continue }

            openingFence = (marker, run)
            // 정보 문자열의 첫 단어가 언어. "```mermaid title=x"도 mermaid로 본다.
            let info = line.dropFirst(run).trimmingCharacters(in: .whitespaces)
            isMermaid = info.split(separator: " ").first.map { $0.lowercased() == "mermaid" } ?? false
            current = []
        }

        return blocks.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
