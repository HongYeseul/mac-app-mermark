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
    private var highlightWorkItem: DispatchWorkItem?

    private static let baseFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private static let boldFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
    private static let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)

    override init() {
        scrollView = NSTextView.scrollableTextView()
        textView = scrollView.documentView as! NSTextView
        super.init()

        textView.delegate = self
        textView.font = Self.baseFont
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
        highlightNow()
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
        scheduleHighlight()
    }

    // MARK: - 문법 강조

    /// 타이핑 중 매 글자마다 문서 전체를 다시 칠하지 않도록 짧게 모은다
    private func scheduleHighlight() {
        highlightWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.highlightNow() }
        highlightWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private func highlightNow() {
        guard let storage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)

        storage.beginEditing()
        storage.setAttributes([.font: Self.baseFont, .foregroundColor: NSColor.textColor], range: fullRange)
        for token in MarkdownSyntax.tokens(in: textView.string) {
            storage.addAttributes(Self.attributes(for: token.kind), range: token.range)
        }
        storage.endEditing()

        // 강조된 구간 뒤에서 입력을 이어가도 서식이 번지지 않게 한다
        textView.typingAttributes = [.font: Self.baseFont, .foregroundColor: NSColor.textColor]
    }

    private static func attributes(for kind: MarkdownSyntax.Token.Kind) -> [NSAttributedString.Key: Any] {
        switch kind {
        case .heading(let level):
            let size = max(14, 22 - CGFloat(level) * 2)
            return [.font: NSFont.monospacedSystemFont(ofSize: size, weight: .bold),
                    .foregroundColor: NSColor.textColor]
        case .codeBlock, .inlineCode:
            return [.foregroundColor: Brand.codeNSColor]
        case .strong:
            return [.font: boldFont]
        case .emphasis:
            return [.font: italicFont]
        case .linkText:
            return [.foregroundColor: NSColor.linkColor]
        case .linkURL:
            return [.foregroundColor: NSColor.secondaryLabelColor]
        case .blockquote:
            return [.foregroundColor: NSColor.secondaryLabelColor]
        case .listMarker:
            return [.foregroundColor: NSColor.systemOrange]
        case .thematicBreak:
            return [.foregroundColor: NSColor.tertiaryLabelColor]
        case .tag:
            return [.foregroundColor: Brand.accentNSColor]
        }
    }
}
