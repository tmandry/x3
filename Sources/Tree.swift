import Swindler

enum Layout {
    case horizontal
    case vertical
    case stacked
}
extension Layout {
    var orientation: Orientation {
        get {
            switch (self) {
            case .horizontal: return .horizontal
            case .vertical:   return .vertical
            case .stacked:    return .vertical
            }
        }
    }
}

struct Tree {
    let root: ContainerNode
    let screen: Swindler.Screen
    init(screen: Swindler.Screen) {
        self.root = ContainerNode(.horizontal, parent: nil)
        self.screen = screen
    }

    func refresh() {
        root.refresh(rect: screen.applicationFrame)
    }

    func find(window: Swindler.Window) -> WindowNode? {
        return root.find(window: window)
    }
}

class Node {
    private(set) var parent: ContainerNode?
    fileprivate var size: Float32

    fileprivate init(parent: ContainerNode?) {
        self.parent = parent
        self.size   = 0.0
    }

    fileprivate func reparent(newParent: ContainerNode) {
        assert(parent != nil)
        // TODO: Assert this node has already been removed from parent
        parent = newParent
    }

    // Primarily for internal use.
    var base: Node { return self }
}

extension Node: Equatable {
    static func == (lhs: Node, rhs: Node) -> Bool {
        return lhs === rhs
    }
}

protocol NodeType: class {
    var parent: ContainerNode? { get }

    func find(window: Swindler.Window) -> WindowNode?

    func refresh(rect: CGRect)

    // Primarily for internal use.
    var base: Node { get }

    var kind: NodeKind { get }
}

extension NodeType {
    func contains(window: Swindler.Window) -> Bool {
        return self.find(window: window) != nil
    }
}

extension ContainerNode: NodeType {
    var kind: NodeKind { get { return .container(self) } }
}
extension WindowNode: NodeType {
    var kind: NodeKind { get { return .window(self) } }
}

struct MovingNode {
    let kind: NodeKind
    fileprivate init(_ node: NodeKind) {
        self.kind = node
    }
}

enum NodeKind {
    case container(ContainerNode)
    case window(WindowNode)

    var node: NodeType {
        switch self {
        case .container(let node):
            return node
        case .window(let node):
            return node
        }
    }
    var base: Node { return node.base }
}

extension NodeKind: Equatable {
    static func == (lhs: NodeKind, rhs: NodeKind) -> Bool {
        return lhs.node.base == rhs.node.base
    }
}

class ContainerNode: Node {
    let layout: Layout
    private(set) var children: [NodeKind]

    enum InsertionPolicy {
        case end
    }

    fileprivate init(_ type: Layout, parent: ContainerNode?) {
        self.layout = type
        self.children = []
        super.init(parent: parent)
    }
}

class WindowNode: Node {
    let window: Swindler.Window

    fileprivate init(_ window: Swindler.Window, parent: ContainerNode) {
        self.window = window
        super.init(parent: parent)
    }

    func destroy() {
        let _ = self.parent!.removeChild(self)
    }
}

private extension String {
    func truncate(length: Int, trailing: String = "…") -> String {
        if self.count > length {
            return String(self.prefix(length)) + trailing
        } else {
            return self
        }
    }
}
extension ContainerNode: CustomDebugStringConvertible {
    var debugDescription: String {
        return "\(layout)(size=\(size), \(children.map{$0.node}))"
    }
}
extension WindowNode: CustomDebugStringConvertible {
    var debugDescription: String {
        return "window(\(window.title.value.truncate(length: 30)), size=\(size))"
    }
}

// - MARK: Children
extension ContainerNode {
    @discardableResult
    func createContainer(layout: Layout, at: InsertionPolicy) -> ContainerNode {
        let node = ContainerNode(layout, parent: self)
        let index = indexForPolicy(at)
        children.insert(.container(node), at: index)
        onNewNodeAdjustSize(index: index)
        return node
    }

    @discardableResult
    func createContainer(layout: Layout, at: InsertionPolicy, _ f: (ContainerNode) -> ()) -> ContainerNode {
        let child = createContainer(layout: layout, at: at)
        f(child)
        return child
    }

    @discardableResult
    func createWindow(_ window: Swindler.Window, at: InsertionPolicy) -> WindowNode {
        let node = WindowNode(window, parent: self)
        let index = indexForPolicy(at)
        children.insert(.window(node), at: index)
        onNewNodeAdjustSize(index: index)
        return node
    }

    // TODO: Should there be just a single moveChild method?
    func addChild(_ child: MovingNode, at: InsertionPolicy) {
        child.kind.node.base.reparent(newParent: self)
        let index = indexForPolicy(at)
        children.insert(child.kind, at: index)
        onNewNodeAdjustSize(index: index)
    }

