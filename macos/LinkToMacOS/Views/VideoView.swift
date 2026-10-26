import AppKit
import AVFoundation
import LinkCore
import SwiftUI

/// 显示手机画面的视图，同时把鼠标键盘变成手机上的触摸和按键。窗口比例锁定为手机画面的比例。
struct VideoView: NSViewRepresentable {
    let decoder: VideoDecoder
    let videoSize: CGSize
    /// 窗口里画面以外占的固定尺寸（手机边框、右侧按键栏），计算窗口比例时要算进去。
    var chrome: CGSize = .zero
    let onInput: (MirrorInput) -> Void

    func makeNSView(context: Context) -> VideoNSView {
        let view = VideoNSView(layer: decoder.layer)
        view.onInput = onInput
        view.chrome = chrome
        view.videoSize = videoSize
        return view
    }

    func updateNSView(_ view: VideoNSView, context: Context) {
        view.onInput = onInput
        view.chrome = chrome
        view.videoSize = videoSize
    }
}

final class VideoNSView: NSView {
    private let videoLayer: AVSampleBufferDisplayLayer
    var onInput: (MirrorInput) -> Void = { _ in }
    var videoSize: CGSize = .zero {
        didSet {
            guard videoSize != oldValue else { return }
            needsLayout = true
            updateWindowAspect(animated: oldValue != .zero)
        }
    }
    var chrome: CGSize = .zero
    private var dragging = false

    init(layer videoLayer: AVSampleBufferDisplayLayer) {
        self.videoLayer = videoLayer
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(videoLayer)
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        videoLayer.frame = bounds
        keepAspectRatio()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        updateWindowAspect(animated: false)
    }

    // MARK: 窗口比例

    /// 投屏窗口没有标题栏和边框（内容铺满整个窗口），所以这里一律按窗口外框（frame）计算，不用 contentRect。
    private func updateWindowAspect(animated: Bool) {
        guard let window, videoSize.width > 0, videoSize.height > 0 else { return }
        let aspect = videoSize.width / videoSize.height
        // 右侧工具栏大约 400pt 高，窗口不能比它矮
        let minHeight = max(400, chrome.height + 360)
        window.minSize = aspect >= 1
            ? NSSize(width: (minHeight - chrome.height) * aspect + chrome.width, height: minHeight)
            : NSSize(width: 240 + chrome.width, height: max(minHeight, 240 / aspect + chrome.height))

        // 画面保持长边不变，旋转时横竖互换；不超出屏幕
        let current = window.frame.size
        var long = max(current.width - chrome.width, current.height - chrome.height)
        if current.width < 10 { long = 780 }
        var video = aspect >= 1 ? NSSize(width: long, height: long / aspect) : NSSize(width: long * aspect, height: long)
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            let scale = min(1, (visible.width - 40 - chrome.width) / video.width, (visible.height - 60 - chrome.height) / video.height)
            video = NSSize(width: video.width * scale, height: video.height * scale)
        }
        let target = NSSize(width: video.width + chrome.width, height: video.height + chrome.height)
        window.aspectRatio = target
        if abs(target.width - current.width) > 2 || abs(target.height - current.height) > 2 {
            let frame = NSRect(x: window.frame.minX, y: window.frame.maxY - target.height, width: target.width, height: target.height)
            window.setFrame(frame, display: true, animate: animated)
        }
    }

    /// 窗口比例只能是一个固定比值，而边框和工具栏是固定的点数，所以窗口宽度变了要按新宽度重算一次比例。
    private func keepAspectRatio() {
        guard chrome != .zero, let window, videoSize.width > 0, videoSize.height > 0 else { return }
        let content = window.frame.size
        let videoWidth = content.width - chrome.width
        guard videoWidth > 0 else { return }
        let want = NSSize(width: content.width, height: videoWidth * videoSize.height / videoSize.width + chrome.height)
        let have = window.aspectRatio
        guard have.height > 0, abs(have.width / have.height - want.width / want.height) > 0.0005 else { return }
        window.aspectRatio = want
    }

    // MARK: 坐标换算

    /// 画面在视图里的实际区域（resizeAspect 时两侧可能有黑边）。
    private func videoRect() -> CGRect {
        guard videoSize.width > 0, videoSize.height > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
        let scale = min(bounds.width / videoSize.width, bounds.height / videoSize.height)
        let size = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// 视图坐标 → 画面里 0…1 的相对位置（左上角为原点）。
    private func normalized(_ event: NSEvent) -> (x: Double, y: Double, inside: Bool) {
        let point = convert(event.locationInWindow, from: nil)
        let rect = videoRect()
        let x = (point.x - rect.minX) / rect.width
        let y = 1 - (point.y - rect.minY) / rect.height
        return (min(1, max(0, x)), min(1, max(0, y)), rect.contains(point))
    }

    // MARK: 鼠标

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = normalized(event)
        guard p.inside else { return }
        dragging = true
        onInput(.touch(0, x: p.x, y: p.y))
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        let p = normalized(event)
        onInput(.touch(2, x: p.x, y: p.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        dragging = false
        let p = normalized(event)
        onInput(.touch(1, x: p.x, y: p.y))
    }

    /// 右键 = 返回，中键 = 主页（与 scrcpy 一致）。
    override func rightMouseDown(with event: NSEvent) { onInput(.command("back")) }
    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 { onInput(.command("home")) }
    }

    override func scrollWheel(with event: NSEvent) {
        let p = normalized(event)
        guard p.inside else { return }
        let divisor = event.hasPreciseScrollingDeltas ? 30.0 : 3.0
        let v = max(-5, min(5, event.scrollingDeltaY / divisor))
        let h = max(-5, min(5, event.scrollingDeltaX / divisor))
        guard v != 0 || h != 0 else { return }
        onInput(MirrorInput(k: "s", x: p.x, y: p.y, h: h, v: v))
    }

    // MARK: 键盘

    private func meta(_ event: NSEvent) -> Int {
        let f = event.modifierFlags
        return AndroidKeys.metaState(shift: f.contains(.shift), option: f.contains(.option), control: f.contains(.control), command: f.contains(.command))
    }

    private func forward(_ event: NSEvent, action: Int) -> Bool {
        guard let code = AndroidKeys.keyCode(forMacKeyCode: event.keyCode) else { return false }
        onInput(MirrorInput(k: "key", a: action, c: code, m: meta(event)))
        return true
    }

    override func keyDown(with event: NSEvent) {
        if !forward(event, action: 0) { super.keyDown(with: event) }
    }

    override func keyUp(with event: NSEvent) {
        if !forward(event, action: 1) { super.keyUp(with: event) }
    }

    /// ⌘C / ⌘V / ⌘A 等：转给手机（当作 Ctrl+键）。
    /// ⌘W ⌘Q ⌘M ⌘H ⌘, ⌘[ ⌘] ⌘数字 和所有 ⇧⌘ 组合是菜单命令，仍由 Mac 自己处理。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        guard flags.contains(.command), !flags.contains(.shift), window?.firstResponder === self else { return false }
        let reserved = Set("wqmh,[]0123456789".map(String.init))
        if let key = event.charactersIgnoringModifiers?.lowercased(), reserved.contains(key) { return false }
        guard AndroidKeys.keyCode(forMacKeyCode: event.keyCode) != nil else { return false }
        _ = forward(event, action: 0)
        _ = forward(event, action: 1)
        return true
    }
}
