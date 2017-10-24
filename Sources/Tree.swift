import Swindler

enum Layout {
    case horizontal
    case vertical
    case stacked
}

struct Tree {
    let root: ContainerNode
    init() {
        root = ContainerNode(.horizontal, parent: nil)
    }
}

class Node {
    private var parent_: ContainerNode?
    var parent: ContainerNode? { return parent_ }

    fileprivate init(parent: ContainerNode?) {
        self.parent_ = parent
    }

    fileprivate func reparent(newParent: ContainerNode) {
        assert(parent != nil)
        // TODO: Assert this node has already been removed from parent
        parent_ = newParent
    }
}

protocol NodeType: class {
    var parent: ContainerNode? { get }
    func contains(window: Swindler.Window) -> Bool
}

struct MovingNode {
    let node: NodeKind
    fileprivate init(_ node: NodeKind) {
        self.node = node
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
}

class ContainerNode: Node {
    let layout: Layout
    var children: [NodeKind] { return children_ }

    private var children_: [NodeKind]

    enum InsertionPolicy {
        case end
    }

    fileprivate init(_ type: Layout, parent: ContainerNode?) {
        self.layout = type
        self.children_ = []
        super.init(parent: parent)
    }

    @discardableResult
    func createContainerChild(layout: Layout, at: InsertionPolicy) -> ContainerNode {
        let node = ContainerNode(layout, parent: self)
        children_.append(.container(node))
        return node
    }

    @discardableResult
    func createWindowChild(_ window: Swindler.Window, at: InsertionPolicy) -> WindowNode {
        let node = WindowNode(window, parent: self)
        children_.append(.window(node))
        return node
    }

    func addChild(_ child: MovingNode, at: InsertionPolicy) {
        switch child.node {
        case .container(let node):
            node.reparent(newParent: self)
        case .window(let node):
            node.reparent(newParent: self)
        }
        children_.append(child.node)
    }

    func removeChild(_ node: Node) -> MovingNode? {
        guard let index = children.index(where: {$0.node === node}) else {
            return nil
        }
        let movingNode = MovingNode(children[index])
        children_.remove(at: index)
        return movingNode
    }
}

extension ContainerNode: NodeType {
    func contains(window: Swindler.Window) -> Bool {
        return children.contains(where: {$0.node.contains(window: window)})
    }
}

class WindowNode: Node {
    let window: Swindler.Window

    fileprivate init(_ window: Swindler.Window, parent: ContainerNode) {
        self.window = window
        super.init(parent: parent)
    }
}

extension WindowNode: NodeType {
    func contains(window: Swindler.Window) -> Bool {
        return self.window == window
    }
}

extension ContainerNode: CustomDebugStringConvertible {
    var debugDescription: String {
        return "\(layout), \(String(describing: children.map{$0.node}))"
    }
}

extension WindowNode: CustomDebugStringConvertible {
    var debugDescription: String {
        return String(describing: window)
    }
}
