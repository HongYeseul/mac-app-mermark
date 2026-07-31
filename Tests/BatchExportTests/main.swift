import AppKit

// 실제 MermaidExporter로 일괄 내보내기를 끝까지 돌린다.
// 폴더 선택 대화상자를 거치지 않는 경로를 써서 파일이 실제로 떨어지는지 확인한다.

var failures: [String] = []
var total = 0
func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
    total += 1
    print("\(condition ? "PASS" : "FAIL"): \(name)\(condition ? "" : "  → \(detail())")")
    if !condition { failures.append(name) }
}

guard let resourcePath = ProcessInfo.processInfo.environment["MERMARK_RESOURCES"] else {
    print("FAIL: MERMARK_RESOURCES 환경변수가 필요합니다")
    exit(2)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// 앱 번들 대신 소스 트리의 리소스를 쓰도록 지정 (shared 최초 접근 전에 설정해야 함)
MermaidExporter.resourcesURL = URL(fileURLWithPath: resourcePath)

let fm = FileManager.default
let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("mermark-batch-\(ProcessInfo.processInfo.processIdentifier)")
try! fm.createDirectory(at: outputDir, withIntermediateDirectories: true)

let document = """
# 설계 문서

첫 다이어그램:

```mermaid
flowchart LR
    A[시작] --> B[끝]
```

두 번째:

```mermaid
sequenceDiagram
    사용자->>앱: 요청
    앱-->>사용자: 응답
```

```swift
let notMermaid = true
```

세 번째:

```mermaid
flowchart TD
    X --> Y
```
"""

let codes = MermaidBlocks.extract(from: document)
check("문서에서 mermaid 블록 3개 추출", codes.count == 3, "\(codes.count)")

func finish() {
    try? fm.removeItem(at: outputDir)
    print("\n" + (failures.isEmpty ? "ALL PASS (\(total) checks)" : "FAILURES(\(failures.count)/\(total)): \(failures.joined(separator: ", "))"))
    exit(failures.isEmpty ? 0 : 1)
}

print("── 일괄 내보내기 실행")
MermaidExporter.shared.exportAll(codes: codes, baseName: "설계 문서", to: outputDir) { written, failureCount in
    check("실패 없이 완료", failureCount == 0, "\(failureCount)")
    check("파일 3개 생성", written.count == 3, "\(written.count)")

    let names = written.map(\.lastPathComponent)
    check("문서명-번호 규칙으로 명명",
          names == ["설계 문서-1.png", "설계 문서-2.png", "설계 문서-3.png"], "\(names)")
    check("모두 실제로 존재", written.allSatisfy { fm.fileExists(atPath: $0.path) })

    // 각 파일이 열리는 PNG이고 서로 다른 다이어그램인지
    let images = written.compactMap { NSImage(contentsOf: $0) }
    check("모두 유효한 이미지", images.count == 3, "\(images.count)")
    check("모두 0보다 큰 크기", images.allSatisfy { $0.size.width > 0 && $0.size.height > 0 },
          "\(images.map(\.size))")

    let sizes = images.map { "\(Int($0.size.width))x\(Int($0.size.height))" }
    check("다이어그램마다 크기가 다름 (같은 그림 반복 아님)", Set(sizes).count > 1, "\(sizes)")

    let byteCounts = written.compactMap { try? Data(contentsOf: $0).count }
    check("빈 파일 없음", byteCounts.allSatisfy { $0 > 1000 }, "\(byteCounts)")

    // 빈 목록은 아무 일도 하지 않아야 한다
    MermaidExporter.shared.exportAll(codes: [], baseName: "빈 문서", to: outputDir) { written, failures in
        check("빈 목록이면 파일 없이 즉시 완료", written.isEmpty && failures == 0, "\(written.count)/\(failures)")
        finish()
    }
}

DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
    check("시간 초과 없이 완료", false, "timeout")
    finish()
}
app.run()