    private func indexForPolicy(_ policy: InsertionPolicy) -> Int {
        switch policy {
        case .end:
            return children.endIndex
        }
    }

    func removeChild(_ node: Node) -> MovingNode? {
        guard let index = children.index(where: {$0.node === node}) else {
            return nil
        }
        let movingNode = MovingNode(children[index])
        children.remove(at: index)
        onRemoveNodeAdjustSize()
        return movingNode
    }
}
extension ContainerNode {
    func find(window: Swindler.Window) -> WindowNode? {
        return children.compactMap({$0.node.find(window: window)}).first
    }
}
extension WindowNode {
    func find(window: Swindler.Window) -> WindowNode? {
        if self.window == window {
            return self
        }
        return nil
    }
}

// - MARK: Size
extension ContainerNode {
    fileprivate func onNewNodeAdjustSize(index: Int) {
        let newSize: Float = 1.0 / Float(children.count)
        let scale = Float(children.count - 1) / Float(children.count)
        for (i, child) in children.enumerated() {
            if i != index {
                child.base.size *= scale
            }
        }
        children[index].base.size = newSize
        check()
    }
    fileprivate func onRemoveNodeAdjustSize() {
        if children.count == 0 {
            return
        }
        let scale = Float(children.count + 1) / Float(children.count)
        for child in children {
            child.base.size *= scale
        }
        check()
    }
    private func check() {
        // sizes should all sum to 1
        assert(children.reduce(0.0){$0 + $1.base.size}.distance(to: 1.0) < 0.01)
    }

    func refresh(rect: CGRect) {
        var start: Float = 0.0
        for child in children {
            let end = start + child.base.size
            child.node.refresh(rect: rectForSlice(whole: rect, start, end))
            start = end
        }
    }
    private func rectForSlice(whole: CGRect, _ start: Float, _ end: Float) -> CGRect {
        let start = CGFloat(start)
        let end   = CGFloat(end)
        switch layout {
        case .horizontal:
            return CGRect(x: (whole.minX + start * whole.width).rounded(),
                          y: whole.minY,
                          width: ((end - start) * whole.width).rounded(),
                          height: whole.height)
        case .vertical:
            return CGRect(x: whole.minX,
                          y: (whole.minY + start * whole.height).rounded(),
                          width: whole.width,
                          height: ((end - start) * whole.height).rounded())
        case .stacked:
            return whole
        }
    }
}
extension WindowNode {
    func refresh(rect: CGRect) {
        let rect = rect.rounded()
        if window.position.value != rect.origin {
            window.position.value = rect.origin
        }
        if window.size.value != rect.size {
            window.size.value = rect.size
        }
    }
}
private extension CGRect {
    func rounded() -> CGRect {
        return CGRect(x: self.minX.rounded(), y: self.minY.rounded(),
                      width: self.width.rounded(), height: self.height.rounded())
    }
}

enum Direction {
    case up
    case down
    case left
    case right
}
extension Direction {
    var orientation: Orientation {
        get {
            switch (self) {
            case .up: return .vertical
            case .down: return .vertical
            case .left: return .horizontal
            case .right: return .horizontal
            }
        }
    }

    var value: Int {
        get {
            switch (self) {
            case .up:    return -1
            case .down:  return +1
            case .left:  return -1
            case .right: return +1
            }
        }
    }
}

enum Orientation {
    case horizontal
    case vertical
}

/// A sort of generalized iterator which crawls the tree in all directions.
struct Crawler {
    var container: ContainerNode?
    var index: Int

    init(at: NodeKind) {
        container = at.base.parent
        index     = container!.children.index(of: at)!
    }

    init(at: NodeType) {
        self.init(at: at.kind)
    }

    /// Moves the crawler in the cardinal direction specified.
    mutating func move(_ direction: Direction) {
        precondition(container != nil)
        precondition(index < container!.children.count)

        // Walk up the tree until we're able to move in the right direction (or hit the end).
        var child = container!.children[index]
        while container != nil && !canMove(direction, from: child) {
            child     = NodeKind.container(container!)
            container = container!.parent
        }

        guard let container = container else {
            // TODO return invalid
            fatalError("unimplemented")
        }

        index = container.children.firstIndex(of: child)! + direction.value
    }

    /// Checks whether we can move within `self.container` along direction `d` from `child`.
    private func canMove(_ d: Direction, from child: NodeKind) -> Bool {
        guard let container = container else {
            return false
        }
        if container.layout.orientation != d.orientation {
            return false
        }
        let curIndex = container.children.firstIndex(of: child)!
        let newIndex = curIndex + d.value
        return newIndex >= 0 && newIndex < container.children.count
    }

    /// Peeks at the node pointed to by the Crawler.
    func peek() -> NodeKind? {
        guard let container = container else {
            return nil
        }
        guard index < container.children.count else {
            return nil
        }
        return container.children[index]
    }
}
