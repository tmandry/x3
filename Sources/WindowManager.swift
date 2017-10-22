import Carbon
import Swindler

enum Layout {
    case Horizontal
    case Vertical
    case Stacked
}

class Node {
    // TODO: Create parallel enums, one representing contents that belong to a node, another
    // representing "released" contents, to make moving contents around safer.
    var contents: NodeContents
    var parent: ParentNode?

    fileprivate init(_ contents: NodeContents) {
        self.contents = contents
    }

    init(_ contents: NodeContents, parent: ParentNode)
    {
        self.contents = contents
        self.parent = parent
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

class ParentNode: Node {
    init(_ type: Layout, _ children: [Node], parent: ParentNode?) {
        if let parent = parent {
            super.init(.Parent(type, children), parent: parent)
        } else {
            super.init(.Parent(type, children))
        }
    }

    func addChild(_ child: NodeContents) {
        switch contents {
        case .Parent(let layout, var children):
            children.append(Node(child, parent: self))
            contents = .Parent(layout, children)
        case .Window:
            fatalError("Can't addChild on a Window node")
        }
    }
}

extension Node: CustomDebugStringConvertible {
    var debugDescription: String {
        return String(describing: contents)
    }
}

enum NodeContents {
    case Window(Swindler.Window)
    indirect case Parent(Layout, [Node])
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
                    self.tree.addChild(.Window(window))
                }
                debugPrint(String(describing: self.tree))
            }
        }
    }
}
