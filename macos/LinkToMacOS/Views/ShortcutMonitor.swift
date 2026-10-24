import AppKit
import SwiftUI

/// 在窗口是 key window 且没有在输入文字时，拦截 ⌘C 和 ⌘A。
struct ShortcutMonitor: NSViewRepresentable {
    var isEnabled = true
    var onCopy: () -> Void
    var onSelectAll: () -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.isEnabled = isEnabled
        view.onCopy = onCopy
        view.onSelectAll = onSelectAll
    }

    final class MonitorView: NSView {
        var isEnabled = true
        var onCopy: () -> Void = {}
        var onSelectAll: () -> Void = {}
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard isEnabled, let window, event.window === window, window.isKeyWindow,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  !(window.firstResponder is NSText)
            else { return event }
            switch event.charactersIgnoringModifiers {
            case "c": onCopy(); return nil
            case "a": onSelectAll(); return nil
            default: return event
            }
        }
    }
}
