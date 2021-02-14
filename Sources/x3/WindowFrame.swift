import Cocoa
import Swindler

class WindowFrame: NSObject, NSWindowDelegate {
    var spec: WindowFrameSpec {
        get { border.spec }
        set {
            border.spec = newValue
            border.needsToDraw(border.frame)
        }
    }

    var title: String {
        get { border.title }
        set { border.title = newValue }
    }

    private var win: NSWindow
    private var inner: Swindler.Window?
    private var border: Border

    convenience init(_ spec: WindowFrameSpec, around window: Swindler.Window) {
        self.init(spec, frame: window.frame.value)
        inner = window
        border.title = window.title.value
    }

    init(_ spec: WindowFrameSpec, frame: CGRect) {
        let rect = spec.insetEdges.unapply(to: frame)
        win = NSWindow(contentRect: rect, styleMask: .resizable, backing: .buffered, defer: true)

        // Important: win is implicitly Arc'd, which conflicts with the default
        // autorelease-on-close behavior.
        win.isReleasedWhenClosed = false

        border = Border(frame: win.frame, spec: spec)
        win.contentView = border
        selectionStatus = .unselected

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

        win.makeKeyAndOrderFront(nil)
    }

    deinit {
        win.close()
    }

    var frame: CGRect {
        get { win.frame }
        set { win.setFrame(newValue, display: true) }
    }

    var selectionStatus: SelectionStatus {
        didSet {
            switch selectionStatus {
                case .selectedGlobally: border.edgeColor = NSColor.blue
                case .selectedLocally: border.edgeColor = NSColor.lightGray
                case .unselected: border.edgeColor = NSColor.gray
            }
        }
    }

    var contentRect: CGRect {
        get {
            spec.insetEdges.apply(to: win.frame)
        }
        set {
            if win.inLiveResize {
                return;
            }
            win.setFrame(spec.insetEdges.unapply(to: newValue), display: true)
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
        let newInnerFrame = spec.insetEdges.apply(to: frame)
        if inner?.frame.value != newInnerFrame {
            inner?.frame.value = newInnerFrame
        }
    }
}

enum SelectionStatus {
    case selectedGlobally
    case selectedLocally
    case unselected
}

struct WindowFrameSpec {
    private var headerHeight_: CGFloat

    var thickness: CGFloat
    var header: Bool
    var radius: CGFloat
    var headerHeight: CGFloat { header ? headerHeight_ : 0 }

    init(header withHeader: Bool) {
        thickness = 1
        headerHeight_ = 20
        header = withHeader
        radius = 27 + thickness
    }

    var insetEdges: InsetEdges {
        InsetEdges(
            left: thickness,
            right: thickness,
            top: thickness + headerHeight,
            bottom: thickness)
    }

    func textFrame(size: NSSize) -> NSRect {
        let margin = radius / 2
        return NSRect(
            x: margin,
            y: size.height - thickness - headerHeight,
            width: size.width - 2 * margin,
            height: headerHeight)
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
    var spec: WindowFrameSpec
    var text: NSTextField

    var title: String {
        get { text.stringValue }
        set { text.stringValue = newValue }
    }

    var edgeColor: NSColor {
        didSet {
            display()
        }
    }

    init(frame: NSRect, spec: WindowFrameSpec) {
        self.spec = spec
        self.edgeColor = NSColor.lightGray
        text = NSTextField(labelWithString: "")
        text.alignment = .center
        super.init(frame: frame)
        addSubview(text)
    }

    required init?(coder: NSCoder) {
        fatalError("unimplemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let thickness = spec.thickness
        let headerHeight = spec.headerHeight
        let radius = spec.radius

        // Is this correct?
        let wholeRect = frame.insetBy(dx: thickness / 2.0, dy: thickness / 2.0)

        let (headerRect, frameRect) = wholeRect.divided(atDistance: headerHeight, from: .maxYEdge)

        NSColor.gray.setStroke()
        NSColor.gray.setFill()
        if spec.header {
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

            //path.line(to: startingPoint)

            path.lineWidth = thickness
            path.stroke()
            path.fill()

            text.frame = spec.textFrame(size: frame.size)
            text.isHidden = false
        } else {
            text.isHidden = true
        }

        edgeColor.setStroke()
        do {
            let rect = wholeRect
            let path = NSBezierPath()

            let topLeft = NSPoint(x: rect.minX, y: rect.maxY)
            let startingPoint = NSPoint(x: rect.minX + radius, y: rect.maxY)
            path.move(to: startingPoint)
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

            path.line(to: startingPoint)

            path.lineWidth = thickness
            path.stroke()
        }

        //let border = NSBezierPath(roundedRect: rect, xRadius: thickness, yRadius: thickness)
        //border.lineWidth = thickness
        //border.fill()
    }
}
