import Swindler

enum Layout {
    case horizontal
    case vertical
    case stacked
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

    fileprivate func removeFromParent() {
        parent = nil
    }
    fileprivate func reparent(newParent: ContainerNode) {
        assert(parent == nil)
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
        assert(node.base.parent == nil)
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
        return lhs.base == rhs.base
    }
}

class ContainerNode: Node {
    let layout: Layout
    private(set) var children: [NodeKind]
    fileprivate var selectionData: SelectionData

    enum InsertionPolicy {
        case end
        case after(NodeKind)
    }

    fileprivate init(_ type: Layout, parent: ContainerNode?) {
        layout = type
        children = []
        selectionData = initSelectionData()
        super.init(parent: parent)
    }

    /// Destroys this node and all of its children and removes them from the tree.
    func destroyAll() {
        guard let parent = parent else {
            fatalError("cannot destroy root node")
        }
        let _ = parent.removeChild(self)
    }
}

class WindowNode: Node {
    let window: Swindler.Window

    fileprivate init(_ window: Swindler.Window, parent: ContainerNode) {
        self.window = window
        super.init(parent: parent)
    }

    /// Destroys this node and removes it from the parent.
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
        onNewNode(index: index)
        return node
    }

    @discardableResult
    func createContainer(layout: Layout,
                         at: InsertionPolicy,
                         _ f: (ContainerNode) -> ())
    -> ContainerNode {
        let child = createContainer(layout: layout, at: at)
        f(child)
        return child
    }

    @discardableResult
    func createWindow(_ window: Swindler.Window, at: InsertionPolicy) -> WindowNode {
        let node = WindowNode(window, parent: self)
        let index = indexForPolicy(at)
        children.insert(.window(node), at: index)
        onNewNode(index: index)
        return node
    }

    // TODO: Should there be just a single moveChild method?
    func addChild(_ child: MovingNode, at: InsertionPolicy) {
        child.kind.node.base.reparent(newParent: self)
        let index = indexForPolicy(at)
        children.insert(child.kind, at: index)
        onNewNode(index: index)
    }

    private func indexForPolicy(_ policy: InsertionPolicy) -> Int {
        switch policy {
        case .end:
            return children.endIndex
        case .after(let node):
            guard let index = children.index(of: node) else {
                fatalError("requested to insert node after a non-existent child")
            }
            return index + 1
        }
    }

    // TODO: Make it an error to call with a node who isn't our child
    func removeChild(_ node: Node) -> MovingNode? {
        guard let index = children.index(where: {$0.node === node}) else {
            return nil
        }
        let node = children.remove(at: index)
        node.base.removeFromParent()
        onRemoveNode()
        return MovingNode(node)
    }

    func removeChild(_ node: NodeKind) -> MovingNode? {
        return removeChild(node.base)
    }

    private func onNewNode(index: Int) {
        onNewNodeAdjustSize(index: index)
        onNewNodeUpdateSelection(index: index)
    }

    private func onRemoveNode() {
        onRemoveNodeAdjustSize()
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

// - MARK: Selection
// Every non-empty container has a selected node. This node is used, for
// example, in determining which child node to move to during a keyboard motion.
//
// All container nodes have a selected node, but may not themselves be selected.
// In this case, we say the selected node is "locally selected". If the
// selection path from the root of the tree includes a node, we say it is
// "globally selected."
//
// If the selected node is removed, the node after it is selected. If there
// is no node after the removed node, the node before it is selected.
// This is easily accomplished with a simple integer index.

fileprivate typealias SelectionData = Int

fileprivate func initSelectionData() -> SelectionData { return 0 }

extension ContainerNode {
    /// Returns the selected node of this container.
    ///
    /// There is always a selected node, unless the container is empty.
    var selection: NodeKind? {
        get {
            if children.isEmpty {
                return nil
            }
            return children[min(selectionData, children.count - 1)]
        }
    }

    func onNewNodeUpdateSelection(index: Int) {
        if index <= selectionData {
            selectionData += 1
        }
    }

    // FIXME: We need to update the index anytime a child node is added or
    // removed before the selected node.
}

extension Node {
    /// Whether this node is the locally selected node of its parent.
    ///
    /// Note that this does *NOT* indicate whether the node is globally selected.
    var isSelected: Bool {
        guard let parent = parent else {
            // By convention, the root node is never considered selected.
            return false
        }
        // We know our parent has at least one child, so it must have a selection.
        return parent.selection!.base == self
    }

    /// Selects this node locally (within its parent).
    func selectLocally() {
        guard let parent = parent else {
            fatalError("cannot select root node")
        }
        parent.selectionData = parent.children.firstIndex(where: {$0.base == self})!
    }

    /// Selects this node globally (this node and all its ancestors are selected).
    func selectGlobally() {
        var node = self
        while let parent = node.parent {
            node.selectLocally()
            node = parent
        }
    }
}

extension NodeKind {
    var selection: NodeKind? {
        switch self {
        case .container(let c):
            return c.selection
        case .window:
            return nil
        }
    }
}
