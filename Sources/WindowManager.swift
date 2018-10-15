import Carbon
import Swindler

struct TreeWrapper {
    private var tree: Tree

    init(_ tree: Tree) {
        self.tree = tree
    }
}
extension TreeWrapper {
    /// Use this when modifying the tree. It always ensures refresh is called.
    func with(_ f: (Tree) -> Void) -> Void {
        f(self.tree)
        self.tree.refresh()
    }

    /// Use this when only inspecting the tree. You must not modify the tree using the return value
    /// of this function!
    func peek() -> Tree {
        return self.tree
    }
}

extension Swindler.State {
    var focusedWindow: Window? {
        get {
            return self.frontmostApplication.value?.mainWindow.value
        }
    }
}

/// Defines the basic window management operations and their behavior.
class WindowManager {
    var state: Swindler.State

    var tree: TreeWrapper
    var focus: Crawler?

    public init(state: Swindler.State) {
        self.state = state
        self.tree = TreeWrapper(Tree(screen: state.screens.last!))
        self.focus = nil

        state.on { (event: WindowDestroyedEvent) in
            self.onWindowDestroyed(event.window)
        }

        // TODO: Add FocusedWindowChangedEvent to Swindler
        state.on { (event: FrontmostApplicationChangedEvent) in
            self.onFocusedWindowChanged(window: event.newValue?.focusedWindow.value)
        }
        state.on { (event: ApplicationFocusedWindowChangedEvent) in
            if event.application == self.state.frontmostApplication.value {
                self.onFocusedWindowChanged(window: event.newValue)
            }
        }
    }

    func registerHotKeys(_ hotKeys: HotKeyManager) {
        hotKeys.register(keyCode: kVK_ANSI_L, modifierKeys: optionKey) {
            self.moveFocus(.right)
        }
        hotKeys.register(keyCode: kVK_ANSI_H, modifierKeys: optionKey) {
            self.moveFocus(.left)
        }
        hotKeys.register(keyCode: kVK_ANSI_J, modifierKeys: optionKey) {
            self.moveFocus(.down)
        }
        hotKeys.register(keyCode: kVK_ANSI_K, modifierKeys: optionKey) {
            self.moveFocus(.up)
        }

        hotKeys.register(keyCode: kVK_ANSI_X, modifierKeys: optionKey) {
            if let window = self.state.focusedWindow {
                self.addWindow(window)
            }
        }
        hotKeys.register(keyCode: kVK_ANSI_R, modifierKeys: optionKey) {
            self.tree.peek().refresh()
        }

        hotKeys.register(keyCode: kVK_ANSI_Minus, modifierKeys: optionKey) {
            if let node = self.focus?.node {
                self.insertContainerAbove(node, layout: .vertical)
            }
        }
        hotKeys.register(keyCode: kVK_ANSI_Backslash, modifierKeys: optionKey) {
            if let node = self.focus?.node {
                self.insertContainerAbove(node, layout: .horizontal)
            }
        }
    }

    func addWindow(_ window: Window) {
        if tree.peek().root.contains(window: window) {
            return
        }
        tree.with { tree in
            var node: WindowNode!
            if let focusNode = focus?.node,
               let parent = focusNode.base.parent {
                node = parent.createWindow(window, at: .after(focusNode))
            } else {
                node = tree.root.createWindow(window, at: .end)
            }
            focus = Crawler(at: node.kind)
            node.selectGlobally()
        }
    }

    func onWindowDestroyed(_ window: Window) {
        tree.with { tree in
            if let node = tree.find(window: window) {
                if self.focus?.node.base == node {
                    self.focus = nil
                }
                node.destroy()
            }
        }
    }

    func moveFocus(_ direction: Direction) {
        guard let next = focus?.move(direction, leaf: .selected) else {
            return
        }
        focus = next

        next.node.base.selectGlobally()
        if case .window(let windowNode) = next.node {
            raise(windowNode.window)
        }
    }

    func moveFocusedWindow(_ direction: Direction) {
    }

    func onFocusedWindowChanged(window: Window?) {
        guard let window = window else { return }
        guard let node = tree.peek().find(window: window) else { return }
        focus = Crawler(at: node)
        node.selectGlobally()
    }

    func raise(_ window: Window) {
        // TODO: Add this method to Swindler
        window.application.mainWindow.set(window).then { _ in
            return self.state.frontmostApplication.set(window.application)
        }.catch { err in
            print("Error raising window \(window): \(err)")
        }
    }

    func insertContainerAbove(_ node: NodeKind, layout: Layout) {
        // FIXME: This modifies the tree without calling tree.with!
        // In this case, it does not affect sizing, but we need a more principled
        // approach here.
        guard let parent = node.base.parent else {
            fatalError("can't reparent the root node")
        }
        let container = parent.createContainer(layout: layout, at: .after(node))
        container.addChild(parent.removeChild(node.base)!, at: .end)
    }
}
