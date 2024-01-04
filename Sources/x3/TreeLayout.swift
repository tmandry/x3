import Cocoa
import Swindler

struct TreeWrapper {
    private var tree: Tree
    private var idToWindow: [WindowId: Window]

    init(_ tree: Tree) {
        self.tree = tree
        self.idToWindow = [:]
    }
}
extension TreeWrapper {
    /// Use this when modifying the tree. It always ensures refresh is called.
    func with(_ f: (Tree) -> Void) -> Void {
        f(self.tree)
        //self.tree.refresh()
    }

    /// Use this when only inspecting the tree. You must not modify the tree using the return value
    /// of this function!
    func peek() -> Tree {
        return self.tree
    }

    //func addWindow
}

extension NodeKind {
    func toCrawler() -> Crawler {
        return Crawler(at: self)
    }
}

public final class TreeLayout {
    var tree: TreeWrapper
    var focus: Crawler?

    init(_ tree: Tree) {
        self.tree = TreeWrapper(tree)
    }

    public var focusedWindow: Window? {
        guard let node = focus?.node else { return nil }
        guard case .window(let windowNode) = node else { return nil }
        return windowNode.window
    }

    func addWindow(_ window: Window) {
        _ = addWindowReturningNode(window)
    }

    // For testing only.
    func addWindowReturningNode(_ window: Window) -> WindowNode? {
        if tree.peek().root.contains(window: window) {
            return nil
        }

        var node: WindowNode!
        tree.with { tree in
            if let focusNode = focus?.node,
               let parent = focusNode.base.parent {
                node = parent.createWindow(window, at: .after(focusNode))
            } else {
                node = tree.root.createWindow(window, at: .end)
            }

            // Question: Do we always want to focus new windows?
            node.selectGlobally()
            focus = Crawler(at: node.kind)
        }

        return node
    }

    func removeCurrentWindow() {
        guard let node = self.focus?.node else {
            return
        }
        self.focus = nil
        node.base.removeFromTree()
    }

    func onWindowDestroyed(_ window: Window) {
        tree.with { tree in
            if let node = tree.find(window: window) {
                let parent = node.parent
                node.destroy()
                if node == focus?.node.base {
                    // TODO: Is this always correct? What if parent has no other
                    // children, or is culled?
                    focus = parent?.selection?.toCrawler()
                }
            }
        }
    }

    func onUserResize(_ window: Window, oldFrame: CGRect, newFrame: CGRect) {
        log.debug("onUserResize: \(window) \(String(describing: oldFrame)) -> \(String(describing: newFrame))")
        tree.peek().resizeWindowAndRefresh(window, oldFrame: oldFrame, newFrame: newFrame)
        log.debug("onUserResize end: \(window)")
    }

    func onFocusedWindowChanged(window: Window?) {
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
        log.debug("onFocusedWindowChanged: \(String(describing: window))")
        guard let window = window else { return }
        guard let node = tree.peek().find(window: window) else { return }
        focus = Crawler(at: node)
        node.selectGlobally()
    }

    func onScreenChanged(_ screen: Screen) {
        if screen != tree.peek().screen {
            tree.with { tree in
                tree.screen = screen
            }
        }
    }

    func moveFocus(_ direction: Direction) {
        guard let next = focus?.move(direction, leaf: .selected) else {
            return
        }
        focus = next

        next.node.base.selectGlobally()
    }

    func focusParent() {
        guard let parent = focus?.node.base.parent else {
            return
        }
        focus = Crawler(at: parent)
    }

    func focusChild() {
        guard let child = focus?.node.containerNode?.selection else {
            return
        }
        focus = Crawler(at: child)
    }

    func moveFocusedNode(_ direction: Direction) {
        guard let node = focus?.node else {
            return
        }
        tree.with { tree in
            node.move(inDirection: direction)
        }
    }

    func resize(to direction: Direction, screenPct: Float) {
        guard let node = focus?.node else {
            return
        }
        tree.with { tree in
            node.resize(byScreenPercentage: screenPct, inDirection: direction)
        }
    }

    func split(_ layout: Layout) {
        if let node = self.focus?.node {
            putContainerAbove(node, layout: layout)
        } else {
            tree.peek().root.layout = layout
        }
    }

    func putContainerAbove(_ node: NodeKind, layout: Layout) {
        // FIXME: This modifies the tree without calling tree.with!
        // In this case, it does not affect sizing, but we need a more principled
        // approach here. Think Binder in rustc.
        if let parent = node.base.parent, parent.children.count == 1 {
            // This node already has a container around itself; just set the layout.
            // This won't affect sizes.
            parent.layout = layout
            return
        }

        node.node.insertParent(layout: layout)
    }

    /// Converts the parent of the current node to tabbed or stacked layout.
    func stack(layout: Layout) {
        assert(layout == .tabbed || layout == .stacked)
        guard let parent = self.focus?.node.parent else { return }
        tree.with { tree in
            if parent.layout == .horizontal || parent.layout == .vertical {
                parent.wmData.unstackLayout = parent.layout
            }
            parent.layout = layout
        }
    }

    /// Converts the parent of the current node back to the unstacked layout it
    /// was in previously.
    func unstack() {
        guard let parent = self.focus?.node.parent else { return }
        if parent.layout == .horizontal || parent.layout == .vertical {
            return
        }
        tree.with { tree in
            // This node must have had an unstacked layout previously.
            parent.layout = parent.wmData.unstackLayout!
        }
    }

    func forceRefresh() {
        self.tree.peek().refresh()
    }
}

extension TreeLayout: CustomDebugStringConvertible {
    public var debugDescription: String {
        String(describing: tree.peek().root)
    }
}
