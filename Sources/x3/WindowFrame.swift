import Cocoa
import Swindler

class WindowFrame: NSObject, NSWindowDelegate {
    var config: WindowFrameSpec = WindowFrameSpec()

    private var win: NSWindow
    private var inner: Swindler.Window

    init(around window: Swindler.Window) {
        let rect = config.insetEdges.unapply(to: window.frame.value)
        win = NSWindow(contentRect: rect, styleMask: .resizable, backing: .buffered, defer: true)

        // Important: win is implicitly Arc'd, which conflicts with the default
        // autorelease-on-close behavior.
        win.isReleasedWhenClosed = false

        inner = window
        super.init()

        // We can handle mouse events and drag/resize the inner window, but it
        // doesn't seem necessary.
        win.ignoresMouseEvents = true

        // For when the above is false.
        win.isMovableByWindowBackground = true
        win.delegate = self

        win.level = .floating
        win.hasShadow = false
        win.backgroundColor = NSColor.clear

        win.animationBehavior = .none
        let border = Border(frame: win.frame)
        border.config = config
        win.contentView = border

        win.makeKeyAndOrderFront(nil)
    }

    deinit {
        win.close()
    }

    var contentRect: CGRect {
        get {
            config.insetEdges.apply(to: win.frame)
        }
        set {
            if win.inLiveResize {
                return;
            }
            win.setFrame(config.insetEdges.unapply(to: newValue), display: false)
        }
    }

    // These are for when win.ignoresMouseEvents = false.

    func windowDidResize(_ notification: Notification) {
        // We get every(?) step, which is too much, and there is lag as the app
        // responds to each request. Needs some kind of flow control mechanism
        // to respond to backpressure.
        updateFrame(win.frame)
    }

    func windowDidMove(_ notification: Notification) {
        // This works, but it's pretty jank because we don't get _enough_ samples.. see
        // https://stackoverflow.com/questions/5248132/notification-during-nswindow-movement
        // for some tips on making it smoother.
        updateFrame(win.frame)
    }

    private func updateFrame(_ frame: CGRect) {
        let newInnerFrame = config.insetEdges.apply(to: frame)
        if inner.frame.value != newInnerFrame {
            inner.frame.value = newInnerFrame
        }
    }
}

struct WindowFrameSpec {
    var thickness: CGFloat
    var headerHeight: CGFloat
    var radius: CGFloat

    init() {
        thickness = 2
        headerHeight = 20
        radius = 24 + thickness
    }

    var insetEdges: InsetEdges {
        InsetEdges(
            left: thickness,
            right: thickness,
            top: thickness + headerHeight,
            bottom: thickness)
    }
}

struct InsetEdges {
    var left, right, top, bottom: CGFloat

    var inverted: InsetEdges {
        InsetEdges(left: -left, right: -right, top: -top, bottom: -bottom)
    }

    func apply(to rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x + left,
            y: rect.origin.y + bottom,
            width: rect.width - left - right,
            height: rect.height - bottom - top)
    }

    func unapply(to rect: CGRect) -> CGRect {
        inverted.apply(to: rect)
    }
}

class Border: NSView {
    var config: WindowFrameSpec = WindowFrameSpec()

    override func draw(_ dirtyRect: NSRect) {
        let thickness = config.thickness
        let headerHeight = config.headerHeight
        let radius = config.radius

        let wholeRect = frame.insetBy(dx: thickness / 2.0, dy: thickness / 2.0)

        let (headerRect, frameRect) = wholeRect.divided(atDistance: headerHeight, from: .maxYEdge)

        NSColor.lightGray.setStroke()
        NSColor.lightGray.setFill()

        do {
            let rect = frameRect
            let path = NSBezierPath()

            let topLeft = NSPoint(x: rect.minX, y: rect.maxY)
            path.move(to: NSPoint(x: rect.minX + radius, y: rect.maxY))
            path.curve(to: NSPoint(x: rect.minX, y: rect.maxY - radius), controlPoint1: topLeft, controlPoint2: topLeft)

            let botLeft = NSPoint(x: rect.minX, y: rect.minY)
            path.line(to: NSPoint(x: rect.minX, y: rect.minY + radius))
            path.curve(to: NSPoint(x: rect.minX + radius, y: rect.minY), controlPoint1: botLeft, controlPoint2: botLeft)

            let botRight = NSPoint(x: rect.maxX, y: rect.minY)
            path.line(to: NSPoint(x: rect.maxX - radius, y: rect.minY))
            path.curve(to: NSPoint(x: rect.maxX, y: rect.minY + radius), controlPoint1: botRight, controlPoint2: botRight)

            let topRight = NSPoint(x: rect.maxX, y: rect.maxY)
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - radius))
            path.curve(to: NSPoint(x: rect.maxX - radius, y: rect.maxY), controlPoint1: topRight, controlPoint2: topRight)

            //path.line(to: NSPoint(x: rect.minX, y: rect.maxY))

            path.lineWidth = thickness
            path.stroke()
        }

        do {
            let rect = headerRect
            let path = NSBezierPath()

            let topLeft = NSPoint(x: rect.minX, y: rect.maxY)
            let startingPoint = NSPoint(x: rect.minX + radius, y: rect.maxY)
            path.move(to: startingPoint)
            path.curve(to: NSPoint(x: rect.minX, y: rect.maxY - radius), controlPoint1: topLeft, controlPoint2: topLeft)

            let ftl = NSPoint(x: frameRect.minX, y: frameRect.maxY)
            path.line(to: NSPoint(x: rect.minX, y: rect.minY - radius))
            path.curve(to: NSPoint(x: rect.minX + radius, y: rect.minY), controlPoint1: ftl, controlPoint2: ftl)

            let ftr = NSPoint(x: frameRect.maxX, y: frameRect.maxY)
            path.line(to: NSPoint(x: rect.maxX - radius, y: rect.minY))
            path.curve(to: NSPoint(x: rect.maxX, y: rect.minY - radius), controlPoint1: ftr, controlPoint2: ftr)

            let topRight = NSPoint(x: rect.maxX, y: rect.maxY)
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - radius))
            path.curve(to: NSPoint(x: rect.maxX - radius, y: rect.maxY), controlPoint1: topRight, controlPoint2: topRight)

            path.line(to: startingPoint)

            path.lineWidth = thickness
            path.stroke()
            path.fill()
        }

        //let border = NSBezierPath(roundedRect: rect, xRadius: thickness, yRadius: thickness)
        //border.lineWidth = thickness
        //border.fill()
    }
}
