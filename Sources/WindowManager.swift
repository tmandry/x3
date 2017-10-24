import Carbon
import Swindler

enum Layout {
    case Horizontal
    case Vertical
    case Stacked
}

// The contents of a Node.
enum NodeContents {
    case Window(Swindler.Window)
    case Parent(Layout, [Node])
}

// The contents of a Node that has been removed; these can be added to a new ParentNode.
enum MovingContents {
    case Window(Swindler.Window)
    case Parent(Layout, [Node])
}

struct Tree {
    let root: ParentNode
    init() {
        root = ParentNode(.Horizontal, [], nil)
    }
}

class Node {
    // TODO: Create parallel enums, one representing contents that belong to a node, another
    // representing "released" contents, to make moving contents around safer.
    var contents: NodeContents
    var parent: ParentNode?

    fileprivate init(_ contents: NodeContents) {
        self.contents = Node.fromMoving(contents)
    }

    fileprivate init(_ contents: NodeContents, parent: ParentNode) {
        self.contents = Node.fromMoving(contents)
        self.parent = parent
    }

    private static func fromMoving(_ contents: NodeContents) -> NodeContents {
        switch contents {
        case .Parent(let layout, let children):
            return .Parent(layout, children)
        case .Window(let window):
            return .Window(window)
        }
    }

    func contains(window: Swindler.Window) -> Bool {
        switch contents {
        case .Parent(_, let children):
            return children.contains(where: {$0.contains(window: window)})
        case .Window(let myWindow):
            return myWindow == window
        }
    }
}

struct MovingNode {
    let node: Node
    fileprivate init(_ node: Node) {
        self.node = node
    }
}

class ParentNode: Node {
    enum InsertionPolicy {
        case end
    }

    fileprivate init(_ type: Layout, _ children: [Node], parent: ParentNode?) {
        if let parent = parent {
            super.init(.Parent(type, children), parent: parent)
        } else {
            super.init(.Parent(type, children))
        }
    }

    func createChild(contents childContents: NodeContents, at: InsertionPolicy) -> Node {
        var node: Node?
        switch childContents {
        case .Parent(let layout, let children):
            node = ParentNode(layout, children, parent: self)
        case .Window(let window):
            node = Node(childContents, parent: self)
        }
        switch contents {
        case .Parent(let layout, var children):
            children.append(node!)
            contents = .Parent(layout, children)
        default:
            fatalError("ParentNode can't have non-parent contents")
        }
        return node!
    }

    func addChild(_ child: MovingNode) {
        switch contents {
        case .Parent(let layout, var children):
            children.append(Node(child.node.contents, parent: self))
            contents = .Parent(layout, children)
        default:
            fatalError("ParentNode can't have non-parent contents")
        }
    }

    func removeChild(_ node: Node) -> MovingNode? {
        switch contents {
        case .Parent(let layout, var children):
            guard let index = children.index(where: {$0 === node}) else {
                return nil
            }
            children.remove(at: index)
            contents = .Parent(layout, children)
            return MovingNode(node)
        default:
            fatalError("ParentNode can't have non-parent contents")
        }
    }
}

extension Node: CustomDebugStringConvertible {
    var debugDescription: String {
        return String(describing: contents)
    }
}

class WindowManager {
    var state: Swindler.State
    var tree: ParentNode
    let hotKeys: HotKeyManager

    init(state: Swindler.State) {
        self.state = state
        tree = ParentNode(.Horizontal, [], parent: nil)

        //NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
        //    debugPrint("Got event: \(event)")
        //}

        hotKeys = HotKeyManager()
        hotKeys.register(keyCode: kVK_ANSI_L, modifierKeys: optionKey) {
            debugPrint("woohoo!")
        }
        hotKeys.register(keyCode: kVK_ANSI_H, modifierKeys: optionKey) {
            debugPrint("wahhah!")
        }
        hotKeys.register(keyCode: kVK_ANSI_X, modifierKeys: optionKey) {
            debugPrint(String(describing:
                self.state.frontmostApplication.value?.mainWindow.value?.title.value))
            if let window = self.state.frontmostApplication.value?.mainWindow.value {
                if !self.tree.contains(window: window) {
                    self.tree.addChild(MovingNode(Node(.Window(window))))
                }
                debugPrint(String(describing: self.tree))
            }
        }
    }
}
