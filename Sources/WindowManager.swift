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

extension NodeKind {
    func toCrawler() -> Crawler {
        return Crawler(at: self)
    }
}

/// Defines the basic window management operations and their behavior.
class WindowManager {
    var state: Swindler.State

    var tree: TreeWrapper
    var focus: Crawler?

    public var focusedWindow: Window? {
        guard let node = focus?.node else { return nil }
        guard case .window(let windowNode) = node else { return nil }
        return windowNode.window
    }

    public init(state: Swindler.State) {
        self.state = state
        let top = state.screens.map{$0.frame.maxY}.max()!
        self.tree = TreeWrapper(Tree(screen: state.screens.last!, top: top))
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

        hotKeys.register(keyCode: kVK_ANSI_L, modifierKeys: optionKey | shiftKey) {
            self.moveFocusedNode(.right)
        }
        hotKeys.register(keyCode: kVK_ANSI_H, modifierKeys: optionKey | shiftKey) {
            self.moveFocusedNode(.left)
        }
        hotKeys.register(keyCode: kVK_ANSI_J, modifierKeys: optionKey | shiftKey) {
            self.moveFocusedNode(.down)
        }
        hotKeys.register(keyCode: kVK_ANSI_K, modifierKeys: optionKey | shiftKey) {
            self.moveFocusedNode(.up)
        }

        hotKeys.register(keyCode: kVK_ANSI_D, modifierKeys: optionKey | shiftKey) {
            print(self.tree.peek().root)
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

            // Question: Do we always want to focus new windows?
            node.selectGlobally()
            focus = Crawler(at: node.kind)
            raiseFocus()
        }
    }

    private func onWindowDestroyed(_ window: Window) {
        tree.with { tree in
            if let node = tree.find(window: window) {
                let parent = node.parent
                node.destroy()
                if node == focus?.node.base {
                    // TODO: Is this always correct? What if parent has no other
                    // children, or is culled?
                    focus = parent?.selection?.toCrawler()
                    raiseFocus()
                }
            }
        }
    }

    func moveFocus(_ direction: Direction) {
        guard let next = focus?.move(direction, leaf: .selected) else {
            return
        }
        focus = next

        next.node.base.selectGlobally()
        raiseFocus()
    }

    func moveFocusedNode(_ direction: Direction) {
        guard let node = focus?.node else {
            return
        }
        tree.with { tree in
            node.move(inDirection: direction)
        }
    }

    private func onFocusedWindowChanged(window: Window?) {
        // TODO: This can happen when a window is destroyed and the OS
        // automatically focuses another window from the same application. We
        // should ignore these events instead of letting them influence
        // selection.
        //
        // One way to do this is to simply add a delay on external events, but
        // this won't be as reliable. Another way is tracking our raise requests
        // and "locking" selection until they complete. This requires careful
        // error handling (what if the window we raise is destroyed first? what
        // if the request times out?)
        guard let window = window else { return }
        guard let node = tree.peek().find(window: window) else { return }
        focus = Crawler(at: node)
        node.selectGlobally()
    }

    private func raiseFocus() {
        guard let focus = focus,
              case .window(let windowNode) = focus.node else {
            return
        }
        raise(windowNode.window)
    }

    private func raise(_ window: Window) {
        // TODO: Add this method to Swindler
        window.application.mainWindow.set(window).then { _ in
            // TODO: Possible race condition here. If a new window is raised
            // before the app responds to our above request, we should cancel
            // the following operation.
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
