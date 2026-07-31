import Foundation

// MermaidBlocks: 일괄 내보내기를 위한 mermaid 펜스 추출 규칙 검증

var failures: [String] = []
var total = 0
func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
    total += 1
    print("\(condition ? "PASS" : "FAIL"): \(name)\(condition ? "" : "  → \(detail())")")
    if !condition { failures.append(name) }
}

func blocks(_ text: String) -> [String] { MermaidBlocks.extract(from: text) }

print("── 기본 추출")
let doc = """
# 문서

첫 문단

```mermaid
flowchart LR
  A --> B
```

중간 문단

```mermaid
sequenceDiagram
  A->>B: 안녕
```

끝
"""
check("블록 2개 추출", blocks(doc).count == 2, "\(blocks(doc).count)")
check("첫 블록 내용 정확", blocks(doc).first == "flowchart LR\n  A --> B", "\(blocks(doc).first ?? "nil")")
check("둘째 블록 내용 정확", blocks(doc).last == "sequenceDiagram\n  A->>B: 안녕", "\(blocks(doc).last ?? "nil")")
check("문서 순서 유지", blocks(doc)[0].hasPrefix("flowchart"))

print("\n── 다른 언어 펜스는 제외")
let mixed = """
```swift
let x = 1
```

```mermaid
flowchart TD
  A --> B
```

```
언어 없는 블록
```

```bash
echo mermaid
```
"""
check("mermaid 블록만 추출", blocks(mixed) == ["flowchart TD\n  A --> B"], "\(blocks(mixed))")

print("\n── 정보 문자열 변형")
check("대문자 표기 허용", blocks("```Mermaid\nflowchart LR\n  A --> B\n```") == ["flowchart LR\n  A --> B"],
      "\(blocks("```Mermaid\nflowchart LR\n  A --> B\n```"))")
check("추가 속성이 붙어도 인식", blocks("```mermaid title=\"흐름도\"\nflowchart LR\n  A --> B\n```").count == 1,
      "\(blocks("```mermaid title=\"흐름도\"\nflowchart LR\n  A --> B\n```"))")
check("mermaidjs 같은 다른 언어는 제외", blocks("```mermaidjs\nflowchart LR\n```").isEmpty,
      "\(blocks("```mermaidjs\nflowchart LR\n```"))")

print("\n── 펜스 문자와 길이")
check("물결 펜스 인식", blocks("~~~mermaid\nflowchart LR\n  A --> B\n~~~") == ["flowchart LR\n  A --> B"],
      "\(blocks("~~~mermaid\nflowchart LR\n  A --> B\n~~~"))")
let longFence = """
````mermaid
flowchart LR
  A --> B
```
아직 안 닫힘
````
"""
check("긴 펜스 안의 짧은 ```는 닫지 않음",
      blocks(longFence) == ["flowchart LR\n  A --> B\n```\n아직 안 닫힘"], "\(blocks(longFence))")
check("여는 문자와 다른 문자로는 안 닫힘",
      blocks("```mermaid\nflowchart LR\n~~~\n  A --> B\n```") == ["flowchart LR\n~~~\n  A --> B"],
      "\(blocks("```mermaid\nflowchart LR\n~~~\n  A --> B\n```"))")

print("\n── 들여쓰기와 공백")
check("들여쓴 펜스도 인식",
      blocks("- 목록\n  ```mermaid\n  flowchart LR\n    A --> B\n  ```").count == 1,
      "\(blocks("- 목록\n  ```mermaid\n  flowchart LR\n    A --> B\n  ```"))")
check("블록 안 들여쓰기는 원본 그대로 보존",
      blocks("```mermaid\n  flowchart LR\n    A --> B\n```") == ["  flowchart LR\n    A --> B"],
      "\(blocks("```mermaid\n  flowchart LR\n    A --> B\n```"))")

print("\n── 비어 있거나 망가진 입력")
check("빈 문서", blocks("").isEmpty)
check("mermaid 없는 문서", blocks("# 제목\n본문만 있음").isEmpty)
check("빈 mermaid 블록은 제외", blocks("```mermaid\n\n```").isEmpty, "\(blocks("```mermaid\n\n```"))")
check("닫히지 않은 블록은 제외", blocks("```mermaid\nflowchart LR\n  A --> B") .isEmpty,
      "\(blocks("```mermaid\nflowchart LR\n  A --> B"))")
check("펜스 표시만 있고 내용 없음", blocks("```mermaid\n```").isEmpty)

print("\n" + (failures.isEmpty ? "ALL PASS (\(total) checks)" : "FAILURES(\(failures.count)/\(total)): \(failures.joined(separator: ", "))"))
exit(failures.isEmpty ? 0 : 1)
