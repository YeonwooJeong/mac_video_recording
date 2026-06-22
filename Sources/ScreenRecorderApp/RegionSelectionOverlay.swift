import AppKit
import Foundation

@MainActor
final class RegionSelectionController {
    private var window: RegionSelectionWindow?
    private var completion: ((CGRect?) -> Void)?

    func begin(completion: @escaping (CGRect?) -> Void) {
        self.completion = completion

        let screenFrame = NSScreen.screens.reduce(CGRect.null) { partial, screen in
            partial.union(screen.frame)
        }

        let window = RegionSelectionWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        let selectionView = RegionSelectionView(frame: CGRect(origin: .zero, size: screenFrame.size))
        selectionView.onFinish = { [weak self] rect in
            self?.finish(rect)
        }

        window.contentView = selectionView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = false
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    private func finish(_ rect: CGRect?) {
        let callback = completion
        completion = nil
        window?.orderOut(nil)
        window = nil
        callback?(rect)
    }
}

private final class RegionSelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class RegionSelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        let point = event.locationInWindow
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = event.locationInWindow
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = event.locationInWindow

        guard let window, let selectionRect, selectionRect.width >= 20, selectionRect.height >= 20 else {
            onFinish?(nil)
            return
        }

        onFinish?(window.convertToScreen(selectionRect))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onFinish?(nil)
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.32).setFill()
        bounds.fill()

        guard let rect = selectionRect else {
            drawInstruction()
            return
        }

        NSColor.systemBlue.withAlphaComponent(0.22).setFill()
        rect.fill()

        let outline = NSBezierPath(rect: rect)
        outline.lineWidth = 2
        NSColor.systemBlue.setStroke()
        outline.stroke()

        drawSizeLabel(for: rect)
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        )
    }

    private func drawInstruction() {
        let text = "드래그해서 녹화 영역 지정, Esc로 취소"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let rect = CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        text.draw(in: rect, withAttributes: attributes)
    }

    private func drawSizeLabel(for rect: CGRect) {
        let text = "\(Int(rect.width)) x \(Int(rect.height)) pt"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let padding = CGSize(width: 16, height: 8)
        let labelRect = CGRect(
            x: rect.minX,
            y: max(8, rect.minY - textSize.height - padding.height - 8),
            width: textSize.width + padding.width,
            height: textSize.height + padding.height
        )

        let background = NSBezierPath(roundedRect: labelRect, xRadius: 6, yRadius: 6)
        NSColor.black.withAlphaComponent(0.72).setFill()
        background.fill()

        text.draw(
            in: labelRect.insetBy(dx: padding.width / 2, dy: padding.height / 2),
            withAttributes: attributes
        )
    }
}
