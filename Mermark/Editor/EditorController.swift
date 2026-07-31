import AppKit

/// NSTextView와 스크롤 뷰를 소유한다. SwiftUI 뷰가 아니라 컨트롤러가 들고 있어야
/// 뷰어/에디터/분할 모드를 오갈 때 실행 취소 기록·커서·스크롤 위치가 유지된다.
final class EditorController: NSObject, ObservableObject, NSTextViewDelegate {
    let scrollView: NSScrollView
    private let textView: NSTextView

    var onTextChange: ((String) -> Void)?
    var onScrollToLine: ((Int) -> Void)?

    private var suppressReportUntil = Date.distantPast
    private var lastReportedLine = -1
    private var lastFocusRequestID = 0

    override init() {
        scrollView = NSTextView.scrollableTextView()
        textView = scrollView.documentView as! NSTextView
        super.init()

        textView.delegate = self
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        // 줄 단위 레이아웃 계산(glyph ↔ 문자 인덱스)을 쓰기 위해 TextKit 1로 고정
        _ = textView.layoutManager

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(boundsDidChange),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView
        )
    }

    var text: String { textView.string }

    func setText(_ text: String) {
        guard textView.string != text else { return }
        textView.string = text
        lastReportedLine = -1
    }

    func focus(requestID: Int) {
        guard requestID != lastFocusRequestID else { return }
        lastFocusRequestID = requestID
        textView.window?.makeFirstResponder(textView)
    }

    /// 화면 최상단에 보이는 줄 번호
    var topVisibleLine: Int {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return 0 }
        let glyphRange = layoutManager.glyphRange(forBoundingRect: scrollView.contentView.bounds, in: container)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphRange.location)
        return LineMath.lineNumber(atCharacterIndex: charIndex, in: textView.string)
    }

    func scroll(toLine line: Int) {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        let index = LineMath.characterIndex(ofLine: line, in: textView.string)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: index, length: 0), actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)

        // 반대쪽에서 온 스크롤이 다시 반대쪽으로 되돌아가지 않도록 잠시 보고를 멈춘다
        suppressReportUntil = Date().addingTimeInterval(0.25)

        let documentHeight = scrollView.documentView?.frame.height ?? 0
        let maxY = max(0, documentHeight - scrollView.contentView.bounds.height)
        let y = min(max(0, rect.minY + textView.textContainerInset.height), maxY)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    @objc private func boundsDidChange() {
        guard Date() >= suppressReportUntil else { return }
        let line = topVisibleLine
        guard line != lastReportedLine else { return }
        lastReportedLine = line
        onScrollToLine?(line)
    }

    func textDidChange(_ notification: Notification) {
        onTextChange?(textView.string)
    }
}
