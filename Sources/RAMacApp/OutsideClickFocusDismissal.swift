import AppKit
import SwiftUI

struct OutsideClickFocusDismissal: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        OutsideClickFocusDismissalView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

enum TextInputFocusPolicy {
    static func isTextInput(_ view: NSView?) -> Bool {
        var current = view
        while let view = current {
            if let textField = view as? NSTextField, textField.isEditable {
                return true
            }
            if let textView = view as? NSTextView, textView.isEditable {
                return true
            }
            current = view.superview
        }
        return false
    }

    static func isEditingText(_ responder: NSResponder?) -> Bool {
        if let textView = responder as? NSTextView {
            return textView.isEditable || textView.isFieldEditor
        }
        if let textField = responder as? NSTextField {
            return textField.isEditable
        }
        return false
    }
}

private final class OutsideClickFocusDismissalView: NSView {
    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeEventMonitor()
        guard window != nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self,
                  self.window != nil,
                  let eventWindow = event.window,
                  TextInputFocusPolicy.isEditingText(eventWindow.firstResponder) else {
                return event
            }

            let clickedView = eventWindow.contentView?.hitTest(event.locationInWindow)
            guard !TextInputFocusPolicy.isTextInput(clickedView) else { return event }
            eventWindow.makeFirstResponder(nil)
            return event
        }
    }

    deinit {
        removeEventMonitor()
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}

extension View {
    func dismissTextInputOnOutsideClick() -> some View {
        background(OutsideClickFocusDismissal().frame(width: 0, height: 0))
    }
}
