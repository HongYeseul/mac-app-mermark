import SwiftUI
import AppKit

struct MarkdownEditor: NSViewRepresentable {
    let controller: EditorController
    var text: String
    var focusRequestID: Int

    func makeNSView(context: Context) -> NSScrollView {
        controller.scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        controller.setText(text)
        controller.focus(requestID: focusRequestID)
    }
}
