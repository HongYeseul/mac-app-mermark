import Foundation

// MarkdownOutline: 본문에서 목차를 뽑는 규칙 검증

var failures: [String] = []
var total = 0
func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
    total += 1
    print("\(condition ? "PASS" : "FAIL"): \(name)\(condition ? "" : "  → \(detail())")")
    if !condition { failures.append(name) }
}

func titles(_ text: String) -> [String] { MarkdownOutline.headings(in: text).map(\.text) }
func levels(_ text: String) -> [Int] { MarkdownOutline.headings(in: text).map(\.level) }
func lines(_ text: String) -> [Int] { MarkdownOutline.headings(in: text).map(\.line) }

print("── 기본 ATX 헤딩")
let basic = """
# 문서 제목
본문 한 줄
## 섹션 1
### 하위 항목
본문
###### 6단계
####### 7단계는 헤딩 아님
"""
check("헤딩 텍스트 추출", titles(basic) == ["문서 제목", "섹션 1", "하위 항목", "6단계"], "\(titles(basic))")
check("레벨 인식", levels(basic) == [1, 2, 3, 6], "\(levels(basic))")
check("줄 번호 정확", lines(basic) == [0, 2, 3, 5], "\(lines(basic))")

print("\n── 헤딩이 아닌 것 걸러내기")
check("# 뒤 공백 없으면 헤딩 아님", titles("#태그입니다\n본문").isEmpty, "\(titles("#태그입니다"))")
check("빈 헤딩 제외", titles("#\n##   \n본문").isEmpty, "\(titles("#\n##   "))")
check("본문 중 # 문자는 무시", titles("코드에서 C# 이야기\n값은 #1 입니다").isEmpty)

print("\n── 코드 펜스 안의 # 제외")
let fenced = """
# 진짜 제목
```bash
# 이건 셸 주석이지 헤딩이 아님
echo hi
```
## 진짜 섹션 2
~~~python
# 파이썬 주석
~~~
### 진짜 섹션 3
"""
check("백틱 펜스 안의 # 제외", !titles(fenced).contains("이건 셸 주석이지 헤딩이 아님"), "\(titles(fenced))")
check("물결 펜스 안의 # 제외", !titles(fenced).contains("파이썬 주석"), "\(titles(fenced))")
check("펜스 밖 헤딩은 모두 인식", titles(fenced) == ["진짜 제목", "진짜 섹션 2", "진짜 섹션 3"], "\(titles(fenced))")
check("펜스 이후 줄 번호 유지", lines(fenced) == [0, 5, 9], "\(lines(fenced))")

let mermaidDoc = """
# 다이어그램 문서
```mermaid
flowchart LR
  A[시작] --> B[끝]
```
## 다음 섹션
"""
check("mermaid 블록 안은 헤딩 없음", titles(mermaidDoc) == ["다이어그램 문서", "다음 섹션"], "\(titles(mermaidDoc))")

print("\n── 닫는 기호와 특수 문자")
check("닫는 # 제거", titles("## 제목 ##") == ["제목"], "\(titles("## 제목 ##"))")
check("C#은 보존", titles("# C#") == ["C#"], "\(titles("# C#"))")
check("F# 같은 언어명도 보존", titles("### F# 입문") == ["F# 입문"], "\(titles("### F# 입문"))")

print("\n── 한글과 실제 문서 형태")
let korean = """
---
title: 프론트매터
---

# 회의록 2026/07/31

## 논의 사항

- 항목 하나

## 결정 사항 ✅
"""
check("한글 헤딩 추출", titles(korean) == ["회의록 2026/07/31", "논의 사항", "결정 사항 ✅"], "\(titles(korean))")
check("프론트매터는 헤딩으로 잡히지 않음", !titles(korean).contains("title: 프론트매터"))
check("빈 문서는 빈 목차", titles("").isEmpty)
check("헤딩 없는 문서는 빈 목차", titles("그냥 본문\n두 번째 줄").isEmpty)

print("\n── 밑줄(setext) 헤딩 (이슈 #3)")
let setext = """
문서 제목
=========

본문입니다.

두 번째 섹션
----------

## ATX도 섞여 있음
"""
check("=== 는 1단계", levels(setext).first == 1, "\(levels(setext))")
check("--- 는 2단계", levels(setext) == [1, 2, 2], "\(levels(setext))")
check("제목 글자를 가져옴", titles(setext) == ["문서 제목", "두 번째 섹션", "ATX도 섞여 있음"],
      "\(titles(setext))")
// 눌렀을 때 밑줄이 아니라 글자가 있는 줄로 가야 한다
check("줄 번호는 밑줄이 아닌 글자 줄", lines(setext) == [0, 5, 8], "\(lines(setext))")

check("밑줄 하나만 있어도 인식", titles("제목\n=") == ["제목"], "\(titles("제목\n="))")

print("\n── 밑줄로 오해하면 안 되는 것")
check("빈 줄 뒤의 --- 는 수평선", titles("본문\n\n---\n\n다음").isEmpty,
      "\(titles("본문\n\n---\n\n다음"))")
check("목록 뒤의 --- 도 수평선", titles("- 항목\n---").isEmpty, "\(titles("- 항목\n---"))")
check("인용 뒤의 --- 도 아님", titles("> 인용\n---").isEmpty, "\(titles("> 인용\n---"))")
check("표 구분선은 제목이 아님", titles("| a | b |\n|---|---|").isEmpty,
      "\(titles("| a | b |\n|---|---|"))")
check("프론트매터 안은 제목이 아님",
      titles("---\ntitle: 보고서\n---\n\n# 진짜 제목") == ["진짜 제목"],
      "\(titles("---\ntitle: 보고서\n---\n\n# 진짜 제목"))")
check("코드 펜스 안의 밑줄도 아님",
      titles("```\n제목\n===\n```\n\n# 밖의 제목") == ["밖의 제목"],
      "\(titles("```\n제목\n===\n```\n\n# 밖의 제목"))")
check("문서 첫 줄이 밑줄이면 무시", titles("===\n본문").isEmpty, "\(titles("===\n본문"))")

print("\n" + (failures.isEmpty ? "ALL PASS (\(total) checks)" : "FAILURES(\(failures.count)/\(total)): \(failures.joined(separator: ", "))"))
exit(failures.isEmpty ? 0 : 1)
