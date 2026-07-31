import AppKit

// 마크다운 문법 강조: 토큰 범위 계산과, 실제 NSTextView에 속성이 입혀지는지 확인한다.

var failures: [String] = []
var total = 0
func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
    total += 1
    print("\(condition ? "PASS" : "FAIL"): \(name)\(condition ? "" : "  → \(detail())")")
    if !condition { failures.append(name) }
}
func pump(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

func tokens(_ text: String) -> [MarkdownSyntax.Token] { MarkdownSyntax.tokens(in: text) }
func kinds(_ text: String) -> [MarkdownSyntax.Token.Kind] { tokens(text).map(\.kind) }
/// 토큰이 실제로 가리키는 문자열 (범위가 어긋나면 여기서 드러난다)
func slices(_ text: String) -> [String] {
    let ns = text as NSString
    return tokens(text).map { ns.substring(with: $0.range) }
}

print("── A. 블록 요소")
let headings = "# 제목 1\n## 제목 2\n###### 제목 6\n####### 일곱 개는 헤딩 아님"
check("헤딩 레벨 인식",
      kinds(headings).prefix(3).elementsEqual([.heading(level: 1), .heading(level: 2), .heading(level: 6)]),
      "\(kinds(headings))")
check("7개 이상은 헤딩 아님", kinds(headings).count == 3, "\(kinds(headings))")
check("헤딩 토큰은 줄 전체", slices(headings).first == "# 제목 1", "\(slices(headings).first ?? "nil")")
// "#태그"는 헤딩이 아니라 태그로 잡힌다
check("# 뒤 공백 없으면 헤딩 아님", kinds("#태그") == [.tag], "\(kinds("#태그"))")
check("태그 토큰은 # 포함", slices("본문 #정산 끝") == ["#정산"], "\(slices("본문 #정산 끝"))")

check("인용문", kinds("> 인용된 문장") == [.blockquote])
check("수평선", kinds("---") == [.thematicBreak], "\(kinds("---"))")
check("별표 수평선", kinds("***") == [.thematicBreak], "\(kinds("***"))")

check("목록 표시만 토큰", slices("- 항목 하나") == ["-"], "\(slices("- 항목 하나"))")
check("번호 목록", slices("1. 첫째") == ["1."], "\(slices("1. 첫째"))")
check("들여쓴 목록", slices("  * 중첩") == ["*"], "\(slices("  * 중첩"))")

print("\n── B. 인라인 요소")
check("굵게", slices("이건 **굵은 글씨** 입니다") == ["**굵은 글씨**"], "\(slices("이건 **굵은 글씨** 입니다"))")
check("기울임", slices("이건 *기울임* 입니다") == ["*기울임*"], "\(slices("이건 *기울임* 입니다"))")
check("굵게가 기울임보다 우선",
      kinds("**둘 다**") == [.strong], "\(kinds("**둘 다**"))")
check("인라인 코드", slices("값은 `code` 입니다") == ["`code`"], "\(slices("값은 `code` 입니다"))")
check("인라인 코드 안의 별표는 강조가 아님",
      kinds("`**코드 안**`") == [.inlineCode], "\(kinds("`**코드 안**`"))")

let linkLine = "[한글 링크](./경로.md) 뒤 문장"
check("링크는 텍스트와 주소로 나뉨",
      kinds(linkLine) == [.linkText, .linkURL], "\(kinds(linkLine))")
check("한글 링크 범위가 어긋나지 않음",
      slices(linkLine) == ["[한글 링크]", "(./경로.md)"], "\(slices(linkLine))")
let emojiLink = "[🎉 축하](https://a.b) 끝"
check("이모지 링크 범위도 정확",
      slices(emojiLink) == ["[🎉 축하]", "(https://a.b)"], "\(slices(emojiLink))")

print("\n── C. 코드 펜스")
let fenced = """
# 제목

```swift
let x = **not bold**
# 주석이지 헤딩이 아님
```

본문 **굵게**
"""
let fencedKinds = kinds(fenced)
check("코드 블록 하나로 묶임", fencedKinds.filter { $0 == .codeBlock }.count == 1, "\(fencedKinds)")
check("펜스 안에는 다른 토큰이 없음",
      !fencedKinds.contains(.strong) || fencedKinds.filter { $0 == .strong }.count == 1, "\(fencedKinds)")
let codeSlice = tokens(fenced).first { $0.kind == .codeBlock }.map { (fenced as NSString).substring(with: $0.range) }
check("코드 블록 범위가 펜스 전체", codeSlice?.hasPrefix("```swift") == true && codeSlice?.hasSuffix("```") == true,
      "\(codeSlice ?? "nil")")
check("펜스 뒤 본문은 다시 강조됨", fencedKinds.contains(.strong), "\(fencedKinds)")
check("닫히지 않은 펜스는 끝까지 코드",
      kinds("```\n계속\n**굵게 아님**") == [.codeBlock], "\(kinds("```\n계속\n**굵게 아님**"))")

print("\n── D. 실제 NSTextView 적용")
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let controller = EditorController()
let frame = NSRect(x: 0, y: 0, width: 600, height: 400)
let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
window.contentView = controller.scrollView
controller.scrollView.frame = frame

let document = "# 큰 제목\n\n본문에 **굵게** 와 `코드` 가 있다.\n\n[링크](./a.md)\n"
controller.setText(document)
controller.scrollView.layoutSubtreeIfNeeded()
pump(0.4)

guard let storage = (controller.scrollView.documentView as? NSTextView)?.textStorage else {
    check("textStorage 접근", false, "nil")
    exit(1)
}
let ns = document as NSString

func font(at index: Int) -> NSFont? {
    storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
}
func color(at index: Int) -> NSColor? {
    storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
}

let headingIndex = ns.range(of: "큰 제목").location
let bodyIndex = ns.range(of: "본문에").location
let strongIndex = ns.range(of: "**굵게**").location
let codeIndex = ns.range(of: "`코드`").location
let linkIndex = ns.range(of: "[링크]").location

check("제목이 굵게 적용됨",
      font(at: headingIndex)?.fontDescriptor.symbolicTraits.contains(.bold) == true,
      "\(String(describing: font(at: headingIndex)))")
check("제목 글자 크기가 본문보다 큼",
      (font(at: headingIndex)?.pointSize ?? 0) > (font(at: bodyIndex)?.pointSize ?? 99),
      "제목 \(font(at: headingIndex)?.pointSize ?? -1) vs 본문 \(font(at: bodyIndex)?.pointSize ?? -1)")
check("본문은 기본 굵기",
      font(at: bodyIndex)?.fontDescriptor.symbolicTraits.contains(.bold) == false,
      "\(String(describing: font(at: bodyIndex)))")
check("굵게 표기가 굵게 적용됨",
      font(at: strongIndex)?.fontDescriptor.symbolicTraits.contains(.bold) == true,
      "\(String(describing: font(at: strongIndex)))")
check("인라인 코드에 색이 적용됨", color(at: codeIndex) != NSColor.textColor,
      "\(String(describing: color(at: codeIndex)))")
check("링크에 색이 적용됨", color(at: linkIndex) != NSColor.textColor,
      "\(String(describing: color(at: linkIndex)))")
check("본문은 기본 색", color(at: bodyIndex) == NSColor.textColor,
      "\(String(describing: color(at: bodyIndex)))")

// 편집 후에도 다시 칠해지는지 (isRichText=false가 속성을 지우지 않는지)
controller.setText("본문만 있는 문서")
pump(0.4)
controller.setText("# 다시 제목\n본문")
pump(0.4)
let ns2 = "# 다시 제목\n본문" as NSString
let newHeadingIndex = ns2.range(of: "다시 제목").location
check("텍스트 교체 후에도 강조 유지",
      (font(at: newHeadingIndex)?.fontDescriptor.symbolicTraits.contains(.bold)) == true,
      "\(String(describing: font(at: newHeadingIndex)))")

print("\n" + (failures.isEmpty ? "ALL PASS (\(total) checks)" : "FAILURES(\(failures.count)/\(total)): \(failures.joined(separator: ", "))"))
exit(failures.isEmpty ? 0 : 1)
