import AppKit

// 태그 추출 규칙과 태그 필터를 확인한다.

var failures: [String] = []
var total = 0
func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
    total += 1
    print("\(condition ? "PASS" : "FAIL"): \(name)\(condition ? "" : "  → \(detail())")")
    if !condition { failures.append(name) }
}
func pump(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

func tags(_ text: String) -> [String] { MarkdownTags.tags(in: text) }

print("── A. 본문 태그")
check("기본 태그", tags("오늘 #회의 내용") == ["회의"], "\(tags("오늘 #회의 내용"))")
check("줄머리 태그", tags("#정산 관련") == ["정산"], "\(tags("#정산 관련"))")
check("여러 개", tags("#정산 과 #검토 둘 다") == ["정산", "검토"], "\(tags("#정산 과 #검토 둘 다"))")
check("중첩 태그 표기", tags("#프로젝트/메르마크 진행") == ["프로젝트/메르마크"],
      "\(tags("#프로젝트/메르마크 진행"))")
check("영문·숫자·기호", tags("#v2 #api-design #snake_case") == ["v2", "api-design", "snake_case"],
      "\(tags("#v2 #api-design #snake_case"))")
check("중복은 한 번만", tags("#회의 하고 #회의 또") == ["회의"], "\(tags("#회의 하고 #회의 또"))")
check("대소문자 다른 중복도 한 번만", tags("#Todo 와 #todo") == ["Todo"], "\(tags("#Todo 와 #todo"))")

print("\n── B. 태그가 아닌 것")
check("헤딩은 태그가 아님", tags("# 제목입니다").isEmpty, "\(tags("# 제목입니다"))")
check("2단계 헤딩도 아님", tags("## 섹션").isEmpty, "\(tags("## 섹션"))")
check("주소의 프래그먼트는 아님", tags("https://example.com/a#section 참고").isEmpty,
      "\(tags("https://example.com/a#section 참고"))")
check("단어 중간의 #은 아님", tags("C#은 언어다").isEmpty, "\(tags("C#은 언어다"))")
check("# 뒤 공백이면 아님", tags("무게 # 5kg").isEmpty, "\(tags("무게 # 5kg"))")
check("인라인 코드 안은 제외", tags("`#코드안` 은 태그 아님").isEmpty, "\(tags("`#코드안` 은 태그 아님"))")

let fenced = """
# 문서

본문의 #진짜태그

```bash
# 주석
echo "#가짜태그"
```

펜스 뒤 #또다른태그
"""
check("코드 펜스 안은 제외",
      tags(fenced) == ["진짜태그", "또다른태그"], "\(tags(fenced))")

print("\n── C. 프론트매터 태그")
let listStyle = """
---
title: 보고서
tags:
  - 정산
  - 검토중
---

본문입니다.
"""
check("목록 형식", tags(listStyle) == ["정산", "검토중"], "\(tags(listStyle))")

let inlineStyle = """
---
tags: 정산, 검토중
---
본문
"""
check("쉼표 형식", tags(inlineStyle) == ["정산", "검토중"], "\(tags(inlineStyle))")

let bracketStyle = """
---
tags: [정산, 검토중]
---
본문
"""
check("대괄호 형식", tags(bracketStyle) == ["정산", "검토중"], "\(tags(bracketStyle))")

let mixed = """
---
title: 회의록
tags:
  - 정산
---

본문의 #추가태그 도 함께
"""
check("프론트매터와 본문을 합침", tags(mixed) == ["정산", "추가태그"], "\(tags(mixed))")
check("프론트매터의 다른 키는 무시", !tags(mixed).contains("회의록"), "\(tags(mixed))")

let quoted = """
---
tags: ["따옴표", '작은따옴표']
---
본문
"""
check("따옴표 제거", tags(quoted) == ["따옴표", "작은따옴표"], "\(tags(quoted))")

print("\n── D. 태그 필터")
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let fm = FileManager.default
let folder = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("mermark-tags-\(ProcessInfo.processInfo.processIdentifier)")
try? fm.removeItem(at: folder)
try! fm.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: folder) }

try! "# 정산 노트\n\n#정산 #검토".write(to: folder.appendingPathComponent("정산 노트.md"), atomically: true, encoding: .utf8)
try! "---\ntags:\n  - 정산\n---\n\n# 회의록".write(to: folder.appendingPathComponent("회의록.md"), atomically: true, encoding: .utf8)
try! "# 잡담\n\n태그 없음".write(to: folder.appendingPathComponent("잡담.md"), atomically: true, encoding: .utf8)

UserDefaults.standard.set(folder.path, forKey: "notesFolderPath")
let store = NoteStore()
pump(0.5)

let all = store.allTags
check("태그 목록 수집", all.map(\.name).sorted() == ["검토", "정산"], "\(all)")
check("사용 횟수 집계", all.first(where: { $0.name == "정산" })?.count == 2, "\(all)")
check("많이 쓰인 태그가 앞", all.first?.name == "정산", "\(all.map(\.name))")

check("필터 전에는 전체", store.filteredNotes.count == 3, "\(store.filteredNotes.map(\.title))")

store.toggleTag("정산")
check("태그로 거르기",
      Set(store.filteredNotes.map(\.title)) == ["정산 노트", "회의록"], "\(store.filteredNotes.map(\.title))")

store.searchQuery = "회의"
check("태그 필터와 검색이 함께 적용",
      store.filteredNotes.map(\.title) == ["회의록"], "\(store.filteredNotes.map(\.title))")
store.searchQuery = ""

store.toggleTag("정산")
check("같은 태그를 다시 누르면 해제", store.selectedTag == nil && store.filteredNotes.count == 3,
      "\(store.selectedTag ?? "nil") / \(store.filteredNotes.count)")

store.toggleTag("검토")
check("다른 태그로 전환", store.filteredNotes.map(\.title) == ["정산 노트"], "\(store.filteredNotes.map(\.title))")

// 외부에서 내용이 바뀌면 태그 캐시도 갱신되어야 한다
store.toggleTag("검토")
try! "# 잡담\n\n이제 #검토 대상".write(to: folder.appendingPathComponent("잡담.md"), atomically: true, encoding: .utf8)
pump(1.5)
store.toggleTag("검토")
check("외부 수정 후 태그 갱신",
      Set(store.filteredNotes.map(\.title)) == ["정산 노트", "잡담"], "\(store.filteredNotes.map(\.title))")

print("\n" + (failures.isEmpty ? "ALL PASS (\(total) checks)" : "FAILURES(\(failures.count)/\(total)): \(failures.joined(separator: ", "))"))
exit(failures.isEmpty ? 0 : 1)
