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

class WindowManager {
    var state: Swindler.State

    let hotKeys: HotKeyManager

    var tree: TreeWrapper
    var focus: Crawler?

    init(state: Swindler.State) {
        self.state = state
        self.tree = TreeWrapper(Tree(screen: state.screens.last!))
        self.focus = nil

        //NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
        //    debugPrint("Got event: \(event)")
        //}

        hotKeys = HotKeyManager()
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
            debugPrint(String(describing:
                self.state.frontmostApplication.value?.mainWindow.value?.title.value))
            if let window = self.state.frontmostApplication.value?.mainWindow.value {
                self.tree.with { tree in
                    if !tree.root.contains(window: window) {
                        let node = tree.root.createWindow(window, at: .end)
                        self.focus = Crawler(at: node)
                    }
                }
                debugPrint(String(describing: self.tree.peek()))
            }
        }
        hotKeys.register(keyCode: kVK_ANSI_R, modifierKeys: optionKey) {
            self.tree.peek().refresh()
        }

        // Update tree in response to window being destroyed.
        state.on { (event: WindowDestroyedEvent) in
            self.tree.with { tree in
                if let node = tree.find(window: event.window) {
                    if self.focus?.node.base == node {
                        self.focus = nil
                    }
                    node.destroy()
                }
            }
        }

        // Update focus in response to focused window changing.
        // TODO: Add FocusedWindowChangedEvent to Swindler
        state.on { (event: FrontmostApplicationChangedEvent) in
            self.updateFocus(window: event.newValue?.focusedWindow.value)
        }
        state.on { (event: ApplicationFocusedWindowChangedEvent) in
            if event.application == self.state.frontmostApplication.value {
                self.updateFocus(window: event.newValue)
            }
        }
    }

    func updateFocus(window: Window?) {
        guard let window = window else { return }
        guard let node = tree.peek().find(window: window) else { return }
        focus = Crawler(at: node)
    }

    func moveFocus(_ direction: Direction) {
        guard let next = focus?.move(direction) else {
            return
        }
        focus = next
        if case .window(let windowNode) = next.node {
            raise(windowNode.window)
        }
    }

    func raise(_ window: Window) {
        // TODO: Add this method to Swindler
        window.application.mainWindow.set(window).then { _ in
            return self.state.frontmostApplication.set(window.application)
        }.catch { err in
            print("Error raising window \(window): \(err)")
        }
    }
}
